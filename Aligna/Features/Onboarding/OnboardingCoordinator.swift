import Foundation

nonisolated enum OnboardingStep: Equatable, Sendable {
    case profile
    case voice
    case workspace
    case complete
}

nonisolated enum OnboardingCoordinator {
    static func nextStep(
        profile: UserProfile?,
        workspaces: [Workspace]
    ) -> OnboardingStep {
        guard let profile, profile.isComplete else {
            return .profile
        }

        if !profile.onboardingCompleted,
           !profile.voiceEnrollmentStatus.isOnboardingDecisionComplete {
            return .voice
        }

        guard !workspaces.isEmpty else {
            return .workspace
        }
        return .complete
    }
}
