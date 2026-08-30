import Foundation
import OSLog
import Supabase

nonisolated struct MeetingProcessingSnapshot: Hashable, Sendable {
    let status: MeetingProcessingStatus
    let title: String
    let analysis: MeetingAnalysis?
    let transcript: [TranscriptSegment]
    let attributedTranscript: [AttributedTranscriptTurn]
    let speakerAttribution: SpeakerAttributionState

    init(
        status: MeetingProcessingStatus,
        title: String,
        analysis: MeetingAnalysis?,
        transcript: [TranscriptSegment],
        attributedTranscript: [AttributedTranscriptTurn] = [],
        speakerAttribution: SpeakerAttributionState = .pending
    ) {
        self.status = status
        self.title = title
        self.analysis = analysis
        self.transcript = transcript
        self.attributedTranscript = attributedTranscript
        self.speakerAttribution = speakerAttribution
    }
}

nonisolated protocol MeetingProcessingServicing: Sendable {
    func enqueue(meeting: Meeting, audioURL: URL) async throws
    func resume(meeting: Meeting, audioURL: URL) async
    func snapshot(meetingID: UUID) async throws -> MeetingProcessingSnapshot
    func updates(
        meetingID: UUID
    ) async -> AsyncStream<MeetingProcessingSnapshot>
    func correctSpeaker(
        meetingID: UUID,
        stableSpeakerKey: String,
        participantUserID: UUID
    ) async throws
}

nonisolated extension MeetingProcessingServicing {
    func resume(meeting _: Meeting, audioURL _: URL) async {}

    func correctSpeaker(
        meetingID _: UUID,
        stableSpeakerKey _: String,
        participantUserID _: UUID
    ) async throws {}
}

