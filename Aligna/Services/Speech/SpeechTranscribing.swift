import Foundation

nonisolated enum TranscriptionPass: Hashable, Sendable {
    case live
    case final
}

nonisolated struct TranscriptionRequest: Hashable, Sendable {
    let localeIdentifier: String
    let engine: TranscriptionEngineKind
    let glossary: [String]

    init(
        localeIdentifier: String,
        engine: TranscriptionEngineKind,
        glossary: [String] = []
    ) {
        self.localeIdentifier =
            TranscriptionLanguage.normalizedIdentifier(localeIdentifier)
        self.engine = engine
        self.glossary = glossary
    }
}

protocol SpeechTranscribing: Sendable {
    func prepare(
        request: TranscriptionRequest,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws
    func startTranscription(
        audioSamples: AsyncThrowingStream<AudioSample, Error>
    ) async throws -> AsyncThrowingStream<TranscriptionEvent, Error>
    func finish() async throws
    func cancel() async
}

protocol FinalTranscriptionServicing: Sendable {
    func transcribe(
        audioURL: URL,
        meetingID: UUID,
        request: TranscriptionRequest,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> TranscriptVersion

    func cancel() async
}

protocol TranscriptionAssetManaging: Sendable {
    func prepareAssets(
        for request: TranscriptionRequest,
        pass: TranscriptionPass,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws

    func cancel() async
}

nonisolated enum TranscriptionServiceError:
    Error,
    Equatable,
    Sendable {
    case unsupportedLocale(String)
    case modelUnavailable
    case modelDownloadFailed
    case insufficientStorage
    case languageAllocationLimit
    case invalidAudioFile
    case audioConversionFailed
    case liveAnalyzerFailed
    case offlineAnalyzerFailed
    case cancelled
    case transcriptPersistenceFailed

    var userMessage: String {
        switch self {
        case let .unsupportedLocale(identifier):
            TranscriptionLanguage.isFilipino(identifier)
                ? "Filipino transcription isn’t available on this iPhone yet."
                : "This transcription language isn’t available on this iPhone."
        case .modelUnavailable:
            "The selected on-device language model is unavailable."
        case .modelDownloadFailed:
            "The language model could not be downloaded. Check your connection and try again."
        case .insufficientStorage:
            "There is not enough free storage to install this language model."
        case .languageAllocationLimit:
            "This device has reached Apple’s active language-model limit."
        case .invalidAudioFile:
            "The saved recording is missing or invalid."
        case .audioConversionFailed:
            "The saved recording could not be prepared for transcription."
        case .liveAnalyzerFailed:
            "Live transcription stopped. Previously finalized text is still available."
        case .offlineAnalyzerFailed:
            "Final processing failed. Aligna kept the live transcript and recording."
        case .cancelled:
            "Transcription was cancelled."
        case .transcriptPersistenceFailed:
            "The transcript could not be saved locally."
        }
    }
}

struct MeetingCaptureDependencies {
    let audio: any AudioRecording
    let speech: any SpeechTranscribing
    let finalTranscription: any FinalTranscriptionServicing
    let capabilities: any TranscriptionCapabilityProviding
    let glossaryBuilder: any TranscriptionGlossaryBuilding
    let transcripts: any TranscriptRepository
    let liveActivity: any MeetingRecordingLiveActivityControlling
    let processing: any MeetingProcessingServicing
    let currentUser: TeamMember?

    init(
        audio: any AudioRecording,
        speech: any SpeechTranscribing,
        finalTranscription: any FinalTranscriptionServicing =
            MockFinalTranscriptionService(),
        capabilities: any TranscriptionCapabilityProviding =
            MockTranscriptionCapabilityProvider(),
        glossaryBuilder: any TranscriptionGlossaryBuilding =
            DefaultTranscriptionGlossaryBuilder(),
        transcripts: any TranscriptRepository =
            InMemoryTranscriptRepository(),
        liveActivity: any MeetingRecordingLiveActivityControlling =
            NoopMeetingRecordingLiveActivityController(),
        processing: any MeetingProcessingServicing =
            MockMeetingProcessingService(),
        currentUser: TeamMember? = nil
    ) {
        self.audio = audio
        self.speech = speech
        self.finalTranscription = finalTranscription
        self.capabilities = capabilities
        self.glossaryBuilder = glossaryBuilder
        self.transcripts = transcripts
        self.liveActivity = liveActivity
        self.processing = processing
        self.currentUser = currentUser
    }

    @MainActor
    static func app(
        ownerUserID: UUID? = nil,
        processing: (any MeetingProcessingServicing)? = nil,
        currentUser: TeamMember? = nil
    ) -> MeetingCaptureDependencies {
        #if targetEnvironment(simulator)
        return MeetingCaptureDependencies(
            audio: MockAudioRecordingService(),
            speech: MockSpeechTranscriptionService(),
            finalTranscription: MockFinalTranscriptionService(),
            capabilities: AppleSpeechCapabilityProvider(),
            transcripts: LocalTranscriptRepository(
                ownerUserID: ownerUserID
            ),
            liveActivity: MeetingRecordingLiveActivityController(),
            processing: processing ?? MockMeetingProcessingService(),
            currentUser: currentUser
        )
        #else
        return MeetingCaptureDependencies(
            audio: AudioRecordingService(),
            speech: MockSpeechTranscriptionService(),
            finalTranscription: MockFinalTranscriptionService(),
            capabilities: MockTranscriptionCapabilityProvider(),
            transcripts: LocalTranscriptRepository(
                ownerUserID: ownerUserID
            ),
            liveActivity: MeetingRecordingLiveActivityController(),
            processing: processing ?? MockMeetingProcessingService(),
            currentUser: currentUser
        )
        #endif
    }

    @MainActor
    static func preview() -> MeetingCaptureDependencies {
        MeetingCaptureDependencies(
            audio: MockAudioRecordingService(),
            speech: MockSpeechTranscriptionService(),
            finalTranscription: MockFinalTranscriptionService(),
            capabilities: MockTranscriptionCapabilityProvider(),
            transcripts: InMemoryTranscriptRepository(),
            liveActivity: NoopMeetingRecordingLiveActivityController(),
            processing: MockMeetingProcessingService()
        )
    }
}
