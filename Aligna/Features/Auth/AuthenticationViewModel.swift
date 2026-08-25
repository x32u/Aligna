import Foundation
import Observation

@MainActor
@Observable
final class AuthenticationViewModel {
    enum RegistrationStep: Int, CaseIterable {
        case profile
        case credentials

        var number: Int {
            rawValue + 1
        }
    }

    var email = ""
    var password = ""
    var passwordConfirmation = ""
    var displayName = ""
    var username = ""
    var newPassword = ""
    var newPasswordConfirmation = ""

    var normalizedEmail: String {
        EmailValidator.normalized(email)
    }

    var normalizedUsername: String {
        HandleValidator.normalized(username)
    }

    var normalizedDisplayName: String {
        DisplayNameValidator.normalized(displayName)
    }

    var emailValidationMessage: String? {
        EmailValidator.isValid(email)
            ? nil
            : "Enter a valid email address."
    }

    var signInPasswordValidationMessage: String? {
        password.isEmpty ? "Enter your password." : nil
    }

    var fullNameValidationMessage: String? {
        DisplayNameValidator.validationMessage(for: displayName)
    }

    var usernameValidationMessage: String? {
        guard let message = HandleValidator.validationMessage(
            for: username
        ) else {
            return nil
        }

        if message == "Use 3–30 characters." {
            return "Username must be 3–30 characters."
        }
        return "Use lowercase letters, numbers, and underscores only."
    }

    var passwordValidationMessage: String? {
        PasswordValidator.validationMessage(for: password)
    }

    var passwordConfirmationValidationMessage: String? {
        guard !passwordConfirmation.isEmpty else {
            return "Confirm your password."
        }
        return password == passwordConfirmation
            ? nil
            : "Passwords do not match."
    }

    var signInIsValid: Bool {
        emailValidationMessage == nil
            && signInPasswordValidationMessage == nil
    }

    var profileStepIsValid: Bool {
        fullNameValidationMessage == nil
            && usernameValidationMessage == nil
    }

    var credentialsStepIsValid: Bool {
        emailValidationMessage == nil
            && passwordValidationMessage == nil
            && passwordConfirmationValidationMessage == nil
    }

    var passwordUpdateValidationMessage: String? {
        if let message = PasswordValidator.validationMessage(
            for: newPassword
        ) {
            return message
        }
        guard !newPasswordConfirmation.isEmpty else {
            return "Confirm your new password."
        }
        return newPassword == newPasswordConfirmation
            ? nil
            : "Passwords do not match."
    }

    @discardableResult
    func signIn(using session: AppSession) async -> Bool {
        guard signInIsValid else { return false }
        let succeeded = await session.signIn(
            email: normalizedEmail,
            password: password
        )
        if succeeded {
            password = ""
        }
        return succeeded
    }

    @discardableResult
    func signUp(using session: AppSession) async -> Bool {
        guard profileStepIsValid, credentialsStepIsValid else {
            return false
        }
        let succeeded = await session.signUp(
            SignUpRequest(
                email: normalizedEmail,
                password: password,
                displayName: normalizedDisplayName,
                handle: normalizedUsername
            )
        )
        if succeeded {
            clearPasswordFields()
        }
        return succeeded
    }

    func clearPasswordFields() {
        password = ""
        passwordConfirmation = ""
        newPassword = ""
        newPasswordConfirmation = ""
    }
}
