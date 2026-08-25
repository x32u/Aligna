import Foundation

nonisolated struct AuthenticatedUser: Equatable, Sendable {
    let id: UUID
    let email: String
    let isEmailVerified: Bool
    let verificationEmailSentAt: Date?

    init(
        id: UUID,
        email: String,
        isEmailVerified: Bool,
        verificationEmailSentAt: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.isEmailVerified = isEmailVerified
        self.verificationEmailSentAt = verificationEmailSentAt
    }
}

nonisolated struct UserProfile: Identifiable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var handle: String?
    var avatarPath: String?
    var onboardingCompleted: Bool
    var voiceEnrollmentStatus: VoiceEnrollmentStatus
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        displayName: String,
        handle: String?,
        avatarPath: String? = nil,
        onboardingCompleted: Bool,
        voiceEnrollmentStatus: VoiceEnrollmentStatus = .notStarted,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.avatarPath = avatarPath
        self.onboardingCompleted = onboardingCompleted
        self.voiceEnrollmentStatus = voiceEnrollmentStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var initials: String {
        displayName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
            .joined()
    }

    var isComplete: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && handle != nil
    }
}

nonisolated enum WorkspaceRole: String, Codable, CaseIterable, Sendable {
    case owner
    case admin
    case member

    var title: String {
        rawValue.capitalized
    }

    var canManageMembers: Bool {
        self == .owner || self == .admin
    }

    func canManage(_ other: WorkspaceRole) -> Bool {
        switch self {
        case .owner:
            true
        case .admin:
            other != .owner
        case .member:
            false
        }
    }
}

nonisolated struct Workspace: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    let createdBy: UUID?
    let createdAt: Date
    var updatedAt: Date
    var currentUserRole: WorkspaceRole?
}

nonisolated struct WorkspaceMember: Identifiable, Hashable, Sendable {
    var id: UUID { userID }

    let workspaceID: UUID
    let userID: UUID
    var role: WorkspaceRole
    let joinedAt: Date
    let displayName: String
    let handle: String?
    let avatarPath: String?

    var initials: String {
        displayName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
            .joined()
    }
}

nonisolated enum WorkspaceInvitationStatus: String, Codable, Sendable {
    case pending
    case accepted
    case declined
    case cancelled
}

nonisolated struct WorkspaceInvitation: Identifiable, Hashable, Sendable {
    let id: UUID
    let workspaceID: UUID
    let workspaceName: String
    let inviteeID: UUID
    let invitedBy: UUID
    var status: WorkspaceInvitationStatus
    let createdAt: Date
    var respondedAt: Date?
}

nonisolated struct ManagedWorkspaceInvitation:
    Identifiable,
    Hashable,
    Sendable {
    let id: UUID
    let workspaceID: UUID
    let inviteeID: UUID
    let inviteeDisplayName: String
    let inviteeHandle: String?
    let createdAt: Date
}

nonisolated struct ProfileLookupResult: Identifiable, Hashable, Sendable {
    let id: UUID
    let handle: String
    let displayName: String
    let avatarPath: String?
}

nonisolated enum ParticipantResponseStatus: String, Codable, Sendable {
    case invited
    case accepted
    case declined
}

nonisolated enum MeetingSyncState: String, Codable, CaseIterable, Sendable {
    case local
    case syncing
    case synced
    case failed

    var title: String {
        switch self {
        case .local: "On device"
        case .syncing: "Syncing"
        case .synced: "Synced"
        case .failed: "Sync failed"
        }
    }
}
