import Foundation
import Supabase

actor SupabaseWorkspaceRepository: WorkspaceRepository {
    private let client: SupabaseClient

    init(provider: SupabaseClientProvider) {
        client = provider.client
    }

    func workspaces() async throws -> [Workspace] {
        let session = try await client.auth.session
        let workspaceDTOs: [WorkspaceDTO] = try await client
            .from("workspaces")
            .select()
            .order("updated_at", ascending: false)
            .execute()
            .value

        var result: [Workspace] = []
        for workspace in workspaceDTOs {
            let roles: [WorkspaceRoleDTO] = try await client
                .from("workspace_members")
                .select("role")
                .eq("workspace_id", value: workspace.id)
                .eq("user_id", value: session.user.id)
                .limit(1)
                .execute()
                .value
            result.append(workspace.domain(role: roles.first?.role))
        }
        return result
    }

    func invitations() async throws -> [WorkspaceInvitation] {
        let session = try await client.auth.session
        let values: [WorkspaceInvitationDTO] = try await client
            .from("workspace_invitations")
            .select(
                "id,workspace_id,invitee_id,invited_by,status,created_at,responded_at,workspaces(name)"
            )
            .eq("invitee_id", value: session.user.id)
            .eq("status", value: WorkspaceInvitationStatus.pending.rawValue)
            .order("created_at", ascending: false)
            .execute()
            .value
        return values.map { $0.domain() }
    }

    func pendingInvitations(workspaceID: UUID) async throws
        -> [ManagedWorkspaceInvitation] {
        let values: [ManagedWorkspaceInvitationDTO] = try await client
            .rpc(
                "list_workspace_invitations",
                params: WorkspaceIDParameters(workspaceID: workspaceID)
            )
            .execute()
            .value
        return values.map(\.domain)
    }

    func createWorkspace(name: String) async throws -> Workspace {
        let id: UUID = try await client
            .rpc(
                "create_workspace",
                params: CreateWorkspaceParameters(name: name)
            )
            .execute()
            .value
        let dto: WorkspaceDTO = try await client
            .from("workspaces")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        return dto.domain(role: .owner)
    }

    func members(workspaceID: UUID) async throws -> [WorkspaceMember] {
        let values: [WorkspaceMemberDTO] = try await client
            .from("workspace_members")
            .select(
                "workspace_id,user_id,role,joined_at,profiles!workspace_members_user_id_fkey(display_name,handle,avatar_path)"
            )
            .eq("workspace_id", value: workspaceID)
            .order("joined_at", ascending: true)
            .execute()
            .value
        return values.map(\.domain)
    }

    func findProfile(exactHandle: String) async throws
        -> ProfileLookupResult? {
        let values: [ProfileLookupDTO] = try await client
            .rpc(
                "find_profile_by_handle",
                params: HandleLookupParameters(handle: exactHandle)
            )
            .execute()
            .value
        return values.first?.domain
    }

    func invite(workspaceID: UUID, userID: UUID) async throws
        -> WorkspaceInvitation {
        let value: WorkspaceInvitationDTO = try await client
            .rpc(
                "invite_workspace_member",
                params: InviteMemberParameters(
                    workspaceID: workspaceID,
                    inviteeID: userID
                )
            )
            .execute()
            .value
        return value.domain()
    }

    func respond(invitationID: UUID, accept: Bool) async throws {
        try await client.rpc(
            "respond_to_workspace_invitation",
            params: RespondInvitationParameters(
                invitationID: invitationID,
                accept: accept
            )
        )
        .execute()
    }

    func cancel(invitationID: UUID) async throws {
        try await client.rpc(
            "cancel_workspace_invitation",
            params: InvitationIDParameters(invitationID: invitationID)
        )
        .execute()
    }

    func setRole(
        workspaceID: UUID,
        userID: UUID,
        role: WorkspaceRole
    ) async throws {
        try await client.rpc(
            "set_workspace_member_role",
            params: SetWorkspaceRoleParameters(
                workspaceID: workspaceID,
                userID: userID,
                role: role
            )
        )
        .execute()
    }

    func removeMember(workspaceID: UUID, userID: UUID) async throws {
        try await client.rpc(
            "remove_workspace_member",
            params: RemoveWorkspaceMemberParameters(
                workspaceID: workspaceID,
                userID: userID
            )
        )
        .execute()
    }

    func rename(workspaceID: UUID, name: String) async throws {
        try await client
            .from("workspaces")
            .update(WorkspaceRenameDTO(name: name))
            .eq("id", value: workspaceID)
            .execute()
    }
}
