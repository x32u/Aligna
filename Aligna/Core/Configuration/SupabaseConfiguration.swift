import Foundation

nonisolated struct SupabaseConfiguration: Equatable, Sendable {
    let projectURL: URL
    let publishableKey: String
    let callbackURL: URL

    static func load(bundle: Bundle = .main) -> Result<
        SupabaseConfiguration,
        SupabaseConfigurationError
    > {
        make(
            projectURL: bundle.object(
                forInfoDictionaryKey: "SUPABASE_URL"
            ) as? String,
            publishableKey: bundle.object(
                forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY"
            ) as? String
        )
    }

    static func make(
        projectURL rawURL: String?,
        publishableKey rawKey: String?
    ) -> Result<SupabaseConfiguration, SupabaseConfigurationError> {
        guard let rawURL,
        !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        let url = URL(string: rawURL),
        url.scheme == "https",
        url.host?.hasSuffix(".supabase.co") == true
        else {
            return .failure(.missingProjectURL)
        }

        guard let key = rawKey,
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        key.hasPrefix("sb_publishable_") || key.hasPrefix("eyJ")
        else {
            return .failure(.missingPublishableKey)
        }

        return .success(
            SupabaseConfiguration(
                projectURL: url,
                publishableKey: key,
                callbackURL: AuthRedirectConfiguration.callbackURL
            )
        )
    }
}

nonisolated enum SupabaseConfigurationError: LocalizedError, Equatable {
    case missingProjectURL
    case missingPublishableKey

    var errorDescription: String? {
        switch self {
        case .missingProjectURL:
            "SUPABASE_URL is missing or invalid. Copy Config/Secrets.xcconfig.example to Secrets.xcconfig."
        case .missingPublishableKey:
            "SUPABASE_PUBLISHABLE_KEY is missing. Add an active publishable key to Config/Secrets.xcconfig."
        }
    }
}
