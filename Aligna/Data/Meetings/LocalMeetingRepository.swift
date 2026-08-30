import Foundation

enum MeetingFileLocations {
    nonisolated static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return directory.appending(path: "Aligna", directoryHint: .isDirectory)
    }

    nonisolated static func recordingsDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "Recordings", directoryHint: .isDirectory)
    }

    nonisolated static func recordingURL(
        fileName: String,
        fileManager: FileManager = .default
    ) -> URL? {
        try? recordingsDirectory(fileManager: fileManager)
            .appending(path: fileName)
    }
}

actor LocalMeetingRepository: MeetingRepository, LegacyMeetingMigrating {
    /// Date coding for the on-disk meeting store.
    ///
    /// `.iso8601` truncates to whole seconds, so a saved `Meeting` never
    /// compared equal to the one that was written — `scheduledAt` lost its
    /// fractional part on every round trip. Encoding uses `Date`'s native
    /// representation, which is exact; decoding still accepts the ISO8601
    /// strings written by earlier builds.
    nonisolated enum DateCoding {
        private static let fractionalSeconds = Date.ISO8601FormatStyle(
            includingFractionalSeconds: true
        )
        private static let wholeSeconds = Date.ISO8601FormatStyle(
            includingFractionalSeconds: false
        )

        static let encodingStrategy: JSONEncoder.DateEncodingStrategy =
            .deferredToDate

        static let decodingStrategy: JSONDecoder.DateDecodingStrategy =
            .custom { decoder in
                let container = try decoder.singleValueContainer()
                if let seconds = try? container.decode(Double.self) {
                    return Date(timeIntervalSinceReferenceDate: seconds)
                }
                // Files written before this change store ISO8601 strings.
                let text = try container.decode(String.self)
                if let date = try? fractionalSeconds.parse(text) {
                    return date
                }
                return try wholeSeconds.parse(text)
            }
    }

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let overrideDirectory: URL?
    private let recordingsDirectoryOverride: URL?
    private let ownerUserID: UUID?

    init(
        ownerUserID: UUID? = nil,
        directory: URL? = nil,
        recordingsDirectory: URL? = nil
    ) {
        self.ownerUserID = ownerUserID
        self.overrideDirectory = directory
        self.recordingsDirectoryOverride = recordingsDirectory

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = DateCoding.encodingStrategy
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = DateCoding.decodingStrategy
        self.decoder = decoder
    }

    func fetchMeetings() throws -> [Meeting] {
        let fileURL = try meetingsFileURL()
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([Meeting].self, from: data)
            .sorted { $0.scheduledAt > $1.scheduledAt }
    }

    @discardableResult
    func save(_ meeting: Meeting) throws -> Meeting {
        if let ownerUserID,
           let meetingOwnerID = meeting.ownerUserID,
           meetingOwnerID != ownerUserID {
            throw LocalMeetingRepositoryError.ownerMismatch
        }
        let ownedMeeting: Meeting
        if let ownerUserID, meeting.ownerUserID == nil {
            ownedMeeting = meeting.withCloudMetadata(
                ownerUserID: ownerUserID,
                workspaceID: meeting.workspaceID,
                organizerUserID: meeting.organizerUserID,
                participantUserIDs: meeting.participantUserIDs,
                syncState: meeting.syncState
            )
        } else {
            ownedMeeting = meeting
        }

        var meetings = try fetchMeetings()
        meetings.removeAll { $0.id == ownedMeeting.id }
        meetings.append(ownedMeeting)
        meetings.sort { $0.scheduledAt > $1.scheduledAt }

        try persist(meetings)
        return ownedMeeting
    }

    func delete(_ meeting: Meeting) throws {
        try validateOwner(of: meeting)

        let storedMeetings = try fetchMeetings()
        guard let storedMeeting = storedMeetings.first(where: {
            $0.id == meeting.id
        }) else {
            return
        }

        let remainingMeetings = storedMeetings.filter {
            $0.id != storedMeeting.id
        }
        try persist(remainingMeetings)

        do {
            try deleteRecordingIfUnreferenced(
                for: storedMeeting,
                remainingMeetings: remainingMeetings
            )
        } catch {
            try? persist(storedMeetings)
            throw error
        }
    }

    func legacyMeetings() throws -> [Meeting] {
        guard ownerUserID != nil else { return [] }
        let fileURL = try repositoryDirectory()
            .appending(path: "meetings.json")
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([Meeting].self, from: data)
            .filter { $0.ownerUserID == nil }
    }

    func legacyMeetingCount() throws -> Int {
        try legacyMeetings().count
    }

    func claimLegacyMeetings() throws -> Int {
        guard let ownerUserID else { return 0 }
        let legacy = try legacyMeetings()
        for meeting in legacy {
            let claimed = meeting.withCloudMetadata(
                ownerUserID: ownerUserID,
                workspaceID: meeting.workspaceID,
                organizerUserID: ownerUserID,
                participantUserIDs: meeting.participantUserIDs,
                syncState: .local
            )
            try save(claimed)
        }
        return legacy.count
    }

    private func meetingsFileURL() throws -> URL {
        let directory = try repositoryDirectory()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        if let ownerUserID {
            let userDirectory = directory.appending(
                path: ownerUserID.uuidString.lowercased(),
                directoryHint: .isDirectory
            )
            try fileManager.createDirectory(
                at: userDirectory,
                withIntermediateDirectories: true
            )
            return userDirectory.appending(path: "meetings.json")
        }
        return directory.appending(path: "meetings.json")
    }

    private func repositoryDirectory() throws -> URL {
        if let overrideDirectory {
            return overrideDirectory
        }
        return try MeetingFileLocations.applicationSupportDirectory(
            fileManager: fileManager
        ).appending(path: "Meetings", directoryHint: .isDirectory)
    }

    private func persist(_ meetings: [Meeting]) throws {
        let data = try encoder.encode(meetings)
        try data.write(to: meetingsFileURL(), options: [.atomic])
    }

    private func validateOwner(of meeting: Meeting) throws {
        guard let ownerUserID,
              let meetingOwnerID = meeting.ownerUserID
        else {
            return
        }
        guard meetingOwnerID == ownerUserID else {
            throw LocalMeetingRepositoryError.ownerMismatch
        }
    }

    private func deleteRecordingIfUnreferenced(
        for meeting: Meeting,
        remainingMeetings: [Meeting]
    ) throws {
        guard let fileName = meeting.audioFileName,
              !remainingMeetings.contains(where: {
                  $0.audioFileName == fileName
              })
        else {
            return
        }
        guard fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              !fileName.isEmpty
        else {
            throw LocalMeetingRepositoryError.invalidRecordingFileName
        }

        let directory = try recordingsDirectoryOverride
            ?? MeetingFileLocations.recordingsDirectory(
                fileManager: fileManager
            )
        let recordingURL = directory.appending(path: fileName)
        guard fileManager.fileExists(atPath: recordingURL.path()) else {
            return
        }
        do {
            try fileManager.removeItem(at: recordingURL)
        } catch {
            throw LocalMeetingRepositoryError.recordingDeletionFailed
        }
    }
}

enum LocalMeetingRepositoryError: LocalizedError {
    case ownerMismatch
    case invalidRecordingFileName
    case recordingDeletionFailed

    var errorDescription: String? {
        switch self {
        case .ownerMismatch:
            "This local meeting belongs to a different Aligna account."
        case .invalidRecordingFileName:
            "The saved recording path is invalid."
        case .recordingDeletionFailed:
            "The meeting was kept because its recording could not be removed."
        }
    }
}
