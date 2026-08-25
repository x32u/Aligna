import SwiftUI

struct InvitationsView: View {
    let session: AppSession

    var body: some View {
        Group {
            if session.invitations.isEmpty {
                EmptyStateView(
                    symbol: "envelope.open",
                    title: "No pending invitations",
                    message: "Workspace invitations sent to your exact handle will appear here."
                )
                .padding(AlignaSpacing.large)
            } else {
                List(session.invitations) { invitation in
                    VStack(alignment: .leading, spacing: AlignaSpacing.small) {
                        Text(invitation.workspaceName)
                            .font(.headline)
                        Text(
                            "Invited \(invitation.createdAt.formatted(.relative(presentation: .named)))"
                        )
                        .font(.caption)
                        .foregroundStyle(AlignaColors.secondaryLabel)

                        HStack {
                            Button("Decline", role: .destructive) {
                                Task {
                                    await session.respond(
                                        to: invitation,
                                        accept: false
                                    )
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("Accept") {
                                Task {
                                    await session.respond(
                                        to: invitation,
                                        accept: true
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(minHeight: AlignaSize.minimumTouchTarget)
                    }
                    .padding(.vertical, AlignaSpacing.extraSmall)
                }
            }
        }
        .navigationTitle("Invitations")
        .refreshable {
            await session.refreshCollaboration()
        }
    }
}
