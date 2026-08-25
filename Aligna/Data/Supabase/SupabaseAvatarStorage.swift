import Foundation
import Supabase

actor SupabaseAvatarStorage: AvatarStorage {
    private let client: SupabaseClient

    init(provider: SupabaseClientProvider) {
        client = provider.client
    }

    func uploadJPEG(_ data: Data, userID: UUID) async throws -> String {
        let path = "\(userID.uuidString.lowercased())/profile.jpg"
        try await client.storage
            .from("avatars")
            .upload(
                path,
                data: data,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )
        return path
    }

    func removeAvatar(userID: UUID) async throws {
        let path = "\(userID.uuidString.lowercased())/profile.jpg"
        try await client.storage.from("avatars").remove(paths: [path])
    }

    func signedURL(path: String) async throws -> URL {
        try await client.storage
            .from("avatars")
            .createSignedURL(path: path, expiresIn: 3_600)
    }
}
