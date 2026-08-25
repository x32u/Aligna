import SwiftUI

struct CheckEmailView: View {
    @Environment(\.openURL) private var openURL

    @State private var showsMailFallback = false

    let session: AppSession

    var body: some View {
        NavigationStack {
            AuthScaffold(
                title: "Check your inbox",
                subtitle: "We sent a verification link to \(EmailMasker.masked(session.pendingVerificationEmail)). The link will reopen Aligna."
            ) {
                VStack(spacing: AlignaSpacing.medium) {
                    statusBanner

                    PrimaryAuthButton(
                        title: "Open Mail",
                        systemImage: "envelope.open",
                        action: openMail
                    )

                    Button {
                        checkVerification()
                    } label: {
                        HStack(spacing: AlignaSpacing.small) {
                            if session.emailVerificationStatus == .checking {
                                ProgressView()
                                    .accessibilityHidden(true)
                            }
                            Text("I’ve verified my email")
                                .fontWeight(.semibold)
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: AlignaSize.minimumTouchTarget
                        )
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(
                        .roundedRectangle(radius: AlignaRadius.medium)
                    )
                    .disabled(session.isPerformingOperation)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining =
                            session.verificationResendRemainingSeconds(
                                at: context.date
                            )
                        Button {
                            resendVerification()
                        } label: {
                            Text(
                                remaining == 0
                                    ? "Resend email"
                                    : "Resend in \(remaining)s"
                            )
                            .frame(minHeight: AlignaSize.minimumTouchTarget)
                        }
                        .disabled(
                            remaining > 0 || session.isPerformingOperation
                        )
                        .accessibilityHint(
                            remaining == 0
                                ? "Sends a new verification email"
                                : "Available in \(remaining) seconds"
                        )
                    }

                    Button("Use a different email") {
                        Task {
                            await session.useDifferentEmail()
                        }
                    }
                    .foregroundStyle(AlignaColors.secondaryLabel)
                    .frame(minHeight: AlignaSize.minimumTouchTarget)
                    .disabled(session.isPerformingOperation)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(AlignaColors.accent)
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
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch session.emailVerificationStatus {
        case .waiting:
            EmptyView()
        case .checking:
            AuthErrorBanner(
                message: "Checking your verification status…",
                style: .information
            )
        case .resent:
            AuthErrorBanner(
                message: "A new verification email is on its way.",
                style: .success
            )
        case .expired:
            AuthErrorBanner(
                message: AuthenticationServiceError
                    .expiredVerificationLink.localizedDescription
            )
        case let .failed(message):
            AuthErrorBanner(message: message)
        }
    }

    private func resendVerification() {
        guard
            session.verificationResendRemainingSeconds() == 0,
            !session.isPerformingOperation
        else {
            return
        }
        Task {
            let succeeded = await session.resendVerification()
            if succeeded {
                AuthHaptics.success()
            } else {
                AuthHaptics.error()
            }
        }
    }

    private func checkVerification() {
        guard !session.isPerformingOperation else { return }
        Task {
            let succeeded = await session.checkEmailVerification()
            if succeeded {
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

#Preview("Check email - Dark") {
    CheckEmailView(
        session: AppSession(
            dependencies: .preview(
                user: AuthenticatedUser(
                    id: UUID(),
                    email: "john.christopher@example.com",
                    isEmailVerified: false
                ),
                profile: nil,
                workspaces: []
            ),
            initialState: .awaitingEmailVerification
        )
    )
    .preferredColorScheme(.dark)
}
