import SwiftUI

struct NewPasswordView: View {
    private enum Field {
        case password
        case confirmation
    }

    let session: AppSession

    @State private var model = AuthenticationViewModel()
    @State private var focusedField: Field? = .password
    @State private var showsValidation = false

    var body: some View {
        NavigationStack {
            AuthScaffold(
                title: "Choose a new password",
                subtitle: "Create a secure password for your Aligna account."
            ) {
                VStack(alignment: .leading, spacing: AlignaSpacing.medium) {
                    SecureAuthField(
                        label: "New Password",
                        placeholder: "Create a new password",
                        text: $model.newPassword,
                        textContentType: .newPassword,
                        returnKey: .next,
                        errorMessage: showsValidation
                            ? PasswordValidator.validationMessage(
                                for: model.newPassword
                            )
                            : nil,
                        isFocused: focusedField == .password,
                        onFocusChange: { isFocused in
                            updateFocus(.password, isFocused: isFocused)
                        },
                        onSubmit: {
                            focusedField = .confirmation
                        }
                    )

                    PasswordRequirementsView(password: model.newPassword)

                    SecureAuthField(
                        label: "Confirm Password",
                        placeholder: "Re-enter your new password",
                        text: $model.newPasswordConfirmation,
                        textContentType: .newPassword,
                        returnKey: .done,
                        errorMessage: showsValidation
                            ? confirmationError
                            : nil,
                        isFocused: focusedField == .confirmation,
                        onFocusChange: { isFocused in
                            updateFocus(
                                .confirmation,
                                isFocused: isFocused
                            )
                        },
                        onSubmit: updatePassword
                    )

                    if let error = session.operationError {
                        AuthErrorBanner(message: error)
                    }

                    PrimaryAuthButton(
                        title: session.isPerformingOperation
                            ? "Updating Password…"
                            : "Update Password",
                        isLoading: session.isPerformingOperation,
                        isEnabled: !session.isPerformingOperation,
                        action: updatePassword
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .interactiveDismissDisabled()
        }
        .tint(AlignaColors.accent)
        .onChange(of: model.newPassword) {
            session.clearOperationError()
        }
        .onChange(of: model.newPasswordConfirmation) {
            session.clearOperationError()
        }
    }

    private var confirmationError: String? {
        guard !model.newPasswordConfirmation.isEmpty else {
            return "Confirm your new password."
        }
        return model.newPassword == model.newPasswordConfirmation
            ? nil
            : "Passwords do not match."
    }

    private func updateFocus(_ field: Field, isFocused: Bool) {
        if isFocused {
            focusedField = field
        } else if focusedField == field {
            focusedField = nil
        }
    }

    private func updatePassword() {
        guard !session.isPerformingOperation else { return }
        showsValidation = true
        focusedField = nil

        guard model.passwordUpdateValidationMessage == nil else {
            AuthHaptics.error()
            focusedField = PasswordValidator.isValid(model.newPassword)
                ? .confirmation
                : .password
            return
        }

        Task {
            let succeeded = await session.updatePassword(
                model.newPassword
            )
            if succeeded {
                model.clearPasswordFields()
                AuthHaptics.success()
            } else {
                AuthHaptics.error()
            }
        }
    }
}

#Preview("New password") {
    NewPasswordView(
        session: AppSession(
            dependencies: .preview(
                user: PreviewCloudData.user,
                profile: nil,
                workspaces: []
            ),
            initialState: .signedOut
        )
    )
}
