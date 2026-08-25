import SwiftUI

struct SettingsView: View {
    @AppStorage(AppAppearance.preferenceKey)
    private var storedAppearance = AppAppearance.system.rawValue
    @State private var meetingRemindersEnabled = true
    @State private var reviewRemindersEnabled = true
    @State private var isConfirmingAccountDeletion = false
    @State private var legacyMeetingCount = 0
    @State private var legacyImportMessage: String?
    @State private var isPresentingVoiceSetup = false
    @State private var isConfirmingVoiceDeletion = false

    let session: AppSession?
    let meetingLibrary: MeetingLibrary?

    init(
        session: AppSession? = nil,
        meetingLibrary: MeetingLibrary? = nil
    ) {
        self.session = session
        self.meetingLibrary = meetingLibrary
    }

    private var appearanceSelection: Binding<AppAppearance> {
        Binding(
            get: {
                selectedAppearance
            },
            set: { appearance in
                guard appearance != selectedAppearance else { return }
                withAnimation(
                    .easeInOut(duration: AlignaAnimation.appearance)
                ) {
                    storedAppearance = appearance.rawValue
                }
            }
        )
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance.resolve(storedAppearance)
    }

    var body: some View {
        Form {
            Section("Workspace") {
                if let session {
                    NavigationLink {
                        WorkspaceListView(session: session)
                    } label: {
                        Label(
                            session.currentWorkspace?.name
                                ?? "Choose workspace",
                            systemImage: "person.3"
                        )
                    }

                    NavigationLink {
                        ProfileEditorView(session: session)
                    } label: {
                        Label(
                            session.profile?.displayName ?? "Profile",
                            systemImage: "person.crop.circle"
                        )
                    }
                } else {
                    Label("Aligna Mobile Launch", systemImage: "folder")
                    Label("Maya Chen", systemImage: "person.crop.circle")
                }
            }

            Section {
                HStack(spacing: AlignaSpacing.small) {
                    Label("Appearance", systemImage: "paintpalette")
                        .foregroundStyle(AlignaColors.label)

                    Spacer(minLength: AlignaSpacing.small)

                    Menu {
                        Picker("Appearance", selection: appearanceSelection) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Label(
                                    appearance.title,
                                    systemImage: appearance.systemImage
                                )
                                .tag(appearance)
                            }
                        }
                    } label: {
                        HStack(spacing: AlignaSpacing.small) {
                            Text(selectedAppearance.title)
                                .foregroundStyle(AlignaColors.secondaryLabel)

                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                                .foregroundStyle(AlignaColors.tertiaryLabel)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "Appearance, \(selectedAppearance.title)"
                    )
                    .accessibilityHint(
                        "Opens a menu with System, Light, and Dark choices"
                    )
                }
            } footer: {
                Text("System follows your iPhone appearance.")
            }

            if let session {
                Section {
                    HStack {
                        Label(
                            "Recognize my voice",
                            systemImage: "waveform.and.person.filled"
                        )
                        Spacer()
                        Text(
                            session.profile?.voiceEnrollmentStatus
                                .customerTitle ?? "Not set up"
                        )
                        .foregroundStyle(AlignaColors.secondaryLabel)
                    }
                    .accessibilityElement(children: .combine)

                    Button {
                        isPresentingVoiceSetup = true
                    } label: {
                        Label(
                            session.profile?.voiceEnrollmentStatus == .enrolled
                                ? "Record my voice again"
                                : "Set up voice recognition",
                            systemImage: "mic"
                        )
                    }

                    if session.profile?.voiceEnrollmentStatus == .enrolled {
                        Button(
                            "Delete voice profile",
                            systemImage: "trash",
                            role: .destructive
                        ) {
                            isConfirmingVoiceDeletion = true
                        }
                    }
                } header: {
                    Text("Voice recognition")
                } footer: {
                    Text(
                        "Optional. Aligna compares speakers only with enrolled people who are eligible for that meeting. Setup recordings are deleted after your protected profile is created."
                    )
                }
            }

            Section {
                Toggle(isOn: $meetingRemindersEnabled) {
                    Label("Meeting reminders", systemImage: "calendar.badge.clock")
                }

                Toggle(isOn: $reviewRemindersEnabled) {
                    Label("Review reminders", systemImage: "checkmark.message")
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Notification delivery will be connected in a later milestone.")
            }

            Section("About") {
                HStack {
                    Text("Foundation")
                    Spacer()
                    Text("Step 1")
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://github.com/x32u/Aligna")!) {
                    Label("Source repository", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .accessibilityHint("Opens the Aligna source repository")
            }

            if legacyMeetingCount > 0 {
                Section {
                    Button {
                        Task {
                            guard let meetingLibrary else { return }
                            do {
                                let count = try await meetingLibrary
                                    .claimLegacyMeetings()
                                legacyMeetingCount = 0
                                legacyImportMessage =
                                    "\(count) legacy meeting\(count == 1 ? "" : "s") added to this account."
                            } catch {
                                legacyImportMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        Label(
                            "Claim \(legacyMeetingCount) legacy meeting\(legacyMeetingCount == 1 ? "" : "s")",
                            systemImage: "tray.and.arrow.down"
                        )
                    }
                } header: {
                    Text("Local Data")
                } footer: {
                    Text("Only claim recordings that belong to you. The legacy source is retained as a safe backup.")
                }
            }

            if let session {
                Section {
                    if let error = session.operationError {
                        Label(
                            error,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(AlignaColors.danger)
                    }

                    Button {
                        Task { await session.signOut() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(session.isPerformingOperation)

                    Button(
                        "Delete account",
                        systemImage: "trash",
                        role: .destructive
                    ) {
                        isConfirmingAccountDeletion = true
                    }
                    .disabled(session.isPerformingOperation)
                } header: {
                    Text("Account")
                } footer: {
                    Text("Account deletion keeps local recordings on this device. Transfer ownership of shared workspaces first.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AlignaColors.background)
        .navigationTitle("Settings")
        .task {
            if let meetingLibrary {
                legacyMeetingCount = await meetingLibrary
                    .legacyMeetingCount()
            }
        }
        .alert(
            "Delete your Aligna account?",
            isPresented: $isConfirmingAccountDeletion
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete account", role: .destructive) {
                Task { await session?.deleteAccount() }
            }
        } message: {
            Text("This permanently deletes your cloud profile and sole-member workspaces. Shared workspaces require ownership transfer. Local audio and transcripts stay on this device.")
        }
        .alert(
            "Delete your voice profile?",
            isPresented: $isConfirmingVoiceDeletion
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await session?.deleteVoiceProfile() }
            }
        } message: {
            Text(
                "Future meetings will no longer recognize your voice automatically. Existing speaker labels are not changed."
            )
        }
        .fullScreenCover(isPresented: $isPresentingVoiceSetup) {
            if let session {
                VoiceSetupView(
                    session: session,
                    onFinished: {
                        isPresentingVoiceSetup = false
                    }
                )
            }
        }
        .alert(
            "Local meetings",
            isPresented: Binding(
                get: { legacyImportMessage != nil },
                set: { if !$0 { legacyImportMessage = nil } }
            )
        ) {
            Button("OK") { legacyImportMessage = nil }
        } message: {
            Text(legacyImportMessage ?? "")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
