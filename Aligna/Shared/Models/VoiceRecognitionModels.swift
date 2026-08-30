import Foundation

nonisolated enum VoiceEnrollmentStatus:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Sendable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case enrolled
    case skipped
    case needsReenrollment = "needs_reenrollment"

    var isOnboardingDecisionComplete: Bool {
        self == .enrolled || self == .skipped
    }

    var customerTitle: String {
        switch self {
        case .notStarted:
            "Not set up"
        case .inProgress:
            "Setup in progress"
        case .enrolled:
            "On"
        case .skipped:
            "Not set up"
        case .needsReenrollment:
            "Update required"
        }
    }
}

nonisolated struct VoiceModelDescriptor:
    Codable,
    Hashable,
    Sendable {
    static let fluidAudioOfflineV1 = VoiceModelDescriptor(
        provider: "FluidAudio",
        packageVersion: "0.15.5",
        modelVersion: "offline-diarizer-v1",
        embeddingDimension: 256
    )

    let provider: String
    let packageVersion: String
    let modelVersion: String
    let embeddingDimension: Int

    var compatibilityKey: String {
        "\(provider):\(modelVersion):\(embeddingDimension)"
    }
}

nonisolated struct VoiceEmbedding: Codable, Hashable, Sendable {
    let values: [Float]
    let model: VoiceModelDescriptor

    var isFinite: Bool {
        values.count == model.embeddingDimension
            && values.allSatisfy(\.isFinite)
    }
}

nonisolated struct CandidateVoiceProfile:
    Identifiable,
    Hashable,
    Sendable {
    var id: UUID { userID }

    let userID: UUID
    let displayName: String
    let avatarPath: String?
    let embedding: VoiceEmbedding
}

nonisolated enum EnrollmentSampleIssue:
    String,
    Codable,
    Hashable,
    Sendable {
    case insufficientSpeech
    case tooQuiet
    case clipped
    case noisy
    case multipleSpeakers
    case interrupted
    var message: String {
        switch self {
        case .insufficientSpeech:
            "Read the full line, then pause for a moment."
        case .tooQuiet:
            "Speak a little louder."
        case .clipped:
            "Move your iPhone a little farther away and try again."
        case .noisy:
            "Let’s try that again somewhere quieter."
        case .multipleSpeakers:
            "We heard another voice. Please try this line by yourself."
        case .interrupted:
            "The recording was interrupted. Let’s try that line again."
        }
    }
}

nonisolated struct EnrollmentSampleQuality:
    Hashable,
    Sendable {
    let durationSeconds: TimeInterval
    let voicedSeconds: TimeInterval
    let rootMeanSquare: Float
    let peakAmplitude: Float
    let issue: EnrollmentSampleIssue?

    var isAccepted: Bool { issue == nil }
}

nonisolated struct DiarizationInterval:
    Identifiable,
    Codable,
    Hashable,
    Sendable {
    let id: UUID
    let stableSpeakerKey: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        stableSpeakerKey: String,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval
    ) {
        self.id = id
        self.stableSpeakerKey = stableSpeakerKey
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

nonisolated struct SpeakerCluster:
    Identifiable,
    Hashable,
    Sendable {
    var id: String { stableSpeakerKey }

    let stableSpeakerKey: String
    let embedding: VoiceEmbedding
}

nonisolated enum SpeakerMatchState: String, Codable, Hashable, Sendable {
    case recognized
    case unknown
    case ambiguous
}

nonisolated struct SpeakerMatch: Hashable, Sendable {
    let stableSpeakerKey: String
    let state: SpeakerMatchState
    let userID: UUID?
    let displayName: String
    let confidence: Float?
}

nonisolated struct WhisperWord:
    Identifiable,
    Codable,
    Hashable,
    Sendable {
    let id: UUID
    let text: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        text: String,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval
    ) {
        self.id = id
        self.text = text
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

nonisolated enum SpeakerAttributionSource:
    String,
    Codable,
    Hashable,
    Sendable {
    case voiceProfile = "voice_profile"
    case manualCorrection = "manual_correction"
    case anonymous
    case ambiguous
}

nonisolated struct AttributedTranscriptTurn:
    Identifiable,
    Codable,
    Hashable,
    Sendable {
    let id: UUID
    let stableSpeakerKey: String
    let speakerUserID: UUID?
    let speakerDisplayName: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let text: String
    let attributionConfidence: Float?
    let attributionSource: SpeakerAttributionSource

    init(
        id: UUID = UUID(),
        stableSpeakerKey: String,
        speakerUserID: UUID?,
        speakerDisplayName: String,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        text: String,
        attributionConfidence: Float?,
        attributionSource: SpeakerAttributionSource
    ) {
        self.id = id
        self.stableSpeakerKey = stableSpeakerKey
        self.speakerUserID = speakerUserID
        self.speakerDisplayName = speakerDisplayName
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.attributionConfidence = attributionConfidence
        self.attributionSource = attributionSource
    }
}

nonisolated struct DiarizationOutput: Hashable, Sendable {
    let intervals: [DiarizationInterval]
    let clusters: [SpeakerCluster]
}

nonisolated enum VoiceRecognitionError:
    LocalizedError,
    Equatable,
    Sendable {
    case modelUnavailable
    case noSpeech
    case multipleSpeakers
    case incompatibleModel
    case invalidEmbedding
    case unauthorized
    case configurationMissing
    case offline
    case interrupted

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Voice recognition isn’t ready yet. Connect to the internet and try again."
        case .noSpeech:
            "Aligna couldn’t find enough speech in that recording."
        case .multipleSpeakers:
            "We heard another voice. Please try this line by yourself."
        case .incompatibleModel:
            "Voice recognition needs a quick update. Record your voice again."
        case .invalidEmbedding:
            "Aligna couldn’t create a reliable voice profile. Please try again."
        case .unauthorized:
            "Your account session needs to be refreshed. Sign in again and try once more."
        case .configurationMissing:
            "Voice recognition needs one more setup step before it can save your profile."
        case .offline:
            "Connect to the internet to finish setting up voice recognition."
        case .interrupted:
            "Voice processing was interrupted. Your meeting recording is still safe."
        }
    }

    /// Stable, non-localized code for diagnostics. Kept separate from
    /// `errorDescription` so log analysis never depends on user-facing copy.
    var diagnosticCode: String {
        switch self {
        case .modelUnavailable: "model_unavailable"
        case .noSpeech: "no_speech"
        case .multipleSpeakers: "multiple_speakers"
        case .incompatibleModel: "incompatible_model"
        case .invalidEmbedding: "invalid_embedding"
        case .unauthorized: "unauthorized"
        case .configurationMissing: "configuration_missing"
        case .offline: "offline"
        case .interrupted: "interrupted"
        }
    }
}
