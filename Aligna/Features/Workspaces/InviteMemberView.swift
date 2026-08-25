import SwiftUI

struct InviteMemberView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var handle = ""
    @State private var result: ProfileLookupResult?
    @State private var isLoading = false
    @State private var errorMessage: String?

    let workspace: Workspace
    let repository: any WorkspaceRepository
    let onInvited: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("@exact_handle", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }

                    Button {
                        Task { await search() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Label("Find account", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(
                        HandleValidator.validationMessage(for: handle) != nil
                            || isLoading
                    )
                } footer: {
                    Text("Aligna searches only an exact public handle. Email addresses are never exposed.")
                }

                if let result {
                    Section("Account") {
                        HStack(spacing: AlignaSpacing.compact) {
                            AvatarView(
                                name: result.displayName,
                                initials: initials(for: result.displayName),
                                size: AlignaSize.avatarMedium
                            )
                            VStack(alignment: .leading) {
                                Text(result.displayName)
                                    .font(.headline)
                                Text("@\(result.handle)")
                                    .foregroundStyle(
                                        AlignaColors.secondaryLabel
                                    )
                            }
                            Spacer()
                            Button("Invite") {
                                Task { await invite(result) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(
                            errorMessage,
                            systemImage: "exclamationmark.circle"
                        )
                        .foregroundStyle(AlignaColors.danger)
                    }
                }
            }
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        isLoading = true
        result = nil
        errorMessage = nil
        defer { isLoading = false }
        do {
            result = try await repository.findProfile(
                exactHandle: HandleValidator.normalized(handle)
            )
            if result == nil {
                errorMessage = "No account matches that exact handle."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func invite(_ profile: ProfileLookupResult) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await repository.invite(
                workspaceID: workspace.id,
                userID: profile.id
            )
            onInvited()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func initials(for name: String) -> String {
        name.split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
            .joined()
    }
}
