import SwiftUI

struct WorkspaceListView: View {
    @State private var isCreatingWorkspace = false

    let session: AppSession
    var isOnboarding = false

    var body: some View {
        List {
            if !session.invitations.isEmpty {
                Section {
                    NavigationLink {
                        InvitationsView(session: session)
                    } label: {
                        Label(
                            "\(session.invitations.count) pending",
                            systemImage: "envelope.badge"
                        )
                    }
                } header: {
                    Text("Invitations")
                }
            }

            Section("Workspaces") {
                ForEach(session.workspaces) { workspace in
                    NavigationLink {
                        WorkspaceDetailView(
                            workspace: workspace,
                            currentUserID: session.user?.id,
                            repository: session.dependencies.workspaces
                        )
                    } label: {
                        HStack(spacing: AlignaSpacing.compact) {
                            Image(systemName: "person.3.fill")
                                .foregroundStyle(AlignaColors.accent)
                                .frame(
                                    width: AlignaSize.minimumTouchTarget,
                                    height: AlignaSize.minimumTouchTarget
                                )
                            VStack(alignment: .leading) {
                                Text(workspace.name)
                                    .font(.headline)
                                Text(workspace.currentUserRole?.title ?? "Member")
                                    .font(.caption)
                                    .foregroundStyle(
                                        AlignaColors.secondaryLabel
                                    )
                            }
                            Spacer()
                            if session.currentWorkspace?.id == workspace.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AlignaColors.accent)
                                    .accessibilityLabel("Current workspace")
                            }
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded {
                            session.switchWorkspace(to: workspace)
                        })
                    }
                }

                Button {
                    isCreatingWorkspace = true
                } label: {
                    Label("Create workspace", systemImage: "plus.circle")
                        .frame(minHeight: AlignaSize.minimumTouchTarget)
                }
            }
        }
        .navigationTitle(
            isOnboarding ? "Choose a Workspace" : "Workspaces"
        )
        .refreshable {
            await session.refreshCollaboration()
        }
        .sheet(isPresented: $isCreatingWorkspace) {
            CreateWorkspaceView(session: session)
        }
    }
}
