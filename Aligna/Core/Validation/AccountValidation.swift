import Foundation

nonisolated enum EmailValidator {
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValid(_ value: String) -> Bool {
        let email = normalized(value)
        guard email.count <= 254,
              let at = email.firstIndex(of: "@"),
              at != email.startIndex
        else {
            return false
        }

        let domainStart = email.index(after: at)
        guard domainStart < email.endIndex else { return false }
        let domain = email[domainStart...]
        return domain.contains(".")
            && !email.contains(" ")
            && !domain.hasPrefix(".")
            && !domain.hasSuffix(".")
    }
}

nonisolated enum PasswordValidator {
    static func validationMessage(for value: String) -> String? {
        guard value.count >= 8 else {
            return "Use at least 8 characters."
        }
        guard value.rangeOfCharacter(from: .lowercaseLetters) != nil,
              value.rangeOfCharacter(from: .uppercaseLetters) != nil,
              value.rangeOfCharacter(from: .decimalDigits) != nil
        else {
            return "Include an uppercase letter, lowercase letter, and number."
        }
        return nil
    }

    static func isValid(_ value: String) -> Bool {
        validationMessage(for: value) == nil
    }
}

nonisolated enum DisplayNameValidator {
    static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func validationMessage(for value: String) -> String? {
        let name = normalized(value)
        guard !name.isEmpty else {
            return "Enter your full name."
        }
        guard name.count <= 80 else {
            return "Use 80 characters or fewer."
        }
        return nil
    }

    static func isValid(_ value: String) -> Bool {
        validationMessage(for: value) == nil
    }
}

nonisolated enum HandleValidator {
    static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("@")
            .lowercased()
    }

    static func validationMessage(for value: String) -> String? {
        let handle = normalized(value)
        guard (3 ... 30).contains(handle.count) else {
            return "Use 3–30 characters."
        }

        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "_"))
        guard handle.unicodeScalars.allSatisfy(allowed.contains),
              handle.first?.isLetter == true
                || handle.first?.isNumber == true
        else {
            return "Use lowercase letters, numbers, and underscores only."
        }
        return nil
    }

    static func isValid(_ value: String) -> Bool {
        validationMessage(for: value) == nil
    }
}

private extension String {
    func trimmingPrefix(_ prefix: Character) -> String {
        first == prefix ? String(dropFirst()) : self
    }
}
