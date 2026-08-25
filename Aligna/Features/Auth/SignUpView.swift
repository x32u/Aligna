import SwiftUI

struct SignUpView: View {
    private enum Field {
        case fullName
        case username
        case email
        case password
        case passwordConfirmation
    }

    let session: AppSession
    @Bindable var model: AuthenticationViewModel
    var motionNamespace: Namespace.ID? = nil
    var onBackToSignIn: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: AuthenticationViewModel.RegistrationStep =
        .profile
    @State private var focusedField: Field?
    @State private var showsProfileValidation = false
    @State private var showsCredentialValidation = false

    var body: some View {
        AuthScaffold(
            title: "Create your Aligna account",
            subtitle: "Capture conversations and turn them into clear next steps.",
            motionNamespace: motionNamespace
        ) {
            VStack(spacing: AlignaSpacing.large) {
                AuthStepIndicator(
                    currentStep: step.number,
                    totalSteps: AuthenticationViewModel
                        .RegistrationStep.allCases.count
                )

                Group {
                    switch step {
                    case .profile:
                        profileStep
                            .transition(stepTransition)
                    case .credentials:
                        credentialsStep
                            .transition(stepTransition)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(step == .credentials)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if step == .credentials {
                    Button("Back", systemImage: "chevron.left") {
                        focusedField = nil
                        withAnimation(stepAnimation) {
                            step = .profile
                        }
                    }
                    .accessibilityHint(
                        "Returns to the profile step without clearing your password."
                    )
                } else {
                    Button("Sign In", action: onBackToSignIn)
                }
            }
        }
        .onAppear {
            focusedField = model.displayName.isEmpty
                ? .fullName
                : .username
        }
        .onChange(of: model.email) {
            session.clearOperationError()
        }
        .onChange(of: model.password) {
            session.clearOperationError()
        }
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: AlignaSpacing.medium) {
            Text("Your profile")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            AuthTextField(
                label: "Full name",
                placeholder: "John Christopher Cruz",
                text: $model.displayName,
                systemImage: "person",
                textContentType: .name,
                capitalization: .words,
                submitLabel: .next,
                errorMessage: showsProfileValidation
                    ? model.fullNameValidationMessage
                    : nil,
                isFocused: focusedField == .fullName,
                onFocusChange: { isFocused in
                    updateFocus(.fullName, isFocused: isFocused)
                },
                onSubmit: {
                    focusedField = .username
                }
            )

            AuthTextField(
                label: "Username",
                placeholder: "johncruz",
                text: $model.username,
                systemImage: "at",
                textContentType: .nickname,
                capitalization: .never,
                autocorrectionDisabled: true,
                submitLabel: .next,
                errorMessage: showsProfileValidation
                    ? model.usernameValidationMessage
                    : nil,
                isFocused: focusedField == .username,
                onFocusChange: { isFocused in
                    updateFocus(.username, isFocused: isFocused)
                },
                onSubmit: continueToCredentials
            )

            Text("Teammates can use this to find and invite you.")
                .font(.footnote)
                .foregroundStyle(AlignaColors.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryAuthButton(
                title: "Continue",
                isEnabled: !session.isPerformingOperation,
                action: continueToCredentials
            )
        }
    }

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: AlignaSpacing.medium) {
            Text("Secure your account")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

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
                errorMessage: showsCredentialValidation
                    ? model.emailValidationMessage
                    : nil,
                isFocused: focusedField == .email,
                onFocusChange: { isFocused in
                    updateFocus(.email, isFocused: isFocused)
                },
                onSubmit: {
                    focusedField = .password
                }
            )

            SecureAuthField(
                label: "Password",
                placeholder: "Create a password",
                text: $model.password,
                textContentType: .newPassword,
                returnKey: .next,
                errorMessage: showsCredentialValidation
                    ? model.passwordValidationMessage
                    : nil,
                isFocused: focusedField == .password,
                onFocusChange: { isFocused in
                    updateFocus(.password, isFocused: isFocused)
                },
                onSubmit: {
                    focusedField = .passwordConfirmation
                }
            )

            PasswordRequirementsView(password: model.password)

            SecureAuthField(
                label: "Confirm password",
                placeholder: "Re-enter your password",
                text: $model.passwordConfirmation,
                textContentType: .newPassword,
                returnKey: .done,
                errorMessage: showsCredentialValidation
                    ? model.passwordConfirmationValidationMessage
                    : nil,
                isFocused: focusedField == .passwordConfirmation,
                onFocusChange: { isFocused in
                    updateFocus(
                        .passwordConfirmation,
                        isFocused: isFocused
                    )
                },
                onSubmit: createAccount
            )

            if let error = session.operationError {
                AuthErrorBanner(message: error)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            PrimaryAuthButton(
                title: session.isPerformingOperation
                    ? "Creating Account…"
                    : "Create Account",
                isLoading: session.isPerformingOperation,
                isEnabled: !session.isPerformingOperation,
                action: createAccount
            )
        }
    }

    private func updateFocus(_ field: Field, isFocused: Bool) {
        if isFocused {
            focusedField = field
        } else if focusedField == field {
            focusedField = nil
        }
    }

    private func continueToCredentials() {
        showsProfileValidation = true
        guard model.profileStepIsValid else {
            AuthHaptics.error()
            focusedField = model.fullNameValidationMessage == nil
                ? .username
                : .fullName
            return
        }

        focusedField = nil
        withAnimation(stepAnimation) {
            step = .credentials
        }
        focusedField = model.email.isEmpty ? .email : .password
    }

    private func createAccount() {
        guard !session.isPerformingOperation else { return }
        showsCredentialValidation = true
        focusedField = nil

        guard model.credentialsStepIsValid else {
            AuthHaptics.error()
            if model.emailValidationMessage != nil {
                focusedField = .email
            } else if model.passwordValidationMessage != nil {
                focusedField = .password
            } else {
                focusedField = .passwordConfirmation
            }
            return
        }

        Task {
            let succeeded = await model.signUp(using: session)
            if succeeded {
                AuthHaptics.success()
            } else {
                AuthHaptics.error()
            }
        }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity
            .combined(with: .scale(scale: 0.99))
            .combined(with: .offset(y: 10))
    }

    private var stepAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: AlignaAnimation.standard)
            : .spring(
                duration: AlignaAnimation.deliberate,
                bounce: 0.1
            )
    }
}

#Preview("Create account - Profile") {
    NavigationStack {
        SignUpView(
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
