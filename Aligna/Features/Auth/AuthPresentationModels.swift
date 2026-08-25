import Foundation

nonisolated enum EmailVerificationStatus: Equatable, Sendable {
    case waiting
    case checking
    case resent
    case expired
    case failed(String)
}

nonisolated enum PasswordRecoveryStatus: Equatable, Sendable {
    case idle
    case linkSent(String)
    case processing
    case ready
    case expired
    case failed(String)
}

nonisolated struct AuthNotice: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case success
        case information
    }

    let style: Style
    let message: String
}

nonisolated struct AuthResendCooldown: Equatable, Sendable {
    let duration: TimeInterval
    private(set) var nextAllowedAt: Date?

    init(
        duration: TimeInterval = SignUpConfirmationPolicy.resendCooldown,
        startedAt: Date? = nil
    ) {
        self.duration = duration
        nextAllowedAt = startedAt?.addingTimeInterval(duration)
    }

    mutating func start(at date: Date = .now) {
        nextAllowedAt = date.addingTimeInterval(duration)
    }

    func remainingSeconds(at date: Date = .now) -> Int {
        guard let nextAllowedAt else { return 0 }
        return max(0, Int(ceil(nextAllowedAt.timeIntervalSince(date))))
    }

    func canResend(at date: Date = .now) -> Bool {
        remainingSeconds(at: date) == 0
    }
}

nonisolated enum EmailMasker {
    static func masked(_ rawEmail: String) -> String {
        let email = EmailValidator.normalized(rawEmail)
        guard let separator = email.firstIndex(of: "@") else {
            return email
        }

        let localPart = String(email[..<separator])
        let domain = String(email[email.index(after: separator)...])
        guard !localPart.isEmpty, !domain.isEmpty else {
            return email
        }

        let visiblePrefixCount = min(2, localPart.count)
        let prefix = localPart.prefix(visiblePrefixCount)
        let maskCount = max(3, localPart.count - visiblePrefixCount)
        return "\(prefix)\(String(repeating: "•", count: maskCount))@\(domain)"
    }
}