actor SupabaseMeetingProcessingService: MeetingProcessingServicing {
    private let client: SupabaseClient
    private let audioPreparation: any AudioPreparing
    private let voiceEngine: any VoiceProcessing
    private let voiceProfiles: any VoiceProfileServicing
    private let attributionResolver: SpeakerAttributionResolver
    private var speakerTasks: [UUID: Task<Void, Never>] = [:]

    init(
        provider: SupabaseClientProvider,
        audioPreparation: any AudioPreparing = AudioPreparationService(),
        voiceEngine: any VoiceProcessing = MockVoiceEngine(),
        voiceProfiles: any VoiceProfileServicing = MockVoiceProfileService(),
        speakerMatcher: any SpeakerMatching = SpeakerMatcher(),
        transcriptReconciler: any TranscriptReconciling =
            TranscriptReconciliationService()
    ) {
        client = provider.client
        self.audioPreparation = audioPreparation
        self.voiceEngine = voiceEngine
        self.voiceProfiles = voiceProfiles
        attributionResolver = SpeakerAttributionResolver(
            matcher: speakerMatcher,
            reconciler: transcriptReconciler
        )
    }

    func enqueue(meeting: Meeting, audioURL: URL) async throws {
        guard let ownerID = meeting.organizerUserID ?? meeting.ownerUserID,
              let workspaceID = meeting.workspaceID
        else {
            throw MeetingProcessingServiceError.missingOwnership
        }

        let endedAt = meeting.durationSeconds.map {
            meeting.scheduledAt.addingTimeInterval($0)
        }
        do {
            try await client
                .from("meetings")
                .upsert(
                    MeetingProcessingSeedDTO(
                        id: meeting.id,
                        workspaceID: workspaceID,
                        organizerID: ownerID,
                        title: meeting.title,
                        startedAt: meeting.scheduledAt,
                        endedAt: endedAt,
                        status: "completed",
                        processingStatus:
                            MeetingProcessingStatus.uploading.rawValue
                    )
                )
                .execute()
        } catch {
            throw MeetingProcessingServiceError.normalized(error)
        }

        let chunks: [PreparedAudioChunk]
        do {
            chunks = try await audioPreparation.prepare(
                recordingURL: audioURL,
                meetingID: meeting.id
            )
        } catch {
            throw MeetingProcessingServiceError.recordingUnavailable
        }
        var manifest: [MeetingAudioChunkDTO] = []

        for (index, chunk) in chunks.enumerated() {
            let path = [
                ownerID.uuidString.lowercased(),
                meeting.id.uuidString.lowercased(),
                "chunk-\(index).m4a",
            ].joined(separator: "/")

            do {
                try await client.storage
                    .from("meeting-processing-audio")
                    .upload(
                        path,
                        fileURL: chunk.fileURL,
                        options: FileOptions(
                            cacheControl: "0",
                            contentType: "audio/mp4",
                            upsert: true
                        )
                    )
            } catch {
                let normalized = MeetingProcessingServiceError.normalized(
                    error
                )
                if normalized == .serviceUnavailable {
                    throw MeetingProcessingServiceError.uploadFailed
                }
                throw normalized
            }

            manifest.append(
                MeetingAudioChunkDTO(
                    path: path,
                    startSeconds: chunk.startSeconds,
                    endSeconds: chunk.endSeconds
                )
            )
        }

        do {
            try await client
                .from("meetings")
                .update(
                    MeetingProcessingUploadDTO(
                        processingStatus:
                            MeetingProcessingStatus.queued.rawValue,
                        audioChunks: manifest
                    )
                )
                .eq("id", value: meeting.id)
                .execute()
        } catch {
            throw MeetingProcessingServiceError.normalized(error)
        }

        do {
            let _: ProcessMeetingResponse = try await client.functions.invoke(
                "process-meeting",
                options: FunctionInvokeOptions(
                    body: ProcessMeetingRequestDTO(
                        meetingID: meeting.id,
                        idempotencyKey: meeting.id,
                        action: .transcribe
                    )
                )
            )
        } catch {
            #if DEBUG
            print(
                "Meeting processing enqueue failed:",
                String(describing: error)
            )
            #endif
            throw MeetingProcessingServiceError.normalized(error)
        }

        beginSpeakerPipeline(meeting: meeting, audioURL: audioURL)
    }

    func resume(meeting: Meeting, audioURL: URL) async {
        beginSpeakerPipeline(meeting: meeting, audioURL: audioURL)
    }

    func snapshot(
        meetingID: UUID
    ) async throws -> MeetingProcessingSnapshot {
        let row: MeetingProcessingResultDTO = try await client
            .from("meetings")
            .select(
                """
                title, processing_status, generated_title, summary,
                key_points, decisions, action_items, open_questions,
                follow_ups, languages_detected, transcript_segments,
                speaker_processing_status, speaker_processing_skipped
                """
            )
            .eq("id", value: meetingID)
            .single()
            .execute()
            .value
        let turns: [AttributedTranscriptTurnDTO]
        do {
            turns = try await client
                .from("meeting_transcript_turns")
                .select(
                    """
                    id, stable_speaker_key, speaker_user_id,
                    speaker_display_name, start_seconds, end_seconds, text,
                    attribution_confidence, attribution_source
                    """
                )
                .eq("meeting_id", value: meetingID)
                .order("start_seconds", ascending: true)
                .execute()
                .value
        } catch {
            turns = []
        }
        return row.domain(attributedTranscript: turns.map(\.domain))
    }

    func updates(
        meetingID: UUID
    ) async -> AsyncStream<MeetingProcessingSnapshot> {
        let client = self.client
        return AsyncStream { continuation in
            let task = Task {
                let channel = client.channel(
                    "meeting-processing-\(meetingID.uuidString.lowercased())"
                )
                let changes = channel.postgresChange(
                    UpdateAction.self,
                    schema: "public",
                    table: "meetings",
                    filter: .eq("id", value: meetingID.uuidString.lowercased())
                )

                do {
                    try await channel.subscribeWithError()
                    if let initial = try? await self.snapshot(
                        meetingID: meetingID
                    ) {
                        continuation.yield(initial)
                    }

                    for await _ in changes {
                        guard !Task.isCancelled else { break }
                        if let next = try? await self.snapshot(
                            meetingID: meetingID
                        ) {
                            continuation.yield(next)
                            if !next.status.isProcessing {
                                break
                            }
                        }
                    }
                } catch {
                    if let fallback = try? await self.snapshot(
                        meetingID: meetingID
                    ) {
                        continuation.yield(fallback)
                    }
                }

                await client.removeChannel(channel)
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func correctSpeaker(
        meetingID: UUID,
        stableSpeakerKey: String,
        participantUserID: UUID
    ) async throws {
        do {
            try await client.rpc(
                "correct_meeting_speaker",
                params: SpeakerCorrectionDTO(
                    meetingID: meetingID,
                    stableSpeakerKey: stableSpeakerKey,
                    participantUserID: participantUserID
                )
            ).execute()
        } catch {
            throw MeetingProcessingServiceError.normalized(error)
        }
    }

    private func beginSpeakerPipeline(
        meeting: Meeting,
        audioURL: URL
    ) {
        guard speakerTasks[meeting.id] == nil else { return }
        speakerTasks[meeting.id] = Task { [weak self] in
            guard let self else { return }
            await self.runSpeakerPipeline(
                meeting: meeting,
                audioURL: audioURL
            )
            await self.clearSpeakerTask(meetingID: meeting.id)
        }
    }

    private func clearSpeakerTask(meetingID: UUID) {
        speakerTasks[meetingID] = nil
    }

    private func runSpeakerPipeline(
        meeting: Meeting,
        audioURL: URL
    ) async {
        let diarizationTask = Task {
            try await voiceEngine.diarize(audioURL: audioURL)
        }

        do {
            let words = try await waitForTranscriptWords(
                meetingID: meeting.id
            )
            guard !words.isEmpty else {
                throw VoiceRecognitionError.noSpeech
            }

            let meetingID = meeting.id
            let voiceProfiles = self.voiceProfiles
            let outcome = await attributionResolver.resolve(
                words: words,
                diarize: { try await diarizationTask.value },
                candidates: {
                    // Explicit handling: a fetch failure and a successful fetch
                    // returning zero candidates are different facts and must not
                    // collapse into the same empty array silently.
                    SpeakerAttributionDiagnostics
                        .logCandidateFetchStarted()
                    do {
                        let loaded = try await voiceProfiles.candidates(
                            meetingID: meetingID
                        )
                        SpeakerAttributionDiagnostics
                            .logCandidateFetchSucceeded(count: loaded.count)
                        return loaded
                    } catch {
                        SpeakerAttributionDiagnostics
                            .logCandidateFetchFailed(
                                error: error,
                                category: Self.candidateFailureCategory(
                                    for: error
                                ),
                                httpStatus: Self.candidateHTTPStatus(
                                    for: error
                                )
                            )
                        return []
                    }
                },
                report: { [weak self] status in
                    try await self?.setSpeakerStatus(
                        meetingID: meetingID,
                        status: status
                    )
                }
            )

            if outcome.state != .attributed {
                diarizationTask.cancel()
            }
            SpeakerAttributionDiagnostics.logOutcome(
                meetingID: meeting.id,
                outcome: outcome
            )

            guard !outcome.turns.isEmpty else {
                throw VoiceRecognitionError.noSpeech
            }
            // Status reporting is best-effort: an Edge Function hiccup here must
            // not discard diarization results that already succeeded.
            try? await setSpeakerStatus(
                meetingID: meeting.id,
                status: .mergingTranscript
            )
            try await saveSpeakerAttribution(
                meetingID: meeting.id,
                outcome: outcome
            )
            try await requestAnalysis(meetingID: meeting.id)
        } catch {
            diarizationTask.cancel()
            try? await setSpeakerStatus(
                meetingID: meeting.id,
                status: .failed
            )
            SpeakerAttributionDiagnostics.logFailure(
                meetingID: meeting.id,
                stage: "speaker_pipeline",
                error: error
            )
        }
    }

    private func waitForTranscriptWords(
        meetingID: UUID
    ) async throws -> [WhisperWord] {
        let deadline = Date().addingTimeInterval(30 * 60)
        while !Task.isCancelled, Date() < deadline {
            let row: SpeakerPrerequisiteDTO = try await client
                .from("meetings")
                .select("processing_status, transcript_words")
                .eq("id", value: meetingID)
                .single()
                .execute()
                .value
            switch row.processingStatus {
            case .mergingTranscript, .analyzing, .complete:
                return row.transcriptWords.map(\.domain)
            case .failed:
                throw MeetingProcessingServiceError.serviceUnavailable
            default:
                try await Task.sleep(for: .seconds(2))
            }
        }
        throw MeetingProcessingServiceError.serviceUnavailable
    }

    private func setSpeakerStatus(
        meetingID: UUID,
        status: MeetingProcessingStatus
    ) async throws {
        let _: SpeakerAttributionResponse = try await client.functions.invoke(
            "speaker-attribution",
            options: FunctionInvokeOptions(
                body: SpeakerAttributionRequestDTO(
                    meetingID: meetingID,
                    modelVersion: nil,
                    skipped: nil,
                    speakerState: nil,
                    failureReason: nil,
                    status: status.rawValue,
                    intervals: nil,
                    turns: nil
                )
            )
        )
    }

    private func saveSpeakerAttribution(
        meetingID: UUID,
        outcome: SpeakerAttributionOutcome
    ) async throws {
        let attributed = outcome.state.identifiesSpeakers
        let _: SpeakerAttributionResponse = try await client.functions.invoke(
            "speaker-attribution",
            options: FunctionInvokeOptions(
                body: SpeakerAttributionRequestDTO(
                    meetingID: meetingID,
                    modelVersion: attributed
                        ? VoiceModelDescriptor.fluidAudioOfflineV1
                            .modelVersion
                        : nil,
                    skipped: !attributed,
                    speakerState: outcome.state.rawValue,
                    failureReason: outcome.failureReason,
                    status: nil,
                    intervals: outcome.intervals.map(
                        SpeakerAttributionIntervalDTO.init
                    ),
                    turns: outcome.turns.map(SpeakerAttributionTurnDTO.init)
                )
            )
        )
    }

    /// Safe category for a candidate-fetch failure. Mirrors the cases
    /// `FunctionsError` exposes, without touching response bodies.
    nonisolated private static func candidateFailureCategory(
        for error: Error
    ) -> String {
        if let voiceError = error as? VoiceRecognitionError {
            return "voice_\(voiceError.diagnosticCode)"
        }
        if let functionsError = error as? FunctionsError {
            return switch functionsError {
            case .relayError: "relay_error"
            case .httpError: "http_error"
            }
        }
        if let urlError = error as? URLError {
            return "url_\(urlError.code.rawValue)"
        }
        if error is CancellationError {
            return "cancelled"
        }
        return "unknown"
    }

    nonisolated private static func candidateHTTPStatus(
        for error: Error
    ) -> Int? {
        guard let functionsError = error as? FunctionsError else {
            return nil
        }
        return switch functionsError {
        case .relayError: nil
        case let .httpError(code, _): code
        }
    }

    private func requestAnalysis(meetingID: UUID) async throws {
        let _: ProcessMeetingResponse = try await client.functions.invoke(
            "process-meeting",
            options: FunctionInvokeOptions(
                body: ProcessMeetingRequestDTO(
                    meetingID: meetingID,
                    idempotencyKey: meetingID,
                    action: .analyze
                )
            )
        )
    }
}

actor MockMeetingProcessingService: MeetingProcessingServicing {
    private var snapshots: [UUID: MeetingProcessingSnapshot] = [:]

    func enqueue(meeting: Meeting, audioURL _: URL) async throws {
        snapshots[meeting.id] = MeetingProcessingSnapshot(
            status: .analyzing,
            title: meeting.title,
            analysis: nil,
            transcript: []
        )
    }

    func snapshot(
        meetingID: UUID
    ) async throws -> MeetingProcessingSnapshot {
        snapshots[meetingID] ?? MeetingProcessingSnapshot(
            status: .queued,
            title: "Meeting",
            analysis: nil,
            transcript: []
        )
    }

    func updates(
        meetingID: UUID
    ) async -> AsyncStream<MeetingProcessingSnapshot> {
        let value = try? await snapshot(meetingID: meetingID)
        return AsyncStream { continuation in
            if let value {
                continuation.yield(value)
            }
            continuation.finish()
        }
    }
}

nonisolated enum MeetingProcessingServiceError:
    LocalizedError,
    Equatable,
    Sendable {
    case missingOwnership
    case offline
    case serviceUnavailable
    case signInRequired
    case recordingUnavailable
    case uploadFailed

    var errorDescription: String? {
        issue.message
    }

    var issue: MeetingProcessingIssue {
        switch self {
        case .missingOwnership, .signInRequired:
            .signInRequired
        case .offline:
            .offline
        case .serviceUnavailable:
            .serviceUnavailable
        case .recordingUnavailable:
            .recordingUnavailable
        case .uploadFailed:
            .uploadFailed
        }
    }

    var shouldRemainQueued: Bool {
        self == .offline
    }

    static func normalized(_ error: Error) -> Self {
        if let processingError = error as? Self {
            return processingError
        }
        if isOffline(error) {
            return .offline
        }
        if let functionsError = error as? FunctionsError {
            switch functionsError {
            case .relayError:
                return .serviceUnavailable
            case let .httpError(code, _):
                if code == 401 || code == 403 {
                    return .signInRequired
                }
                return .serviceUnavailable
            }
        }
        if let storageError = error as? StorageError {
            if storageError.statusCode == "401"
                || storageError.statusCode == "403" {
                return .signInRequired
            }
            if storageError.statusCode == "404" {
                return .serviceUnavailable
            }
            return .uploadFailed
        }
        return .serviceUnavailable
    }

    private static func isOffline(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let offlineCodes: Set<Int> = [
                URLError.notConnectedToInternet.rawValue,
                URLError.networkConnectionLost.rawValue,
                URLError.cannotConnectToHost.rawValue,
                URLError.cannotFindHost.rawValue,
                URLError.dnsLookupFailed.rawValue,
                URLError.timedOut.rawValue,
            ]
            if offlineCodes.contains(nsError.code) {
                return true
            }
        }
        if let underlying = nsError.userInfo[
            NSUnderlyingErrorKey
        ] as? Error {
            return isOffline(underlying)
        }
        return false
    }
}

nonisolated private struct MeetingProcessingSeedDTO: Encodable, Sendable {
    let id: UUID
    let workspaceID: UUID
    let organizerID: UUID
    let title: String
    let startedAt: Date
    let endedAt: Date?
    let status: String
    let processingStatus: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case organizerID = "organizer_id"
        case title
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case status
        case processingStatus = "processing_status"
    }
}

nonisolated private struct MeetingAudioChunkDTO: Codable, Sendable {
    let path: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval

    enum CodingKeys: String, CodingKey {
        case path
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
    }
}

nonisolated private struct MeetingProcessingUploadDTO: Encodable, Sendable {
    let processingStatus: String
    let audioChunks: [MeetingAudioChunkDTO]

    enum CodingKeys: String, CodingKey {
        case processingStatus = "processing_status"
        case audioChunks = "audio_chunks"
    }
}

nonisolated private struct ProcessMeetingRequestDTO: Encodable, Sendable {
    let meetingID: UUID
    let idempotencyKey: UUID
    let action: ProcessMeetingAction

    enum CodingKeys: String, CodingKey {
        case meetingID = "meeting_id"
        case idempotencyKey = "idempotency_key"
        case action
    }
}

nonisolated private enum ProcessMeetingAction: String, Encodable, Sendable {
    case transcribe
    case analyze
}

nonisolated private struct ProcessMeetingResponse: Decodable, Sendable {
    let accepted: Bool
    let status: String
}

nonisolated private struct MeetingProcessingResultDTO: Decodable, Sendable {
    let title: String
    let processingStatus: MeetingProcessingStatus
    let generatedTitle: String?
    let summary: String?
    let keyPoints: [MeetingInsight]
    let decisions: [MeetingInsight]
    let actionItems: [MeetingActionItem]
    let openQuestions: [MeetingInsight]
    let followUps: [MeetingInsight]
    let languagesDetected: [String]
    let transcriptSegments: [CloudTranscriptSegmentDTO]
    let speakerProcessingStatus: String?
    let speakerProcessingSkipped: Bool?

    enum CodingKeys: String, CodingKey {
        case title
        case processingStatus = "processing_status"
        case generatedTitle = "generated_title"
        case summary
        case keyPoints = "key_points"
        case decisions
        case actionItems = "action_items"
        case openQuestions = "open_questions"
        case followUps = "follow_ups"
        case languagesDetected = "languages_detected"
        case transcriptSegments = "transcript_segments"
        case speakerProcessingStatus = "speaker_processing_status"
        case speakerProcessingSkipped = "speaker_processing_skipped"
    }

    func domain(
        attributedTranscript: [AttributedTranscriptTurn]
    ) -> MeetingProcessingSnapshot {
        let analysis = generatedTitle.flatMap { generatedTitle in
            summary.map {
                MeetingAnalysis(
                    generatedTitle: generatedTitle,
                    summary: $0,
                    keyPoints: keyPoints,
                    decisions: decisions,
                    actionItems: actionItems,
                    openQuestions: openQuestions,
                    followUps: followUps,
                    languagesDetected: languagesDetected
                )
            }
        }
        return MeetingProcessingSnapshot(
            status: processingStatus,
            title: generatedTitle ?? title,
            analysis: analysis,
            transcript: transcriptSegments.map(\.domain),
            attributedTranscript: attributedTranscript,
            speakerAttribution: .fromProcessingStatus(
                speakerProcessingStatus,
                skipped: speakerProcessingSkipped ?? false
            )
        )
    }
}

nonisolated private struct CloudTranscriptSegmentDTO: Decodable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String

    var domain: TranscriptSegment {
        TranscriptSegment(
            text: text,
            startTime: start,
            endTime: end,
            isFinal: true,
            speaker: nil
        )
    }
}

