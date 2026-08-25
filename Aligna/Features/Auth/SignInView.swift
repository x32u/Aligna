import SwiftUI

struct SignInView: View {
    private enum Field {
        case email
        case password
    }

    let session: AppSession
    @Bindable var model: AuthenticationViewModel
    var motionNamespace: Namespace.ID? = nil
    var onCreateAccount: () -> Void = {}
    var onForgotPassword: () -> Void = {}

    @State private var focusedField: Field?
    @State private var didAttemptSubmit = false

    var body: some View {
        AuthScaffold(
            title: "Welcome back",
            subtitle: "Your meetings, decisions, and next steps—all in one place.",
            motionNamespace: motionNamespace
        ) {
            VStack(spacing: AlignaSpacing.medium) {
                if let notice = session.authNotice {
                    AuthErrorBanner(
                        message: notice.message,
                        style: notice.style == .success
                            ? .success
                            : .information
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                AuthTextField(
                    label: "Email",
                    placeholder: "name@example.com",
                    text: $model.email,
                    systemImage: "envelope",
                    keyboardType: .emailAddress,
                    textContentType: .username,
                    capitalization: .never,
                    autocorrectionDisabled: true,
                    submitLabel: .next,
                    errorMessage: didAttemptSubmit
                        ? model.emailValidationMessage
                        : nil,
                    isFocused: focusedField == .email,
                    onFocusChange: { isFocused in
                        if isFocused {
                            focusedField = .email
                        } else if focusedField == .email {
                            focusedField = nil
                        }
                    },
                    onSubmit: {
                        focusedField = .password
                    }
                )

                SecureAuthField(
                    label: "Password",
                    placeholder: "Enter your password",
                    text: $model.password,
                    textContentType: .password,
                    returnKey: .go,
                    errorMessage: didAttemptSubmit
                        ? model.signInPasswordValidationMessage
                        : nil,
                    isFocused: focusedField == .password,
                    labelActionTitle: "Forgot password?",
                    onLabelAction: {
                        focusedField = nil
                        onForgotPassword()
                    },
                    onFocusChange: { isFocused in
                        if isFocused {
                            focusedField = .password
                        } else if focusedField == .password {
                            focusedField = nil
                        }
                    },
                    onSubmit: submit
                )

                if let error = session.operationError {
                    AuthErrorBanner(message: error)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                PrimaryAuthButton(
                    title: session.isPerformingOperation
                        ? "Signing In…"
                        : "Sign In",
                    isLoading: session.isPerformingOperation,
                    isEnabled: !session.isPerformingOperation,
                    action: submit
                )

                HStack(spacing: AlignaSpacing.extraSmall) {
                    Text("New to Aligna?")
                        .foregroundStyle(AlignaColors.secondaryLabel)
                    Button("Create account", action: onCreateAccount)
                    .fontWeight(.semibold)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AlignaSize.minimumTouchTarget)
                .accessibilityElement(children: .combine)
            }
            .animation(
                .easeInOut(duration: AlignaAnimation.quick),
                value: session.operationError
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            focusedField = model.email.isEmpty ? .email : .password
        }
        .onChange(of: model.email) {
            session.clearOperationError()
            session.clearAuthNotice()
        }
        .onChange(of: model.password) {
            session.clearOperationError()
        }
    }

    private func submit() {
        guard !session.isPerformingOperation else { return }
        didAttemptSubmit = true
        focusedField = nil

        guard model.signInIsValid else {
            AuthHaptics.error()
            focusedField = model.emailValidationMessage == nil
                ? .password
                : .email
            return
        }

        Task {
            let succeeded = await model.signIn(using: session)
            if succeeded {
                AuthHaptics.success()
            } else {
                AuthHaptics.error()
            }
        }
    }
}
