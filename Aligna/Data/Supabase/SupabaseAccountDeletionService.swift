import Foundation
import Supabase

nonisolated struct DeleteAccountBody: Encodable, Sendable {
    let confirmSoleMemberWorkspaceDeletion: Bool
}

actor SupabaseAccountDeletionService: AccountDeletionServicing {
    private let client: SupabaseClient

    init(provider: SupabaseClientProvider) {
        client = provider.client
    }

    func deleteAccount(
        confirmingSoleMemberWorkspaceDeletion: Bool
    ) async throws {
        try await client.functions.invoke(
            "delete-account",
            options: FunctionInvokeOptions(
                body: DeleteAccountBody(
                    confirmSoleMemberWorkspaceDeletion:
                        confirmingSoleMemberWorkspaceDeletion
                )
            )
        )
    }
}
