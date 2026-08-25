import CryptoKit
import Foundation
import Security

nonisolated protocol LocalVoiceProfileStoring: Sendable {
    func save(_ embedding: VoiceEmbedding, userID: UUID) async throws
    func load(userID: UUID) async throws -> VoiceEmbedding?
    func delete(userID: UUID) async throws
}

actor LocalVoiceProfileStore: LocalVoiceProfileStoring {
    private let fileManager: FileManager
    private let keychainService =
        "dev.notjc.Aligna.voice-profile-encryption"
    private let keychainAccount = "local-profile-key-v1"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func save(
        _ embedding: VoiceEmbedding,
        userID: UUID
    ) async throws {
        guard embedding.isFinite else {
            throw VoiceRecognitionError.invalidEmbedding
        }
        let payload = try JSONEncoder().encode(
            LocalVoiceProfilePayload(
                embedding: embedding,
                savedAt: .now
            )
        )
        let sealed = try AES.GCM.seal(
            payload,
            using: try encryptionKey()
        )
        guard let combined = sealed.combined else {
            throw VoiceRecognitionError.invalidEmbedding
        }

        let url = try profileURL(userID: userID)
        try combined.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    func load(userID: UUID) async throws -> VoiceEmbedding? {
        let url = try profileURL(userID: userID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let encrypted = try Data(contentsOf: url)
        let box = try AES.GCM.SealedBox(combined: encrypted)
        let plaintext = try AES.GCM.open(
            box,
            using: try encryptionKey()
        )
        let payload = try JSONDecoder().decode(
            LocalVoiceProfilePayload.self,
            from: plaintext
        )
        guard payload.embedding.isFinite else {
            throw VoiceRecognitionError.invalidEmbedding
        }
        return payload.embedding
    }

    func delete(userID: UUID) async throws {
        let url = try profileURL(userID: userID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func profileURL(userID: UUID) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(
            "VoiceProfiles",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [
                .protectionKey:
                    FileProtectionType
                        .completeUntilFirstUserAuthentication
            ]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
        return directory.appendingPathComponent(
            "\(userID.uuidString.lowercased()).profile"
        )
    }

    private func encryptionKey() throws -> SymmetricKey {
        var lookup = keychainQuery
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            lookup as CFDictionary,
            &result
        )
        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else {
            throw VoiceRecognitionError.interrupted
        }

        let data = Data(SymmetricKey(size: .bits256).withUnsafeBytes {
            Data($0)
        })
        var insertion = keychainQuery
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insertion as CFDictionary, nil)
                == errSecSuccess else {
            throw VoiceRecognitionError.interrupted
        }
        return SymmetricKey(data: data)
    }

    private var keychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }
}

nonisolated private struct LocalVoiceProfilePayload:
    Codable,
    Sendable {
    let embedding: VoiceEmbedding
    let savedAt: Date
}

actor MockLocalVoiceProfileStore: LocalVoiceProfileStoring {
    private var profiles: [UUID: VoiceEmbedding] = [:]

    func save(_ embedding: VoiceEmbedding, userID: UUID) {
        profiles[userID] = embedding
    }

    func load(userID: UUID) -> VoiceEmbedding? {
        profiles[userID]
    }

    func delete(userID: UUID) {
        profiles[userID] = nil
    }
}
