import Foundation
import Observation

@MainActor
@Observable
final class AppSession {
    enum State: Equatable {
        case launching
        case configurationMissing(String)
        case signedOut
        case awaitingEmailVerification
        case profileIncomplete
        case voiceSetup
        case workspaceRequired
        case authenticated
        case failed(String)
    }

    private(set) var state: State
    private(set) var user: AuthenticatedUser?
    private(set) var profile: UserProfile?
    private(set) var workspaces: [Workspace] = []
    private(set) var invitations: [WorkspaceInvitation] = []
    private(set) var currentWorkspace: Workspace?
    private(set) var isPerformingOperation = false
    private(set) var operationError: String?
    private(set) var emailVerificationStatus:
        EmailVerificationStatus = .waiting
    private(set) var passwordRecoveryStatus:
        PasswordRecoveryStatus = .idle
    private(set) var authNotice: AuthNotice?
    var isPresentingPasswordUpdate = false
    var pendingVerificationEmail = ""
    var pendingPasswordResetEmail = ""
    private(set) var verificationEmailRequestedAt: Date?

    let dependencies: DependencyContainer

    private var authListenerTask: Task<Void, Never>?
    private var hasStarted = false
    private var callbackKindInProgress: AuthCallbackKind?
    private var isRecoveryFlowActive = false
    private var callbackGeneration = 0
    private var activeCallbackFingerprint: String?
    private var completedCallbackFingerprints: Set<String> = []

    init(
        dependencies: DependencyContainer,
        initialState: State = .launching
    ) {
        self.dependencies = dependencies
        state = initialState
    }

    static func configurationMissing(_ error: Error) -> AppSession {
        AppSession(
            dependencies: .preview(user: nil, profile: nil, workspaces: []),
            initialState: .configurationMissing(
                error.localizedDescription
            )
        )
    }

