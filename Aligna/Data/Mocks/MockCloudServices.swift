import Foundation

actor MockAuthenticationService: AuthenticationServicing {
    nonisolated private let stream: AsyncStream<AuthenticationEvent>
    nonisolated private let continuation:
        AsyncStream<AuthenticationEvent>.Continuation

    private var user: AuthenticatedUser?
    private var failure: Error?
    private var callbackFailure: Error?
    private(set) var handleCallbackCount = 0
    private(set) var resendVerificationCount = 0

    init(
        user: AuthenticatedUser? = nil,
        failure: Error? = nil,
        callbackFailure: Error? = nil
    ) {
        let pair = AsyncStream<AuthenticationEvent>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
        self.user = user
        self.failure = failure
        self.callbackFailure = callbackFailure
    }

    func restoredUser() throws -> AuthenticatedUser? {
        if let failure { throw failure }
        return user
    }

    func currentUser() throws -> AuthenticatedUser? {
        if let failure { throw failure }
        return user
    }

    nonisolated func authenticationEvents()
        -> AsyncStream<AuthenticationEvent> {
        stream
    }

    func signUp(_ request: SignUpRequest) throws -> AuthenticatedUser {
        if let failure { throw failure }
        let created = AuthenticatedUser(
            id: UUID(),
            email: EmailValidator.normalized(request.email),
            isEmailVerified: false,
            verificationEmailSentAt: .now
        )
        user = created
        return created
    }

    func signIn(email: String, password: String) throws
        -> AuthenticatedUser {
        if let failure { throw failure }
        let signedIn = user ?? AuthenticatedUser(
            id: UUID(),
            email: EmailValidator.normalized(email),
            isEmailVerified: true
        )
        user = signedIn
        continuation.yield(.signedIn(signedIn))
        return signedIn
    }

    func signOut() {
        user = nil
        continuation.yield(.signedOut)
    }

    func resendVerification(email: String) throws {
        if let failure { throw failure }
        resendVerificationCount += 1
    }

    func sendPasswordReset(email: String) throws {
        if let failure { throw failure }
    }

    func updatePassword(_ password: String) throws {
        if let failure { throw failure }
    }

    func handleCallback(_ url: URL) throws -> AuthCallbackResult {
        if let failure { throw failure }
        if let callbackFailure { throw callbackFailure }
        handleCallbackCount += 1
        guard AuthRedirectConfiguration.accepts(url) else {
            throw AuthenticationServiceError.invalidCallback
        }

        let kind = AuthRedirectConfiguration.callbackKind(from: url)
            ?? AuthCallbackIntentStore.current()
            ?? .emailVerification
        let callbackUser = AuthenticatedUser(
            id: user?.id ?? UUID(),
            email: user?.email ?? "john@example.com",
            isEmailVerified: true
        )
        user = callbackUser
        AuthCallbackIntentStore.clear()
        return AuthCallbackResult(kind: kind, user: callbackUser)
    }

    func emit(_ event: AuthenticationEvent) {
        continuation.yield(event)
    }
}

actor MockProfileRepository: ProfileRepository {
    private var storedProfile: UserProfile?
    private let failure: Error?

    init(profile: UserProfile? = nil, failure: Error? = nil) {
        storedProfile = profile
        self.failure = failure
    }

    func profile(userID: UUID) throws -> UserProfile? {
        if let failure { throw failure }
        return storedProfile
    }

    func update(
        userID: UUID,
        displayName: String,
        handle: String,
        avatarPath: String?,
        onboardingCompleted: Bool
    ) throws -> UserProfile {
        if let failure { throw failure }
        let now = Date()
        let profile = UserProfile(
            id: userID,
            displayName: displayName,
            handle: HandleValidator.normalized(handle),
            avatarPath: avatarPath,
            onboardingCompleted: onboardingCompleted,
            createdAt: storedProfile?.createdAt ?? now,
            updatedAt: now
        )
        storedProfile = profile
        return profile
    }
}

