import Foundation
import Supabase

nonisolated struct SupabaseClientProvider: Sendable {
    let client: SupabaseClient
    let configuration: SupabaseConfiguration

    init(configuration: SupabaseConfiguration) {
        self.configuration = configuration
        client = SupabaseClient(
            supabaseURL: configuration.projectURL,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(
                    flowType: .pkce,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}
