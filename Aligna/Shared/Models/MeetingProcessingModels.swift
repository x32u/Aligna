import Foundation

nonisolated enum MeetingProcessingStatus:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Sendable {
    case queued
    case uploading
    case transcribing
    case preparingSpeakers = "preparing_speakers"
    case diarizing
    case matchingSpeakers = "matching_speakers"
    case mergingTranscript = "merging_transcript"
    case analyzing
    case complete
    case failed

    var customerTitle: String {
        switch self {
        case .queued, .uploading:
            "Preparing recording"
        case .transcribing:
            "Creating transcript"
        case .preparingSpeakers, .diarizing, .matchingSpeakers,
             .mergingTranscript, .analyzing:
            "Organizing your notes"
        case .complete:
            "Notes ready"
        case .failed:
            "Needs processing"
        }
    }

    var isProcessing: Bool {
        switch self {
        case .queued, .uploading, .transcribing, .preparingSpeakers,
             .diarizing, .matchingSpeakers, .mergingTranscript, .analyzing:
            true
        case .complete, .failed:
            false
        }
    }

    var customerPhase: MeetingProcessingPhase? {
        switch self {
        case .queued, .uploading:
            .preparingRecording
        case .transcribing:
            .creatingTranscript
        case .preparingSpeakers, .diarizing, .matchingSpeakers,
             .mergingTranscript, .analyzing:
            .organizingNotes
        case .complete, .failed:
            nil
        }
    }
}

nonisolated enum MeetingProcessingPhase:
    Int,
    CaseIterable,
    Hashable,
    Sendable {
    case preparingRecording
    case creatingTranscript
    case organizingNotes
}

nonisolated enum MeetingProcessingIssue: Hashable, Sendable {
    case offline
    case serviceUnavailable
    case signInRequired
    case recordingUnavailable
    case uploadFailed

    var message: String {
        switch self {
        case .offline:
            "Saved on this iPhone. Processing will continue when you’re connected."
        case .serviceUnavailable:
            "Aligna couldn’t start processing right now. Your recording is safe—try again in a moment."
        case .signInRequired:
            "Your session needs to be refreshed before Aligna can process this meeting."
        case .recordingUnavailable:
            "The saved recording couldn’t be prepared. The original audio is still on this iPhone."
        case .uploadFailed:
            "The recording couldn’t be uploaded. Your local copy is safe and ready to retry."
        }
    }

    var systemImage: String {
        switch self {
        case .offline:
            "wifi.slash"
        case .serviceUnavailable:
            "clock.arrow.circlepath"
        case .signInRequired:
            "person.crop.circle.badge.exclamationmark"
        case .recordingUnavailable:
            "waveform.badge.exclamationmark"
        case .uploadFailed:
            "icloud.and.arrow.up"
        }
    }
}

nonisolated struct MeetingEvidence:
    Codable,
    Hashable,
    Sendable {
    let timestampSeconds: TimeInterval
    let quote: String

    enum CodingKeys: String, CodingKey {
        case timestampSeconds = "timestamp_seconds"
        case quote
    }
}

nonisolated struct MeetingInsight:
    Identifiable,
    Codable,
    Hashable,
    Sendable {
    let id: UUID
    let text: String
    let evidence: MeetingEvidence

    init(
        id: UUID = UUID(),
        text: String,
        evidence: MeetingEvidence
    ) {
        self.id = id
        self.text = text
        self.evidence = evidence
    }

    enum CodingKeys: String, CodingKey {
        case text
        case evidence
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        text = try values.decode(String.self, forKey: .text)
        evidence = try values.decode(MeetingEvidence.self, forKey: .evidence)
    }
}

nonisolated struct MeetingActionItem:
    Identifiable,
    Codable,
    Hashable,
    Sendable {
    let id: UUID
    let task: String
    let assignee: String?
    let assigneeUserID: UUID?
    let assigneeDisplayName: String?
    let assignmentConfidence: Float?
    let evidenceSpeakerKey: String?
    let dueDate: String?
    let evidence: MeetingEvidence

    init(
        id: UUID = UUID(),
        task: String,
        assignee: String?,
        assigneeUserID: UUID? = nil,
        assigneeDisplayName: String? = nil,
        assignmentConfidence: Float? = nil,
        evidenceSpeakerKey: String? = nil,
        dueDate: String?,
        evidence: MeetingEvidence
    ) {
        self.id = id
        self.task = task
        self.assignee = assignee
        self.assigneeUserID = assigneeUserID
        self.assigneeDisplayName = assigneeDisplayName
        self.assignmentConfidence = assignmentConfidence
        self.evidenceSpeakerKey = evidenceSpeakerKey
        self.dueDate = dueDate
        self.evidence = evidence
    }

    enum CodingKeys: String, CodingKey {
        case task
        case assignee
        case assigneeUserID = "assignee_user_id"
        case assigneeDisplayName = "assignee_display_name"
        case assignmentConfidence = "assignment_confidence"
        case evidenceSpeakerKey = "evidence_speaker_key"
        case dueDate = "due_date"
        case evidence
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        task = try values.decode(String.self, forKey: .task)
        assignee = try values.decodeIfPresent(String.self, forKey: .assignee)
        assigneeUserID = try values.decodeIfPresent(
            UUID.self,
            forKey: .assigneeUserID
        )
        assigneeDisplayName = try values.decodeIfPresent(
            String.self,
            forKey: .assigneeDisplayName
        )
        assignmentConfidence = try values.decodeIfPresent(
            Float.self,
            forKey: .assignmentConfidence
        )
        evidenceSpeakerKey = try values.decodeIfPresent(
            String.self,
            forKey: .evidenceSpeakerKey
        )
        dueDate = try values.decodeIfPresent(String.self, forKey: .dueDate)
        evidence = try values.decode(MeetingEvidence.self, forKey: .evidence)
    }
}

nonisolated struct MeetingAnalysis:
    Codable,
    Hashable,
    Sendable {
    let generatedTitle: String
    let summary: String
    let keyPoints: [MeetingInsight]
    let decisions: [MeetingInsight]
    let actionItems: [MeetingActionItem]
    let openQuestions: [MeetingInsight]
    let followUps: [MeetingInsight]
    let languagesDetected: [String]

    enum CodingKeys: String, CodingKey {
        case generatedTitle = "generated_title"
        case summary
        case keyPoints = "key_points"
        case decisions
        case actionItems = "action_items"
        case openQuestions = "open_questions"
        case followUps = "follow_ups"
        case languagesDetected = "languages_detected"
    }
}

nonisolated struct PreparedAudioChunk:
    Identifiable,
    Hashable,
    Sendable {
    let id: UUID
    let fileURL: URL
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        fileURL: URL,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval
    ) {
        self.id = id
        self.fileURL = fileURL
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}
