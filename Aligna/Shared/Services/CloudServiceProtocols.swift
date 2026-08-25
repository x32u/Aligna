import Foundation

nonisolated struct SignUpRequest: Sendable {
    let email: String
    let password: String
    let displayName: String
    let handle: String
}

nonisolated enum AuthenticationEvent: Equatable, Sendable {
    case initialSession(AuthenticatedUser?)
    case signedIn(AuthenticatedUser)
    case signedOut
    case passwordRecovery(AuthenticatedUser)
    case tokenRefreshed(AuthenticatedUser)
}

nonisolated enum AuthenticationServiceError: LocalizedError, Equatable {
    case invalidCredentials
    case emailNotVerified
    case emailAlreadyRegistered
    case usernameAlreadyUsed
    case weakPassword
    case samePassword
    case emailRateLimited
    case rateLimited
    case offline
    case invalidCallback
    case expiredVerificationLink
    case expiredRecoveryLink
    case callbackCancelled
    case unexpected
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "The email or password is incorrect."
        case .emailNotVerified:
            "Verify your email before signing in."
        case .emailAlreadyRegistered:
            "An account already exists for this email. Go back and sign in."
        case .usernameAlreadyUsed:
            "That username is already taken."
        case .weakPassword:
            "Choose a stronger password that meets the requirements below."
        case .samePassword:
            "Choose a password you haven’t used for this account."
        case .emailRateLimited:
            "Too many emails were requested. Wait before requesting another verification or recovery email."
        case .rateLimited:
            "Too many attempts. Wait a moment, then try again."
        case .offline:
            "Aligna couldn’t connect. Check your internet connection."
        case .invalidCallback:
            "This link is invalid. Request a new email and try again."
        case .expiredVerificationLink:
            "This verification link has expired or was already used. Request a new email."
        case .expiredRecoveryLink:
            "This recovery link has expired or was already used. Request a new one."
        case .callbackCancelled:
            "The link was cancelled before it could be completed."
        case .unexpected:
            "Something unexpected happened. Please try again."
        case let .message(message):
            message
        }
    }
}

protocol AuthenticationServicing: Sendable {
    func restoredUser() async throws -> AuthenticatedUser?
    func currentUser() async throws -> AuthenticatedUser?
    func authenticationEvents() -> AsyncStream<AuthenticationEvent>
    func signUp(_ request: SignUpRequest) async throws -> AuthenticatedUser
    func signIn(email: String, password: String) async throws
        -> AuthenticatedUser
    func signOut() async throws
    func resendVerification(email: String) async throws
    func sendPasswordReset(email: String) async throws
    func updatePassword(_ password: String) async throws
    func handleCallback(_ url: URL) async throws -> AuthCallbackResult
}

protocol ProfileRepository: Sendable {
    func profile(userID: UUID) async throws -> UserProfile?
    func update(
        userID: UUID,
        displayName: String,
        handle: String,
        avatarPath: String?,
        onboardingCompleted: Bool
    ) async throws -> UserProfile
}

protocol WorkspaceRepository: Sendable {
    func workspaces() async throws -> [Workspace]
    func invitations() async throws -> [WorkspaceInvitation]
    func createWorkspace(name: String) async throws -> Workspace
    func members(workspaceID: UUID) async throws -> [WorkspaceMember]
    func pendingInvitations(workspaceID: UUID) async throws
        -> [ManagedWorkspaceInvitation]
    func findProfile(exactHandle: String) async throws
        -> ProfileLookupResult?
    func invite(workspaceID: UUID, userID: UUID) async throws
        -> WorkspaceInvitation
    func respond(invitationID: UUID, accept: Bool) async throws
    func cancel(invitationID: UUID) async throws
    func setRole(
        workspaceID: UUID,
        userID: UUID,
        role: WorkspaceRole
    ) async throws
    func removeMember(workspaceID: UUID, userID: UUID) async throws
    func rename(workspaceID: UUID, name: String) async throws
}

protocol MeetingCloudRepository: Sendable {
    func synchronize(
        _ meeting: Meeting,
        workspaceID: UUID,
        organizerID: UUID,
        participantUserIDs: [UUID]
    ) async throws
    func delete(meetingID: UUID) async throws
}

protocol AvatarStorage: Sendable {
    func uploadJPEG(_ data: Data, userID: UUID) async throws -> String
    func removeAvatar(userID: UUID) async throws
    func signedURL(path: String) async throws -> URL
}

protocol AccountDeletionServicing: Sendable {
    func deleteAccount(
        confirmingSoleMemberWorkspaceDeletion: Bool
    ) async throws
}