actor MockWorkspaceRepository: WorkspaceRepository {
    private var storedWorkspaces: [Workspace]
    private var storedInvitations: [WorkspaceInvitation]
    private var storedMembers: [UUID: [WorkspaceMember]]
    private let lookup: ProfileLookupResult?
    private let failure: Error?

    init(
        workspaces: [Workspace] = [],
        invitations: [WorkspaceInvitation] = [],
        members: [UUID: [WorkspaceMember]] = [:],
        lookup: ProfileLookupResult? = nil,
        failure: Error? = nil
    ) {
        storedWorkspaces = workspaces
        storedInvitations = invitations
        storedMembers = members
        self.lookup = lookup
        self.failure = failure
    }

    func workspaces() throws -> [Workspace] {
        if let failure { throw failure }
        return storedWorkspaces
    }

    func invitations() throws -> [WorkspaceInvitation] {
        if let failure { throw failure }
        return storedInvitations.filter { $0.status == .pending }
    }

    func createWorkspace(name: String) throws -> Workspace {
        if let failure { throw failure }
        let workspace = Workspace(
            id: UUID(),
            name: name,
            createdBy: nil,
            createdAt: .now,
            updatedAt: .now,
            currentUserRole: .owner
        )
        storedWorkspaces.append(workspace)
        return workspace
    }

    func members(workspaceID: UUID) throws -> [WorkspaceMember] {
        if let failure { throw failure }
        return storedMembers[workspaceID] ?? []
    }

    func pendingInvitations(workspaceID: UUID) throws
        -> [ManagedWorkspaceInvitation] {
        if let failure { throw failure }
        return storedInvitations
            .filter {
                $0.workspaceID == workspaceID && $0.status == .pending
            }
            .map {
                ManagedWorkspaceInvitation(
                    id: $0.id,
                    workspaceID: $0.workspaceID,
                    inviteeID: $0.inviteeID,
                    inviteeDisplayName: "Invited member",
                    inviteeHandle: nil,
                    createdAt: $0.createdAt
                )
            }
    }

    func findProfile(exactHandle: String) throws -> ProfileLookupResult? {
        if let failure { throw failure }
        guard lookup?.handle == HandleValidator.normalized(exactHandle)
        else {
            return nil
        }
        return lookup
    }

    func invite(workspaceID: UUID, userID: UUID) throws
        -> WorkspaceInvitation {
        if let failure { throw failure }
        let invitation = WorkspaceInvitation(
            id: UUID(),
            workspaceID: workspaceID,
            workspaceName: storedWorkspaces.first {
                $0.id == workspaceID
            }?.name ?? "Workspace",
            inviteeID: userID,
            invitedBy: UUID(),
            status: .pending,
            createdAt: .now,
            respondedAt: nil
        )
        storedInvitations.append(invitation)
        return invitation
    }

    func respond(invitationID: UUID, accept: Bool) throws {
        if let failure { throw failure }
        guard let index = storedInvitations.firstIndex(where: {
            $0.id == invitationID
        }) else {
            return
        }
        storedInvitations[index].status = accept ? .accepted : .declined
        storedInvitations[index].respondedAt = .now
    }

    func cancel(invitationID: UUID) throws {
        if let failure { throw failure }
        guard let index = storedInvitations.firstIndex(where: {
            $0.id == invitationID
        }) else {
            return
        }
        storedInvitations[index].status = .cancelled
        storedInvitations[index].respondedAt = .now
    }

    func setRole(
        workspaceID: UUID,
        userID: UUID,
        role: WorkspaceRole
    ) throws {
        if let failure { throw failure }
        guard let index = storedMembers[workspaceID]?.firstIndex(where: {
            $0.userID == userID
        }) else {
            return
        }
        storedMembers[workspaceID]?[index].role = role
    }

    func removeMember(workspaceID: UUID, userID: UUID) throws {
        if let failure { throw failure }
        storedMembers[workspaceID]?.removeAll { $0.userID == userID }
    }

    func rename(workspaceID: UUID, name: String) throws {
        if let failure { throw failure }
        guard let index = storedWorkspaces.firstIndex(where: {
            $0.id == workspaceID
        }) else {
            return
        }
        storedWorkspaces[index].name = name
        storedWorkspaces[index].updatedAt = .now
    }
}

actor MockMeetingCloudRepository: MeetingCloudRepository {
    private(set) var synchronizedMeetingIDs: [UUID] = []
    private(set) var deletedMeetingIDs: [UUID] = []
    private let failure: Error?

    init(failure: Error? = nil) {
        self.failure = failure
    }

    func synchronize(
        _ meeting: Meeting,
        workspaceID: UUID,
        organizerID: UUID,
        participantUserIDs: [UUID]
    ) throws {
        if let failure { throw failure }
        synchronizedMeetingIDs.append(meeting.id)
    }

    func delete(meetingID: UUID) throws {
        if let failure { throw failure }
        deletedMeetingIDs.append(meetingID)
    }
}

actor MockAvatarStorage: AvatarStorage {
    private let failure: Error?

    init(failure: Error? = nil) {
        self.failure = failure
    }

    func uploadJPEG(_ data: Data, userID: UUID) throws -> String {
        if let failure { throw failure }
        return "\(userID.uuidString.lowercased())/profile.jpg"
    }

    func removeAvatar(userID: UUID) throws {
        if let failure { throw failure }
    }

    func signedURL(path: String) throws -> URL {
        if let failure { throw failure }
        guard let url = URL(string: "https://example.test/\(path)") else {
            throw URLError(.badURL)
        }
        return url
    }
}

actor MockAccountDeletionService: AccountDeletionServicing {
    private(set) var deletionCount = 0
    private let failure: Error?

    init(failure: Error? = nil) {
        self.failure = failure
    }

    func deleteAccount(
        confirmingSoleMemberWorkspaceDeletion: Bool
    ) throws {
        if let failure { throw failure }
        deletionCount += 1
    }
}