    func start() async {
        guard !hasStarted, state == .launching else { return }
        hasStarted = true
        startAuthListener()
        let callbackGenerationAtStart = callbackGeneration

        do {
            let restored = try await dependencies.authentication.restoredUser()
            guard callbackGenerationAtStart == callbackGeneration,
                  activeCallbackFingerprint == nil,
                  completedCallbackFingerprints.isEmpty
            else {
                return
            }
            guard !isRecoveryFlowActive else {
                state = .signedOut
                return
            }
            guard let restored else {
                clearIdentity()
                state = .signedOut
                return
            }
            await route(user: restored)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func signUp(_ request: SignUpRequest) async -> Bool {
        await perform {
            let user = try await dependencies.authentication.signUp(request)
            self.user = user
            pendingVerificationEmail = user.email
            verificationEmailRequestedAt =
                user.verificationEmailSentAt ?? .now
            emailVerificationStatus = .waiting
            authNotice = nil
            if user.isEmailVerified {
                await route(user: user)
            } else {
                state = .awaitingEmailVerification
            }
        }
    }

    @discardableResult
    func signIn(email: String, password: String) async -> Bool {
        await perform {
            authNotice = nil
            let user = try await dependencies.authentication.signIn(
                email: email,
                password: password
            )
            await route(user: user)
        }
    }

    @discardableResult
    func resendVerification(at date: Date = .now) async -> Bool {
        let email = pendingVerificationEmail
        guard EmailValidator.isValid(email) else { return false }
        guard verificationResendRemainingSeconds(at: date) == 0 else {
            operationError =
                "Please wait before requesting another verification email."
            return false
        }
        let didSend = await perform {
            try await dependencies.authentication.resendVerification(
                email: email
            )
        }
        if didSend {
            verificationEmailRequestedAt = date
            emailVerificationStatus = .resent
        }
        return didSend
    }

    func verificationResendRemainingSeconds(at date: Date = .now) -> Int {
        guard let verificationEmailRequestedAt else { return 0 }
        let nextAllowedAt = verificationEmailRequestedAt.addingTimeInterval(
            SignUpConfirmationPolicy.resendCooldown
        )
        return max(0, Int(ceil(nextAllowedAt.timeIntervalSince(date))))
    }

    @discardableResult
    func sendPasswordReset(email: String) async -> Bool {
        let normalizedEmail = EmailValidator.normalized(email)
        guard EmailValidator.isValid(normalizedEmail) else { return false }
        let didSend = await perform {
            try await dependencies.authentication.sendPasswordReset(
                email: normalizedEmail
            )
        }
        if didSend {
            pendingPasswordResetEmail = normalizedEmail
            passwordRecoveryStatus = .linkSent(normalizedEmail)
        }
        return didSend
    }

    @discardableResult
    func updatePassword(_ password: String) async -> Bool {
        let didUpdate = await perform {
            try await dependencies.authentication.updatePassword(password)
        }
        guard didUpdate else { return false }

        try? await dependencies.authentication.signOut()
        isRecoveryFlowActive = false
        clearIdentity()
        state = .signedOut
        authNotice = AuthNotice(
            style: .success,
            message: "Password updated. Sign in with your new password."
        )
        return true
    }

    func handle(url: URL) async {
        let fingerprint = AuthRedirectConfiguration.fingerprint(url)
        guard activeCallbackFingerprint != fingerprint,
              !completedCallbackFingerprints.contains(fingerprint)
        else {
            return
        }
        guard !isPerformingOperation else { return }

        let expectedKind = AuthRedirectConfiguration.callbackKind(from: url)
            ?? AuthCallbackIntentStore.current()
            ?? (pendingPasswordResetEmail.isEmpty
                ? .emailVerification
                : .passwordRecovery)

        callbackGeneration += 1
        activeCallbackFingerprint = fingerprint
        callbackKindInProgress = expectedKind
        isRecoveryFlowActive = expectedKind == .passwordRecovery
        isPerformingOperation = true
        operationError = nil

        if expectedKind == .emailVerification {
            emailVerificationStatus = .checking
        } else {
            passwordRecoveryStatus = .processing
        }

        defer {
            activeCallbackFingerprint = nil
            callbackKindInProgress = nil
            isPerformingOperation = false
        }

        do {
            let result = try await dependencies.authentication
                .handleCallback(url)
            completedCallbackFingerprints.insert(fingerprint)
            switch result.kind {
            case .emailVerification:
                isRecoveryFlowActive = false
                emailVerificationStatus = .waiting
                await route(user: result.user)
            case .passwordRecovery:
                user = result.user
                passwordRecoveryStatus = .ready
                state = .signedOut
                isPresentingPasswordUpdate = true
            }
        } catch {
            if expectedKind == .emailVerification,
               let current = try? await dependencies.authentication
                   .currentUser(),
               current.isEmailVerified {
                completedCallbackFingerprints.insert(fingerprint)
                isRecoveryFlowActive = false
                emailVerificationStatus = .waiting
                operationError = nil
                await route(user: current)
                return
            }

            let message = error.localizedDescription
            operationError = message
            if expectedKind == .emailVerification {
                if error as? AuthenticationServiceError
                    == .expiredVerificationLink {
                    emailVerificationStatus = .expired
                } else {
                    emailVerificationStatus = .failed(message)
                }
            } else {
                isRecoveryFlowActive = false
                if error as? AuthenticationServiceError
                    == .expiredRecoveryLink {
                    passwordRecoveryStatus = .expired
                } else {
                    passwordRecoveryStatus = .failed(message)
                }
            }
        }
    }

    @discardableResult
    func checkEmailVerification() async -> Bool {
        emailVerificationStatus = .checking
        let didVerify = await perform {
            guard let current = try await dependencies.authentication
                .currentUser(),
                current.isEmailVerified
            else {
                throw AuthenticationServiceError.message(
                    "We haven’t confirmed your email yet. Open the newest link, then try again."
                )
            }
            await route(user: current)
        }

        if !didVerify {
            emailVerificationStatus = .failed(
                operationError ?? "We couldn’t confirm your email."
            )
        }
        return didVerify
    }

    func refreshAuthenticationState() async {
        guard !isPerformingOperation, !isRecoveryFlowActive else { return }

        do {
            guard let current = try await dependencies.authentication
                .currentUser()
            else {
                if state != .signedOut && state != .launching {
                    clearIdentity()
                    state = .signedOut
                }
                return
            }

            if state == .awaitingEmailVerification {
                guard current.isEmailVerified else { return }
                await route(user: current)
            } else if state == .authenticated
                || state == .profileIncomplete
                || state == .voiceSetup
                || state == .workspaceRequired {
                user = current
            }
        } catch {
            if state == .awaitingEmailVerification {
                operationError = error.localizedDescription
                emailVerificationStatus = .failed(
                    error.localizedDescription
                )
            }
        }
    }

    func useDifferentEmail() async {
        try? await dependencies.authentication.signOut()
        isRecoveryFlowActive = false
        clearIdentity()
        authNotice = nil
        state = .signedOut
    }

    func signOut() async {
        await perform {
            try await dependencies.authentication.signOut()
            clearIdentity()
            state = .signedOut
        }
    }

    func saveProfile(
        displayName: String,
        handle: String,
        avatarJPEG: Data?,
        removeAvatar: Bool,
        completeOnboarding: Bool = true
    ) async {
        guard let user else { return }
        await perform {
            var avatarPath = profile?.avatarPath
            if removeAvatar {
                try await dependencies.avatars.removeAvatar(userID: user.id)
                avatarPath = nil
            }
            if let avatarJPEG {
                avatarPath = try await dependencies.avatars.uploadJPEG(
                    avatarJPEG,
                    userID: user.id
                )
            }

            profile = try await dependencies.profiles.update(
                userID: user.id,
                displayName: displayName,
                handle: handle,
                avatarPath: avatarPath,
                onboardingCompleted: completeOnboarding
            )
            await refreshCollaboration()
        }
    }

    func finishVoiceSetup(
        as status: VoiceEnrollmentStatus
    ) async {
        guard status == .enrolled || status == .skipped else { return }
        let didUpdate = await perform {
            try await dependencies.voiceProfiles.updateStatus(status)
            profile?.voiceEnrollmentStatus = status
            if let user, let profile,
               let handle = profile.handle {
                self.profile = try await dependencies.profiles.update(
                    userID: user.id,
                    displayName: profile.displayName,
                    handle: handle,
                    avatarPath: profile.avatarPath,
                    onboardingCompleted: true
                )
            }
        }
        if didUpdate {
            await refreshCollaboration()
        }
    }

    func deleteVoiceProfile() async {
        let didDelete = await perform {
            try await dependencies.voiceProfiles.deleteProfile()
            profile?.voiceEnrollmentStatus = .notStarted
        }
        if didDelete {
            await refreshCollaboration()
        }
    }

    func createWorkspace(name: String) async {
        await perform {
            let workspace = try await dependencies.workspaces
                .createWorkspace(name: name)
            workspaces.append(workspace)
            currentWorkspace = workspace
            state = .authenticated
        }
    }

    func respond(to invitation: WorkspaceInvitation, accept: Bool) async {
        await perform {
            try await dependencies.workspaces.respond(
                invitationID: invitation.id,
                accept: accept
            )
            await refreshCollaboration()
        }
    }

    func refreshCollaboration() async {
        guard user != nil else { return }
        do {
            async let fetchedWorkspaces = dependencies.workspaces.workspaces()
            async let fetchedInvitations = dependencies.workspaces
                .invitations()
            workspaces = try await fetchedWorkspaces
            invitations = try await fetchedInvitations

            if let selected = currentWorkspace,
               let refreshed = workspaces.first(where: {
                   $0.id == selected.id
               }) {
                currentWorkspace = refreshed
            } else {
                currentWorkspace = workspaces.first
            }

            switch OnboardingCoordinator.nextStep(
                profile: profile,
                workspaces: workspaces
            ) {
            case .profile:
                state = .profileIncomplete
            case .voice:
                state = .voiceSetup
            case .workspace:
                state = .workspaceRequired
            case .complete:
                state = .authenticated
            }
        } catch {
            operationError = error.localizedDescription
            if workspaces.isEmpty {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func switchWorkspace(to workspace: Workspace) {
        guard workspaces.contains(where: { $0.id == workspace.id }) else {
            return
        }
        currentWorkspace = workspace
    }

    func deleteAccount() async {
        await perform {
            try await dependencies.accountDeletion.deleteAccount(
                confirmingSoleMemberWorkspaceDeletion: true
            )
            clearIdentity()
            state = .signedOut
        }
    }

    func clearOperationError() {
        operationError = nil
    }

    func clearAuthNotice() {
        authNotice = nil
    }

    private func startAuthListener() {
        guard authListenerTask == nil else { return }
        authListenerTask = Task { [weak self] in
            guard let self else { return }
            for await event in dependencies.authentication
                .authenticationEvents() {
                if Task.isCancelled { return }
                await receive(event)
            }
        }
    }

    private func receive(_ event: AuthenticationEvent) async {
        switch event {
        case .initialSession:
            // start() validates the stored session before routing. Ignoring
            // this provisional event prevents a signed-out/authenticated flash.
            break
        case let .signedIn(user), let .tokenRefreshed(user):
            if callbackKindInProgress == .passwordRecovery
                || isRecoveryFlowActive {
                self.user = user
                passwordRecoveryStatus = .ready
                state = .signedOut
                isPresentingPasswordUpdate = true
            } else if callbackKindInProgress == .emailVerification {
                // session(from:) emits signedIn while the callback service is
                // still validating its result. The callback completion is
                // the single authority that routes the verified user.
                self.user = user
            } else {
                await route(user: user)
            }
        case let .passwordRecovery(user):
            self.user = user
            isRecoveryFlowActive = true
            passwordRecoveryStatus = .ready
            state = .signedOut
            isPresentingPasswordUpdate = true
        case .signedOut:
            clearIdentity()
            state = .signedOut
        }
    }

    private func route(user: AuthenticatedUser) async {
        guard !isRecoveryFlowActive else {
            self.user = user
            return
        }
        self.user = user
        pendingVerificationEmail = user.email
        guard user.isEmailVerified else {
            if verificationEmailRequestedAt == nil {
                verificationEmailRequestedAt = user.verificationEmailSentAt
            }
            state = .awaitingEmailVerification
            return
        }

        do {
            profile = try await dependencies.profiles.profile(userID: user.id)
            guard OnboardingCoordinator.nextStep(
                profile: profile,
                workspaces: []
            ) != .profile else {
                state = .profileIncomplete
                return
            }
            await refreshCollaboration()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    private func perform(
        _ operation: () async throws -> Void
    ) async -> Bool {
        guard !isPerformingOperation else { return false }
        isPerformingOperation = true
        operationError = nil
        defer { isPerformingOperation = false }
        do {
            try await operation()
            return true
        } catch {
            operationError = error.localizedDescription
            return false
        }
    }

    private func clearIdentity() {
        user = nil
        profile = nil
        workspaces = []
        invitations = []
        currentWorkspace = nil
        isPresentingPasswordUpdate = false
        pendingVerificationEmail = ""
        pendingPasswordResetEmail = ""
        verificationEmailRequestedAt = nil
        emailVerificationStatus = .waiting
        passwordRecoveryStatus = .idle
    }

    isolated deinit {
        authListenerTask?.cancel()
    }
}
