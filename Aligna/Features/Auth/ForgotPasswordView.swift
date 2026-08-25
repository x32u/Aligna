import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var sentEmail: String?
    @State private var cooldown = AuthResendCooldown()
    @State private var showsValidation = false
    @State private var isEmailFocused = false
    @State private var showsMailFallback = false

    let session: AppSession
    @Bindable var model: AuthenticationViewModel

    var body: some View {
        AuthScaffold(
            title: sentEmail == nil
                ? "Reset your password"
                : "Check your inbox",
            subtitle: sentEmail == nil
                ? "Enter the email you use for Aligna and we’ll send a secure recovery link."
                : "Use the newest recovery link to choose a new password."
        ) {
            if let sentEmail {
                confirmationContent(email: sentEmail)
            } else {
                requestContent
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert(
            "Open your mail app",
            isPresented: $showsMailFallback
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Apple Mail isn’t available. Open your preferred mail app and look for the newest message from Aligna."
            )
        }
        .onAppear {
            isEmailFocused = true
        }
        .onChange(of: model.email) {
            session.clearOperationError()
        }
    }

    private var requestContent: some View {
        VStack(spacing: AlignaSpacing.medium) {
            AuthTextField(
                label: "Email",
                placeholder: "name@example.com",
                text: $model.email,
                systemImage: "envelope",
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                capitalization: .never,
                autocorrectionDisabled: true,
                submitLabel: .go,
                errorMessage: showsValidation
                    ? model.emailValidationMessage
                    : nil,
                isFocused: isEmailFocused,
                onFocusChange: { isEmailFocused = $0 },
                onSubmit: sendRecoveryLink
            )

            if let error = session.operationError {
                AuthErrorBanner(message: error)
            }

            PrimaryAuthButton(
                title: session.isPerformingOperation
                    ? "Sending Link…"
                    : "Send recovery link",
                isLoading: session.isPerformingOperation,
                isEnabled: !session.isPerformingOperation,
                action: sendRecoveryLink
            )
        }
    }

    private func confirmationContent(email: String) -> some View {
        VStack(spacing: AlignaSpacing.medium) {
            Label(
                EmailMasker.masked(email),
                systemImage: "envelope.badge"
            )
            .font(.headline)
            .foregroundStyle(AlignaColors.label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AlignaSpacing.medium)
            .background(AlignaColors.elevatedSurface)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: AlignaRadius.medium,
                    style: .continuous
                )
            )
            .accessibilityLabel(
                "Recovery email sent to \(EmailMasker.masked(email))"
            )

            if let error = session.operationError {
                AuthErrorBanner(message: error)
            }

            PrimaryAuthButton(
                title: "Open Mail",
                systemImage: "envelope.open",
                action: openMail
            )

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = cooldown.remainingSeconds(at: context.date)
                Button {
                    resendRecoveryLink(email: email)
                } label: {
                    Text(
                        remaining == 0
                            ? "Resend recovery email"
                            : "Resend in \(remaining)s"
                    )
                    .frame(minHeight: AlignaSize.minimumTouchTarget)
                }
                .disabled(
                    remaining > 0 || session.isPerformingOperation
                )
                .accessibilityHint(
                    remaining == 0
                        ? "Sends a new recovery link"
                        : "Available in \(remaining) seconds"
                )
            }

            Button("Back to Sign In") {
                dismiss()
            }
            .fontWeight(.semibold)
            .frame(minHeight: AlignaSize.minimumTouchTarget)
        }
    }

    private func sendRecoveryLink() {
        guard !session.isPerformingOperation else { return }
        showsValidation = true
        isEmailFocused = false

        guard model.emailValidationMessage == nil else {
            AuthHaptics.error()
            isEmailFocused = true
            return
        }

        Task {
            let succeeded = await session.sendPasswordReset(
                email: model.normalizedEmail
            )
            if succeeded {
                cooldown.start()
                sentEmail = model.normalizedEmail
                AuthHaptics.success()
            } else {
                AuthHaptics.error()
            }
        }
    }

    private func resendRecoveryLink(email: String) {
        guard cooldown.canResend(), !session.isPerformingOperation else {
            return
        }
        Task {
            let succeeded = await session.sendPasswordReset(email: email)
            if succeeded {
                cooldown.start()
                AuthHaptics.success()
            } else {
                AuthHaptics.error()
            }
        }
    }

    private func openMail() {
        guard let mailURL = URL(string: "message://") else {
            showsMailFallback = true
            return
        }
        openURL(mailURL) { accepted in
            if !accepted {
                showsMailFallback = true
            }
        }
    }
}

#Preview("Password recovery") {
    NavigationStack {
        ForgotPasswordView(
            session: AppSession(
                dependencies: .preview(
                    user: nil,
                    profile: nil,
                    workspaces: []
                ),
                initialState: .signedOut
            ),
            model: AuthenticationViewModel()
        )
    }
}
