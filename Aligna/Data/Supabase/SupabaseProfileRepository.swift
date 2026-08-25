import Foundation
import Supabase

actor SupabaseProfileRepository: ProfileRepository {
    private let client: SupabaseClient

    init(provider: SupabaseClientProvider) {
        client = provider.client
    }

    func profile(userID: UUID) async throws -> UserProfile? {
        let profiles: [ProfileDTO] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value
        return profiles.first?.domain
    }

    func update(
        userID: UUID,
        displayName: String,
        handle: String,
        avatarPath: String?,
        onboardingCompleted: Bool
    ) async throws -> UserProfile {
        let dto = ProfileUpdateDTO(
            displayName: displayName.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            handle: HandleValidator.normalized(handle),
            avatarPath: avatarPath,
            onboardingCompleted: onboardingCompleted
        )
        do {
            let profile: ProfileDTO = try await client
                .from("profiles")
                .update(dto)
                .eq("id", value: userID)
                .select()
                .single()
                .execute()
                .value
            return profile.domain
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("duplicate")
                || message.contains("profiles_handle_unique") {
                throw AuthenticationServiceError.usernameAlreadyUsed
            }
            throw error
        }
    }
}
