import Foundation

nonisolated struct TranscriptVersion: Identifiable, Hashable, Codable, Sendable {
    enum Source: String, Hashable, Codable, Sendable {
        case liveApple
        case offlineApple
        case futureCloud
        case userEdited
    }

    enum ProcessingStatus: String, Hashable, Codable, Sendable {
        case processing
        case succeeded
        case failed
        case cancelled
    }

    let id: UUID
    let source: Source
    let engineIdentifier: String
    let localeIdentifier: String
    let createdAt: Date
    let segments: [TranscriptSegment]
    let processingStatus: ProcessingStatus
    let failureReason: String?

    init(
        id: UUID = UUID(),
        source: Source,
        engineIdentifier: String,
        localeIdentifier: String,
        createdAt: Date = .now,
        segments: [TranscriptSegment],
        processingStatus: ProcessingStatus,
        failureReason: String? = nil
    ) {
        self.id = id
        self.source = source
        self.engineIdentifier = engineIdentifier
        self.localeIdentifier = TranscriptionLanguage.normalizedIdentifier(
            localeIdentifier
        )
        self.createdAt = createdAt
        self.segments = segments.map { $0.applyingCorrection(nil) }
        self.processingStatus = processingStatus
        self.failureReason = failureReason
    }
}

nonisolated struct TranscriptDocument: Identifiable, Hashable, Codable, Sendable {
    var id: UUID { meetingID }

    let meetingID: UUID
    let ownerUserID: UUID?
    let selectedLocaleIdentifier: String
    private(set) var currentVersionID: UUID?
    private(set) var versions: [TranscriptVersion]
    private(set) var corrections: [UUID: String]
    let createdAt: Date
    private(set) var updatedAt: Date

    init(
        meetingID: UUID,
        ownerUserID: UUID?,
        selectedLocaleIdentifier: String,
        currentVersionID: UUID? = nil,
        versions: [TranscriptVersion] = [],
        corrections: [UUID: String] = [:],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.meetingID = meetingID
        self.ownerUserID = ownerUserID
        self.selectedLocaleIdentifier =
            TranscriptionLanguage.normalizedIdentifier(
                selectedLocaleIdentifier
            )
        self.currentVersionID = currentVersionID
            ?? versions.last(where: {
                $0.processingStatus == .succeeded
            })?.id
        self.versions = versions
        self.corrections = corrections
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var currentVersion: TranscriptVersion? {
        versions.first { $0.id == currentVersionID }
    }

    var effectiveSegments: [TranscriptSegment] {
        guard let currentVersion else { return [] }
        return currentVersion.segments.map {
            $0.applyingCorrection(corrections[$0.id])
        }
    }

    var hasCorrections: Bool {
        !corrections.isEmpty
    }

    mutating func append(_ version: TranscriptVersion, makeCurrent: Bool) {
        guard !versions.contains(where: { $0.id == version.id }) else {
            return
        }
        versions.append(version)
        if makeCurrent, version.processingStatus == .succeeded {
            currentVersionID = version.id
            corrections = corrections.filter { correction in
                version.segments.contains { $0.id == correction.key }
            }
        }
        updatedAt = .now
    }

    mutating func setCorrection(
        _ text: String,
        for segmentID: UUID,
        at date: Date = .now
    ) {
        guard let segment = currentVersion?.segments.first(where: {
            $0.id == segmentID
        }) else {
            return
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty
            || normalized == segment.originalText
        {
            corrections.removeValue(forKey: segmentID)
        } else {
            corrections[segmentID] = normalized
        }
        updatedAt = date
    }

    mutating func resetCorrection(
        for segmentID: UUID,
        at date: Date = .now
    ) {
        corrections.removeValue(forKey: segmentID)
        updatedAt = date
    }

    static func migratingLegacy(
        meetingID: UUID,
        ownerUserID: UUID?,
        localeIdentifier: String?,
        segments: [TranscriptSegment],
        createdAt: Date
    ) -> TranscriptDocument? {
        guard !segments.isEmpty else { return nil }
        let locale = localeIdentifier ?? "und"
        let version = TranscriptVersion(
            source: .liveApple,
            engineIdentifier: "legacy-apple-speech",
            localeIdentifier: locale,
            createdAt: createdAt,
            segments: segments,
            processingStatus: .succeeded
        )
        return TranscriptDocument(
            meetingID: meetingID,
            ownerUserID: ownerUserID,
            selectedLocaleIdentifier: locale,
            currentVersionID: version.id,
            versions: [version],
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
