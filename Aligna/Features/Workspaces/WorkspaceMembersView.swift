import SwiftUI

struct WorkspaceMembersView: View {
    let model: WorkspaceDetailViewModel

    var body: some View {
        List {
            if let error = model.errorMessage {
                Section {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(AlignaColors.danger)
                }
            }

            Section("Members") {
                ForEach(model.members) { member in
                    HStack(spacing: AlignaSpacing.compact) {
                        AvatarView(
                            name: member.displayName,
                            initials: member.initials,
                            size: AlignaSize.avatarMedium
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName)
                                .font(.headline)
                            Text(
                                member.handle.map { "@\($0)" }
                                    ?? "No handle"
                            )
                            .font(.caption)
                            .foregroundStyle(AlignaColors.secondaryLabel)
                        }
                        Spacer()
                        StatusBadge(
                            title: member.role.title,
                            tone: member.role == .owner ? .accent : .neutral
                        )
                    }
                    .frame(minHeight: AlignaSize.minimumTouchTarget)
                    .contextMenu {
                        if canManage(member) {
                            ForEach(WorkspaceRole.allCases, id: \.self) {
                                role in
                                if role != member.role {
                                    Button("Make \(role.title)") {
                                        Task {
                                            await model.setRole(
                                                role,
                                                for: member
                                            )
                                        }
                                    }
                                }
                            }
                            Button("Remove member", role: .destructive) {
                                Task { await model.remove(member) }
                            }
                        }
                    }
                }
            }

            if model.currentRole.canManageMembers,
               !model.pendingInvitations.isEmpty {
                Section("Pending Invitations") {
                    ForEach(model.pendingInvitations) { invitation in
                        HStack(spacing: AlignaSpacing.compact) {
                            AvatarView(
                                name: invitation.inviteeDisplayName,
                                size: AlignaSize.avatarMedium
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invitation.inviteeDisplayName)
                                    .font(.headline)
                                Text(
                                    invitation.inviteeHandle.map {
                                        "@\($0)"
                                    } ?? "Invitation pending"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    AlignaColors.secondaryLabel
                                )
                            }
                            Spacer()
                            Button("Cancel", role: .destructive) {
                                Task { await model.cancel(invitation) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(minHeight: AlignaSize.minimumTouchTarget)
                    }
                }
            }
        }
    }

    private func canManage(_ member: WorkspaceMember) -> Bool {
        guard member.userID != model.currentUserID else { return false }
        return model.currentRole.canManage(member.role)
    }
}
