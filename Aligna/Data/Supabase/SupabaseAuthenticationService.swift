import Foundation
import Supabase

actor SupabaseAuthenticationService: AuthenticationServicing {
    private let client: SupabaseClient
    private let callbackURL: URL

    init(provider: SupabaseClientProvider) {
        client = provider.client
        callbackURL = provider.configuration.callbackURL
    }

    func restoredUser() async throws -> AuthenticatedUser? {
        try await validatedCurrentUser()
    }

    func currentUser() async throws -> AuthenticatedUser? {
        try await validatedCurrentUser()
    }

    nonisolated func authenticationEvents()
        -> AsyncStream<AuthenticationEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, session) in client.auth.authStateChanges {
                    switch event {
                    case .initialSession:
                        continuation.yield(
                            .initialSession(
                                session.flatMap {
                                    $0.isExpired ? nil : map($0.user)
                                }
                            )
                        )
                    case .signedIn:
                        if let session, !session.isExpired {
                            continuation.yield(.signedIn(map(session.user)))
                        }
                    case .signedOut, .userDeleted:
                        continuation.yield(.signedOut)
                    case .passwordRecovery:
                        if let session, !session.isExpired {
                            continuation.yield(
                                .passwordRecovery(map(session.user))
                            )
                        }
                    case .tokenRefreshed, .userUpdated:
                        if let session, !session.isExpired {
                            continuation.yield(
                                .tokenRefreshed(map(session.user))
                            )
                        }
                    default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func signUp(_ request: SignUpRequest) async throws
        -> AuthenticatedUser {
        do {
            let response = try await client.auth.signUp(
                email: EmailValidator.normalized(request.email),
                password: request.password,
                data: [
                    "display_name": .string(
                        request.displayName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    ),
                    "handle": .string(
                        HandleValidator.normalized(request.handle)
                    ),
                ],
                redirectTo: callbackURL
            )

            guard !SignUpConfirmationPolicy.isObfuscatedExistingUser(
                identityCount: response.user.identities?.count,
                hasSession: response.session != nil
            ) else {
                throw AuthenticationServiceError.emailAlreadyRegistered
            }

            AuthCallbackIntentStore.remember(.emailVerification)
            return map(
                response.user,
                verificationEmailSentAt: response.user.confirmationSentAt
            )
        } catch {
            throw mapError(error)
        }
    }

    func signIn(email: String, password: String) async throws
        -> AuthenticatedUser {
        do {
            let session = try await client.auth.signIn(
                email: EmailValidator.normalized(email),
                password: password
            )
            guard !session.isExpired else {
                throw AuthenticationServiceError.invalidCredentials
            }
            return map(session.user)
        } catch {
            throw mapError(error)
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
            AuthCallbackIntentStore.clear()
        } catch {
            throw mapError(error)
        }
    }

    func resendVerification(email: String) async throws {
        do {
            try await client.auth.resend(
                email: EmailValidator.normalized(email),
                type: .signup,
                emailRedirectTo: callbackURL
            )
            AuthCallbackIntentStore.remember(.emailVerification)
        } catch {
            throw mapError(error)
        }
    }

    func sendPasswordReset(email: String) async throws {
        do {
            try await client.auth.resetPasswordForEmail(
                EmailValidator.normalized(email),
                redirectTo: callbackURL
            )
            AuthCallbackIntentStore.remember(.passwordRecovery)
        } catch {
            throw mapError(error)
        }
    }

    func updatePassword(_ password: String) async throws {
        do {
            try await client.auth.update(
                user: UserAttributes(password: password)
            )
        } catch {
            throw mapError(error, linkKind: .passwordRecovery)
        }
    }

    func handleCallback(_ url: URL) async throws
        -> AuthCallbackResult {
        let storedKind = AuthCallbackIntentStore.current()
        let kind = AuthRedirectConfiguration.callbackKind(from: url)
            ?? storedKind
            ?? .emailVerification

        if let callbackError = AuthRedirectConfiguration.callbackError(
            from: url,
            fallbackKind: kind
        ) {
            throw callbackError
        }

        guard AuthRedirectConfiguration.accepts(url) else {
            throw AuthenticationServiceError.invalidCallback
        }

        do {
            let session = try await client.auth.session(from: url)
            guard !session.isExpired else {
                throw AuthRedirectConfiguration.expiredError(for: kind)
            }

            var user = map(session.user)

            if kind == .emailVerification,
               !user.isEmailVerified {
                user = map(
                    try await client.auth.user(jwt: session.accessToken)
                )
                guard user.isEmailVerified else {
                    throw AuthenticationServiceError.emailNotVerified
                }
            }

            AuthCallbackIntentStore.clear()
            return AuthCallbackResult(kind: kind, user: user)
        } catch {
            throw mapError(error, linkKind: kind)
        }
    }

    private func validatedCurrentUser() async throws
        -> AuthenticatedUser? {
        do {
            let session = try await client.auth.session
            guard !session.isExpired else { return nil }

            let latestUser = try await client.auth.user(
                jwt: session.accessToken
            )
            return map(latestUser)
        } catch {
            if isMissingSession(error) {
                return nil
            }
            throw mapError(error)
        }
    }

    private nonisolated func map(
        _ user: User,
        verificationEmailSentAt: Date? = nil
    ) -> AuthenticatedUser {
        AuthenticatedUser(
            id: user.id,
            email: user.email ?? "",
            isEmailVerified: user.emailConfirmedAt != nil,
            verificationEmailSentAt:
                verificationEmailSentAt ?? user.confirmationSentAt
        )
    }

    private nonisolated func isMissingSession(_ error: Error) -> Bool {
        guard let authError = error as? AuthError else {
            return false
        }
        return [
            ErrorCode.sessionNotFound,
            .refreshTokenNotFound,
            .refreshTokenAlreadyUsed,
        ].contains(authError.errorCode)
    }

    private nonisolated func mapError(
        _ error: Error,
        linkKind: AuthCallbackKind? = nil
    ) -> Error {
        if let serviceError = error as? AuthenticationServiceError {
            return serviceError
        }

        if let urlError = error as? URLError,
           [
               URLError.notConnectedToInternet,
               .networkConnectionLost,
               .timedOut,
               .cannotConnectToHost,
               .cannotFindHost,
           ].contains(urlError.code) {
            return AuthenticationServiceError.offline
        }

        if let authError = error as? AuthError {
            let code = authError.errorCode

            if code == .invalidCredentials {
                return AuthenticationServiceError.invalidCredentials
            }
            if code == .emailNotConfirmed {
                return AuthenticationServiceError.emailNotVerified
            }
            if code == .emailExists || code == .userAlreadyExists {
                return AuthenticationServiceError.emailAlreadyRegistered
            }
            if code == .weakPassword {
                return AuthenticationServiceError.weakPassword
            }
            if code == .samePassword {
                return AuthenticationServiceError.samePassword
            }
            if code == .overEmailSendRateLimit {
                return AuthenticationServiceError.emailRateLimited
            }
            if code == .overRequestRateLimit {
                return AuthenticationServiceError.rateLimited
            }
            if code == .requestTimeout {
                return AuthenticationServiceError.offline
            }
            if [
                ErrorCode.otpExpired,
                .flowStateExpired,
                .flowStateNotFound,
                .badCodeVerifier,
                .sessionExpired,
                .refreshTokenAlreadyUsed,
            ].contains(code) {
                return AuthRedirectConfiguration.expiredError(
                    for: linkKind
                )
            }

            if case let .api(_, _, _, response) = authError,
               response.statusCode == 429 {
                return AuthenticationServiceError.rateLimited
            }
        }

        let message = error.localizedDescription.lowercased()
        if message.contains("profiles_handle_unique")
            || message.contains("handle already") {
            return AuthenticationServiceError.usernameAlreadyUsed
        }
        if message.contains("already registered")
            || message.contains("email already") {
            return AuthenticationServiceError.emailAlreadyRegistered
        }
        if message.contains("expired")
            || message.contains("invalid grant")
            || message.contains("code verifier") {
            return AuthRedirectConfiguration.expiredError(for: linkKind)
        }
        if message.contains("email")
            && message.contains("rate limit") {
            return AuthenticationServiceError.emailRateLimited
        }
        if message.contains("rate limit")
            || message.contains("too many requests") {
            return AuthenticationServiceError.rateLimited
        }

        return AuthenticationServiceError.unexpected
    }
}
