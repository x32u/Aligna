import SwiftUI

struct CreateWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    let session: AppSession

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Workspace name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                } footer: {
                    Text("Use a team, company, or project name.")
                }

                if let error = session.operationError {
                    Section {
                        Label(
                            error,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(AlignaColors.danger)
                    }
                }
            }
            .navigationTitle("New Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await session.createWorkspace(
                                name: name.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            )
                            if session.operationError == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        !(2 ... 80).contains(
                            name.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).count
                        ) || session.isPerformingOperation
                    )
                }
            }
        }
    }
}
