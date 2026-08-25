import CryptoKit
import Foundation

nonisolated enum AuthCallbackKind: String, Equatable, Sendable {
    case emailVerification
    case passwordRecovery
}

nonisolated struct AuthCallbackResult: Equatable, Sendable {
    let kind: AuthCallbackKind
    let user: AuthenticatedUser
}

nonisolated enum SignUpConfirmationPolicy {
    static let resendCooldown: TimeInterval = 60

    static func isObfuscatedExistingUser(
        identityCount: Int?,
        hasSession: Bool
    ) -> Bool {
        !hasSession && identityCount == 0
    }

    static func shouldRequestFreshEmail(
        createdAt: Date,
        confirmationSentAt: Date?,
        now: Date = .now
    ) -> Bool {
        let mostRecentRequest = confirmationSentAt ?? createdAt
        return now.timeIntervalSince(mostRecentRequest) >= resendCooldown
    }
}

nonisolated enum AuthRedirectConfiguration {
    static let scheme = "aligna"
    static let host = "auth"
    static let path = "/callback"
    static let callbackURL = URL(string: "aligna://auth/callback")!

    static func accepts(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
            && url.host?.lowercased() == host
            && normalizedPath(url.path) == path
    }

    static func callbackKind(from url: URL) -> AuthCallbackKind? {
        switch parameters(from: url)["type"]?.lowercased() {
        case "recovery":
            .passwordRecovery
        case "signup", "email", "email_change", "magiclink":
            .emailVerification
        default:
            nil
        }
    }

    static func callbackError(
        from url: URL,
        fallbackKind: AuthCallbackKind?
    ) -> AuthenticationServiceError? {
        guard accepts(url) else {
            return .invalidCallback
        }

        let values = parameters(from: url)
        guard values["error"] != nil
            || values["error_code"] != nil
            || values["error_description"] != nil
        else {
            return nil
        }

        let kind = callbackKind(from: url) ?? fallbackKind
        let combined = [
            values["error"],
            values["error_code"],
            values["error_description"],
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if combined.contains("cancel")
            || combined.contains("access_denied") {
            return .callbackCancelled
        }

        if combined.contains("expired")
            || combined.contains("otp_expired")
            || combined.contains("flow_state")
            || combined.contains("invalid_grant")
            || combined.contains("already been used") {
            return expiredError(for: kind)
        }

        return .invalidCallback
    }

    static func fingerprint(_ url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func expiredError(
        for kind: AuthCallbackKind?
    ) -> AuthenticationServiceError {
        kind == .passwordRecovery
            ? .expiredRecoveryLink
            : .expiredVerificationLink
    }

    private static func normalizedPath(_ value: String) -> String {
        if value.isEmpty || value == "/" {
            return "/"
        }
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }

    private static func parameters(from url: URL) -> [String: String] {
        var values: [String: String] = [:]

        if let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) {
            for item in components.queryItems ?? [] {
                values[item.name] = item.value
            }

            if let fragment = components.fragment,
               let fragmentComponents = URLComponents(
                   string: "?\(fragment)"
               ) {
                for item in fragmentComponents.queryItems ?? [] {
                    values[item.name] = item.value
                }
            }
        }

        return values
    }
}

nonisolated enum AuthCallbackIntentStore {
    private static let key = "aligna.auth.pending-callback-kind"

    static func remember(
        _ kind: AuthCallbackKind,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(kind.rawValue, forKey: key)
    }

    static func current(
        defaults: UserDefaults = .standard
    ) -> AuthCallbackKind? {
        defaults.string(forKey: key).flatMap(AuthCallbackKind.init(rawValue:))
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
