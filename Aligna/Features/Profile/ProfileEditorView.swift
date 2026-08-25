import PhotosUI
import SwiftUI

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var handle: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarJPEG: Data?
    @State private var existingAvatarURL: URL?
    @State private var removeAvatar = false
    @State private var localError: String?

    let session: AppSession
    let isOnboarding: Bool

    init(session: AppSession, isOnboarding: Bool = false) {
        self.session = session
        self.isOnboarding = isOnboarding
        _displayName = State(initialValue: session.profile?.displayName ?? "")
        _handle = State(initialValue: session.profile?.handle ?? "")
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: AlignaSpacing.medium) {
                    avatar

                    VStack(alignment: .leading, spacing: AlignaSpacing.small) {
                        PhotosPicker(
                            selection: $selectedPhoto,
                            matching: .images
                        ) {
                            Label(
                                avatarJPEG == nil
                                    ? "Choose photo"
                                    : "Replace photo",
                                systemImage: "photo"
                            )
                            .frame(minHeight: AlignaSize.minimumTouchTarget)
                        }

                        if session.profile?.avatarPath != nil
                            || avatarJPEG != nil {
                            Button(
                                "Remove photo",
                                role: .destructive
                            ) {
                                avatarJPEG = nil
                                selectedPhoto = nil
                                existingAvatarURL = nil
                                removeAvatar = true
                            }
                            .frame(minHeight: AlignaSize.minimumTouchTarget)
                        }
                    }
                }
            } footer: {
                Text("JPEG only. Aligna resizes avatars to 512 px and limits uploads to 2 MB.")
            }

            Section("Profile") {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)

                TextField("@handle", text: $handle)
                    .textContentType(.nickname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if let validationMessage {
                Section {
                    Label(
                        validationMessage,
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(AlignaColors.secondaryLabel)
                }
            }

            if let error = localError ?? session.operationError {
                Section {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(AlignaColors.danger)
                }
            }

            Section {
                Button {
                    Task {
                        await session.saveProfile(
                            displayName: displayName,
                            handle: handle,
                            avatarJPEG: avatarJPEG,
                            removeAvatar: removeAvatar,
                            completeOnboarding: !isOnboarding
                        )
                        if !isOnboarding, session.operationError == nil {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if session.isPerformingOperation {
                            ProgressView()
                        }
                        Text(isOnboarding ? "Continue" : "Save changes")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .frame(minHeight: AlignaSize.minimumTouchTarget)
                }
                .disabled(
                    validationMessage != nil
                        || session.isPerformingOperation
                )
            }
        }
        .navigationTitle(isOnboarding ? "Your Profile" : "Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isOnboarding)
        .task {
            guard let path = session.profile?.avatarPath,
                  existingAvatarURL == nil
            else {
                return
            }
            existingAvatarURL = try? await session.dependencies.avatars
                .signedURL(path: path)
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            do {
                guard let data = try await selectedPhoto.loadTransferable(
                    type: Data.self
                ) else {
                    throw AvatarImageError.invalidImage
                }
                avatarJPEG = try AvatarImageProcessor.jpegData(from: data)
                removeAvatar = false
                localError = nil
            } catch {
                localError = error.localizedDescription
                avatarJPEG = nil
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarJPEG, let image = UIImage(data: avatarJPEG) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .accessibilityLabel("Selected profile photo")
        } else if let existingAvatarURL, !removeAvatar {
            AsyncImage(url: existingAvatarURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    avatarFallback
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .accessibilityLabel("Current profile photo")
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        AvatarView(
            name: displayName.isEmpty ? "Profile" : displayName,
            initials: initials,
            size: 72
        )
    }

    private var initials: String {
        let value = displayName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
            .joined()
        return value.isEmpty ? "A" : value
    }

    private var validationMessage: String? {
        guard !displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return "Enter your display name."
        }
        return HandleValidator.validationMessage(for: handle)
    }
}

#Preview {
    NavigationStack {
        ProfileEditorView(
            session: AppSession(
                dependencies: .preview(),
                initialState: .authenticated
            )
        )
    }
}