nonisolated private struct CloudTranscriptWordDTO: Decodable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let word: String

    var domain: WhisperWord {
        WhisperWord(
            text: word,
            startSeconds: start,
            endSeconds: end
        )
    }
}

nonisolated private struct SpeakerPrerequisiteDTO: Decodable, Sendable {
    let processingStatus: MeetingProcessingStatus
    let transcriptWords: [CloudTranscriptWordDTO]

    enum CodingKeys: String, CodingKey {
        case processingStatus = "processing_status"
        case transcriptWords = "transcript_words"
    }
}

nonisolated private struct SpeakerAttributionRequestDTO:
    Encodable,
    Sendable {
    let meetingID: UUID
    let modelVersion: String?
    let skipped: Bool?
    let speakerState: String?
    let failureReason: String?
    let status: String?
    let intervals: [SpeakerAttributionIntervalDTO]?
    let turns: [SpeakerAttributionTurnDTO]?

    enum CodingKeys: String, CodingKey {
        case meetingID = "meeting_id"
        case modelVersion = "model_version"
        case skipped
        case speakerState = "speaker_state"
        case failureReason = "failure_reason"
        case status
        case intervals
        case turns
    }
}

nonisolated private struct SpeakerAttributionIntervalDTO:
    Encodable,
    Sendable {
    let stableSpeakerKey: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval

    init(_ interval: DiarizationInterval) {
        stableSpeakerKey = interval.stableSpeakerKey
        startSeconds = interval.startSeconds
        endSeconds = interval.endSeconds
    }

    enum CodingKeys: String, CodingKey {
        case stableSpeakerKey = "stable_speaker_key"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
    }
}

