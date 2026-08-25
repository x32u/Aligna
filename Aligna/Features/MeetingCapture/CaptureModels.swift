import Foundation

nonisolated struct MeetingCreationContext: Sendable {
    let workspace: Workspace
    let organizerUserID: UUID
    let workspaceRepository: any WorkspaceRepository
}

nonisolated struct NewMeetingConfiguration: Hashable, Sendable {
    let title: String
    let participantNames: [String]
    let localeIdentifier: String
    let transcriptionEngine: TranscriptionEngineKind
    let termsToRecognize: [String]
    let workspace: Workspace?
    let organizerUserID: UUID?
    let selectedMembers: [WorkspaceMember]

    var participants: [MeetingParticipant] {
        let selected = selectedMembers.map {
            MeetingParticipant(
                name: $0.displayName,
                userID: $0.userID,
                handle: $0.handle,
                responseStatus: .invited
            )
        }
        let selectedNames = Set(
            selected.map { $0.name.lowercased() }
        )
        let manual = participantNames
            .filter { !selectedNames.contains($0.lowercased()) }
            .map { MeetingParticipant(name: $0) }
        return selected + manual
    }

    init(
        title: String,
        participantNames: [String],
        localeIdentifier: String,
        transcriptionEngine: TranscriptionEngineKind =
            .speechTranscriber,
        termsToRecognize: [String] = [],
        workspace: Workspace? = nil,
        organizerUserID: UUID? = nil,
        selectedMembers: [WorkspaceMember] = []
    ) {
        self.title = title
        self.participantNames = participantNames
        self.localeIdentifier =
            TranscriptionLanguage.normalizedIdentifier(localeIdentifier)
        self.transcriptionEngine = transcriptionEngine
        self.termsToRecognize = termsToRecognize
        self.workspace = workspace
        self.organizerUserID = organizerUserID
        self.selectedMembers = selectedMembers
    }
}

nonisolated enum TranscriptionEvent: Hashable, Sendable {
    case volatile(TranscriptSegment)
    case finalized(TranscriptSegment)
}

nonisolated struct TranscriptAccumulator: Equatable, Sendable {
    private(set) var finalizedSegments: [TranscriptSegment] = []
    private(set) var volatileSegment: TranscriptSegment?

    mutating func consume(_ event: TranscriptionEvent) {
        switch event {
        case let .volatile(segment):
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            volatileSegment = trimmed.isEmpty ? nil : segment

        case let .finalized(segment):
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                volatileSegment = nil
                return
            }

            if !finalizedSegments.contains(where: {
                $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(trimmed) == .orderedSame
                    && approximatelyEqual($0.startTime, segment.startTime)
            }) {
                finalizedSegments.append(
                    TranscriptSegment(
                        id: segment.id,
                        text: trimmed,
                        startTime: segment.startTime,
                        endTime: segment.endTime,
                        isFinal: true,
                        speaker: nil
                    )
                )
            }
            volatileSegment = nil
        }
    }

    private func approximatelyEqual(
        _ lhs: TimeInterval?,
        _ rhs: TimeInterval?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): abs(lhs - rhs) < 0.25
        default: false
        }
    }
}

nonisolated struct RecordingDurationTracker: Equatable, Sendable {
    private(set) var accumulated: TimeInterval = 0
    private(set) var activeStart: Date?

    mutating func start(at date: Date) {
        guard activeStart == nil, accumulated == 0 else { return }
        activeStart = date
    }

    mutating func pause(at date: Date) {
        guard let activeStart else { return }
        accumulated += max(0, date.timeIntervalSince(activeStart))
        self.activeStart = nil
    }

    mutating func resume(at date: Date) {
        guard activeStart == nil else { return }
        activeStart = date
    }

    mutating func finish(at date: Date) -> TimeInterval {
        pause(at: date)
        return accumulated
    }

    func elapsed(at date: Date) -> TimeInterval {
        guard let activeStart else { return accumulated }
        return accumulated + max(0, date.timeIntervalSince(activeStart))
    }
}

nonisolated struct AudioLevelHistory: Equatable, Sendable {
    private(set) var samples: [Float]
    private var smoothedLevel: Float

    init(sampleCount: Int = 36, restingLevel: Float = 0.06) {
        samples = Array(
            repeating: restingLevel,
            count: max(1, sampleCount)
        )
        smoothedLevel = restingLevel
    }

    mutating func append(rawLevel: Float) -> [Float] {
        let clampedLevel = min(max(rawLevel, 0), 1)
        let responsiveLevel = pow(clampedLevel, 0.72)
        let smoothingFactor: Float =
            responsiveLevel > smoothedLevel ? 0.42 : 0.16

        smoothedLevel += (
            responsiveLevel - smoothedLevel
        ) * smoothingFactor

        samples.removeFirst()
        samples.append(max(0.045, smoothedLevel))
        return samples
    }

    mutating func settle() -> [Float] {
        smoothedLevel = 0.045
        samples = Array(repeating: smoothedLevel, count: samples.count)
        return samples
    }
}
