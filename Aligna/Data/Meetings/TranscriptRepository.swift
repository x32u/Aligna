import Foundation

protocol TranscriptRepository: Sendable {
    func transcript(for meetingID: UUID) async throws -> TranscriptDocument?
    func save(_ document: TranscriptDocument) async throws
}

actor InMemoryTranscriptRepository: TranscriptRepository {
    private var documents: [UUID: TranscriptDocument]

    init(documents: [TranscriptDocument] = []) {
        self.documents = Dictionary(
            uniqueKeysWithValues: documents.map { ($0.meetingID, $0) }
        )
    }

    func transcript(for meetingID: UUID) -> TranscriptDocument? {
        documents[meetingID]
    }

    func save(_ document: TranscriptDocument) {
        documents[document.meetingID] = document
    }
}

actor LocalTranscriptRepository: TranscriptRepository {
    private let ownerUserID: UUID?
    private let directory: URL?
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(ownerUserID: UUID?, directory: URL? = nil) {
        self.ownerUserID = ownerUserID
        self.directory = directory

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func transcript(for meetingID: UUID) throws -> TranscriptDocument? {
        let url = try fileURL(for: meetingID)
        guard fileManager.fileExists(atPath: url.path()) else {
            return nil
        }
        let document = try decoder.decode(
            TranscriptDocument.self,
            from: Data(contentsOf: url)
        )
        try validateOwner(document.ownerUserID)
        return document
    }

    func save(_ document: TranscriptDocument) throws {
        try validateOwner(document.ownerUserID)
        let data = try encoder.encode(document)
        try data.write(
            to: fileURL(for: document.meetingID),
            options: [.atomic]
        )
    }

    private func validateOwner(_ documentOwnerID: UUID?) throws {
        guard let ownerUserID else { return }
        guard documentOwnerID == ownerUserID else {
            throw LocalTranscriptRepositoryError.ownerMismatch
        }
    }

    private func fileURL(for meetingID: UUID) throws -> URL {
        let base: URL
        if let directory {
            base = directory
        } else {
            base = try MeetingFileLocations.applicationSupportDirectory()
                .appending(path: "Transcripts", directoryHint: .isDirectory)
        }
        let ownedDirectory = ownerUserID.map {
            base.appending(
                path: $0.uuidString.lowercased(),
                directoryHint: .isDirectory
            )
        } ?? base.appending(path: "legacy", directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: ownedDirectory,
            withIntermediateDirectories: true
        )
        return ownedDirectory.appending(
            path: "\(meetingID.uuidString.lowercased()).json"
        )
    }
}

enum LocalTranscriptRepositoryError: LocalizedError {
    case ownerMismatch

    var errorDescription: String? {
        "This transcript belongs to a different Aligna account."
    }
}