nonisolated private struct SpeakerAttributionTurnDTO:
    Encodable,
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

    init(_ turn: AttributedTranscriptTurn) {
        id = turn.id
        stableSpeakerKey = turn.stableSpeakerKey
        speakerUserID = turn.speakerUserID
        speakerDisplayName = turn.speakerDisplayName
        startSeconds = turn.startSeconds
        endSeconds = turn.endSeconds
        text = turn.text
        attributionConfidence = turn.attributionConfidence
        attributionSource = turn.attributionSource
    }

    enum CodingKeys: String, CodingKey {
        case id
        case stableSpeakerKey = "stable_speaker_key"
        case speakerUserID = "speaker_user_id"
        case speakerDisplayName = "speaker_display_name"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
        case text
        case attributionConfidence = "attribution_confidence"
        case attributionSource = "attribution_source"
    }
}

nonisolated private struct SpeakerAttributionResponse:
    Decodable,
    Sendable {
    let success: Bool
}

nonisolated private struct AttributedTranscriptTurnDTO:
    Decodable,
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

    enum CodingKeys: String, CodingKey {
        case id
        case stableSpeakerKey = "stable_speaker_key"
        case speakerUserID = "speaker_user_id"
        case speakerDisplayName = "speaker_display_name"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
        case text
        case attributionConfidence = "attribution_confidence"
        case attributionSource = "attribution_source"
    }

    var domain: AttributedTranscriptTurn {
        AttributedTranscriptTurn(
            id: id,
            stableSpeakerKey: stableSpeakerKey,
            speakerUserID: speakerUserID,
            speakerDisplayName: speakerDisplayName,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            text: text,
            attributionConfidence: attributionConfidence,
            attributionSource: attributionSource
        )
    }
}

nonisolated private struct SpeakerCorrectionDTO: Encodable, Sendable {
    let meetingID: UUID
    let stableSpeakerKey: String
    let participantUserID: UUID

    enum CodingKeys: String, CodingKey {
        case meetingID = "p_meeting_id"
        case stableSpeakerKey = "p_stable_speaker_key"
        case participantUserID = "p_speaker_user_id"
    }
}
