import Foundation

nonisolated struct ProfileDTO: Codable, Sendable {
    let id: UUID
    let displayName: String
    let handle: String?
    let avatarPath: String?
    let onboardingCompleted: Bool
    let voiceEnrollmentStatus: VoiceEnrollmentStatus?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case handle
        case avatarPath = "avatar_path"
        case onboardingCompleted = "onboarding_completed"
        case voiceEnrollmentStatus = "voice_enrollment_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var domain: UserProfile {
        UserProfile(
            id: id,
            displayName: displayName,
            handle: handle,
            avatarPath: avatarPath,
            onboardingCompleted: onboardingCompleted,
            voiceEnrollmentStatus:
                voiceEnrollmentStatus ?? .notStarted,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

nonisolated struct ProfileUpdateDTO: Encodable, Sendable {
    let displayName: String
    let handle: String
    let avatarPath: String?
    let onboardingCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case handle
        case avatarPath = "avatar_path"
        case onboardingCompleted = "onboarding_completed"
    }
}

nonisolated struct ProfileSummaryDTO: Codable, Sendable {
    let displayName: String
    let handle: String?
    let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case handle
        case avatarPath = "avatar_path"
    }
}

nonisolated struct ProfileLookupDTO: Codable, Sendable {
    let id: UUID
    let handle: String
    let displayName: String
    let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case avatarPath = "avatar_path"
    }

    var domain: ProfileLookupResult {
        ProfileLookupResult(
            id: id,
            handle: handle,
            displayName: displayName,
            avatarPath: avatarPath
        )
    }
}

nonisolated struct WorkspaceDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let createdBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func domain(role: WorkspaceRole?) -> Workspace {
        Workspace(
            id: id,
            name: name,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt,
            currentUserRole: role
        )
    }
}

nonisolated struct WorkspaceMemberDTO: Codable, Sendable {
    let workspaceID: UUID
    let userID: UUID
    let role: WorkspaceRole
    let joinedAt: Date
    let profile: ProfileSummaryDTO

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case userID = "user_id"
        case role
        case joinedAt = "joined_at"
        case profile = "profiles"
    }

    var domain: WorkspaceMember {
        WorkspaceMember(
            workspaceID: workspaceID,
            userID: userID,
            role: role,
            joinedAt: joinedAt,
            displayName: profile.displayName,
            handle: profile.handle,
            avatarPath: profile.avatarPath
        )
    }
}

nonisolated struct WorkspaceRoleDTO: Codable, Sendable {
    let role: WorkspaceRole
}

nonisolated struct WorkspaceNameDTO: Codable, Sendable {
    let name: String
}

nonisolated struct WorkspaceInvitationDTO: Codable, Sendable {
    let id: UUID
    let workspaceID: UUID
    let inviteeID: UUID
    let invitedBy: UUID
    let status: WorkspaceInvitationStatus
    let createdAt: Date
    let respondedAt: Date?
    let workspace: WorkspaceNameDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case inviteeID = "invitee_id"
        case invitedBy = "invited_by"
        case status
        case createdAt = "created_at"
        case respondedAt = "responded_at"
        case workspace = "workspaces"
    }

    func domain(fallbackWorkspaceName: String = "Workspace")
        -> WorkspaceInvitation {
        WorkspaceInvitation(
            id: id,
            workspaceID: workspaceID,
            workspaceName: workspace?.name ?? fallbackWorkspaceName,
            inviteeID: inviteeID,
            invitedBy: invitedBy,
            status: status,
            createdAt: createdAt,
            respondedAt: respondedAt
        )
    }
}

nonisolated struct ManagedWorkspaceInvitationDTO: Codable, Sendable {
    let id: UUID
    let workspaceID: UUID
    let inviteeID: UUID
    let inviteeDisplayName: String
    let inviteeHandle: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case inviteeID = "invitee_id"
        case inviteeDisplayName = "invitee_display_name"
        case inviteeHandle = "invitee_handle"
        case createdAt = "created_at"
    }

    var domain: ManagedWorkspaceInvitation {
        ManagedWorkspaceInvitation(
            id: id,
            workspaceID: workspaceID,
            inviteeID: inviteeID,
            inviteeDisplayName: inviteeDisplayName,
            inviteeHandle: inviteeHandle,
            createdAt: createdAt
        )
    }
}

nonisolated struct CreateWorkspaceParameters: Encodable, Sendable {
    let name: String

    enum CodingKeys: String, CodingKey {
        case name = "p_name"
    }
}

nonisolated struct HandleLookupParameters: Encodable, Sendable {
    let handle: String

    enum CodingKeys: String, CodingKey {
        case handle = "p_handle"
    }
}

nonisolated struct WorkspaceIDParameters: Encodable, Sendable {
    let workspaceID: UUID

    enum CodingKeys: String, CodingKey {
        case workspaceID = "p_workspace_id"
    }
}

nonisolated struct InviteMemberParameters: Encodable, Sendable {
    let workspaceID: UUID
    let inviteeID: UUID

    enum CodingKeys: String, CodingKey {
        case workspaceID = "p_workspace_id"
        case inviteeID = "p_invitee_id"
    }
}

nonisolated struct RespondInvitationParameters: Encodable, Sendable {
    let invitationID: UUID
    let accept: Bool

    enum CodingKeys: String, CodingKey {
        case invitationID = "p_invitation_id"
        case accept = "p_accept"
    }
}

nonisolated struct InvitationIDParameters: Encodable, Sendable {
    let invitationID: UUID

    enum CodingKeys: String, CodingKey {
        case invitationID = "p_invitation_id"
    }
}

nonisolated struct SetWorkspaceRoleParameters: Encodable, Sendable {
    let workspaceID: UUID
    let userID: UUID
    let role: WorkspaceRole

    enum CodingKeys: String, CodingKey {
        case workspaceID = "p_workspace_id"
        case userID = "p_user_id"
        case role = "p_role"
    }
}

nonisolated struct RemoveWorkspaceMemberParameters: Encodable, Sendable {
    let workspaceID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case workspaceID = "p_workspace_id"
        case userID = "p_user_id"
    }
}

nonisolated struct WorkspaceRenameDTO: Encodable, Sendable {
    let name: String
}

nonisolated struct MeetingCloudDTO: Encodable, Sendable {
    let id: UUID
    let workspaceID: UUID
    let organizerID: UUID
    let title: String
    let scheduledAt: Date?
    let startedAt: Date?
    let endedAt: Date?
    let status: String
    let processingStatus: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case organizerID = "organizer_id"
        case title
        case scheduledAt = "scheduled_at"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case status
        case processingStatus = "processing_status"
    }
}

nonisolated struct MeetingParticipantCloudDTO: Encodable, Sendable {
    let meetingID: UUID
    let userID: UUID
    let role: String
    let responseStatus: String
    let invitedBy: UUID

    enum CodingKeys: String, CodingKey {
        case meetingID = "meeting_id"
        case userID = "user_id"
        case role
        case responseStatus = "response_status"
        case invitedBy = "invited_by"
    }
}

nonisolated struct MeetingDeletionCloudDTO: Decodable, Sendable {
    let audioChunks: [MeetingDeletionAudioChunkDTO]

    enum CodingKeys: String, CodingKey {
        case audioChunks = "audio_chunks"
    }
}

nonisolated struct MeetingDeletionAudioChunkDTO: Decodable, Sendable {
    let path: String
}
