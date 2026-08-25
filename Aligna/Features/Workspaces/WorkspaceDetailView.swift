import Observation
import SwiftUI

@MainActor
@Observable
final class WorkspaceDetailViewModel {
    private(set) var members: [WorkspaceMember] = []
    private(set) var pendingInvitations: [ManagedWorkspaceInvitation] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    let workspace: Workspace
    let currentUserID: UUID?
    let repository: any WorkspaceRepository

    init(
        workspace: Workspace,
        currentUserID: UUID?,
        repository: any WorkspaceRepository
    ) {
        self.workspace = workspace
        self.currentUserID = currentUserID
        self.repository = repository
    }

    var currentRole: WorkspaceRole {
        members.first { $0.userID == currentUserID }?.role
            ?? workspace.currentUserRole
            ?? .member
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let fetchedMembers = repository.members(
                workspaceID: workspace.id
            )
            members = try await fetchedMembers
            if currentRole.canManageMembers {
                pendingInvitations = try await repository.pendingInvitations(
                    workspaceID: workspace.id
                )
            } else {
                pendingInvitations = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setRole(_ role: WorkspaceRole, for member: WorkspaceMember) async {
        do {
            try await repository.setRole(
                workspaceID: workspace.id,
                userID: member.userID,
                role: role
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ member: WorkspaceMember) async {
        do {
            try await repository.removeMember(
                workspaceID: workspace.id,
                userID: member.userID
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel(_ invitation: ManagedWorkspaceInvitation) async {
        do {
            try await repository.cancel(invitationID: invitation.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct WorkspaceDetailView: View {
    @State private var model: WorkspaceDetailViewModel
    @State private var isInviting = false

    init(
        workspace: Workspace,
        currentUserID: UUID?,
        repository: any WorkspaceRepository
    ) {
        _model = State(
            initialValue: WorkspaceDetailViewModel(
                workspace: workspace,
                currentUserID: currentUserID,
                repository: repository
            )
        )
    }

    var body: some View {
        Group {
            if model.isLoading && model.members.isEmpty {
                ProgressView("Loading members…")
            } else if let error = model.errorMessage,
                      model.members.isEmpty {
                EmptyStateView(
                    symbol: "exclamationmark.triangle",
                    title: "Couldn’t load workspace",
                    message: error,
                    actionTitle: "Retry",
                    action: { Task { await model.load() } }
                )
                .padding()
            } else {
                WorkspaceMembersView(model: model)
            }
        }
        .navigationTitle(model.workspace.name)
        .toolbar {
            if model.currentRole.canManageMembers {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isInviting = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Invite a member")
                }
            }
        }
        .sheet(isPresented: $isInviting) {
            InviteMemberView(
                workspace: model.workspace,
                repository: model.repository
            ) {
                Task { await model.load() }
            }
        }
        .task {
            await model.load()
        }
        .refreshable {
            await model.load()
        }
    }
}
