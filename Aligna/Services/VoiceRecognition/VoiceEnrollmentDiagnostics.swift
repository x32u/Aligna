import Foundation
import OSLog

/// Machine-readable reason an enrollment sample or attempt was rejected.
///
/// The three previously indistinguishable "not enough speech" paths each get
/// their own code so a log line answers *why* a specific enrollment failed:
///
/// - `fluidAudioNoSpeechDetected` — FluidAudio's pipeline produced no embeddings
///   at all (its own `noSpeechDetected`).
/// - `diarizerSpeakerCountUnexpected` — FluidAudio returned a speaker database
///   whose count was not exactly 1.
/// - `analyzerInsufficientSpeech` — Aligna's own RMS analyzer measured too
///   little voiced audio.
nonisolated enum VoiceEnrollmentReason: String, Hashable, Sendable {
    case fluidAudioNoSpeechDetected = "fluidaudio_no_speech_detected"
    case diarizerSpeakerCountUnexpected = "diarizer_speaker_count_unexpected"
    case diarizerEmptyClusters = "diarizer_empty_clusters"
    case analyzerInsufficientSpeech = "analyzer_insufficient_speech"
    case analyzerTooQuiet = "analyzer_too_quiet"
    case analyzerClipped = "analyzer_clipped"
    case analyzerNoisy = "analyzer_noisy"
    case analyzerMultipleSpeakers = "analyzer_multiple_speakers"
    case analyzerInterrupted = "analyzer_interrupted"
    /// The recorder read zero frames back from the file it had just written.
    case recordedBufferEmpty = "recorded_buffer_empty"
    /// The engine was handed an empty sample array.
    case emptySampleArray = "empty_sample_array"
    case audioInterrupted = "audio_interrupted"
    case routeChanged = "route_changed"
    case mediaServicesReset = "media_services_reset"
    case recordingFailed = "recording_failed"
    case permissionDenied = "permission_denied"
    case modelUnavailable = "model_unavailable"
    case embeddingInvalid = "embedding_invalid"
    case aggregationFailed = "aggregation_failed"
    case storageFailed = "storage_failed"
    case unauthorized = "unauthorized"
    case offline = "offline"
    case cancelled
    case unknown

    /// Maps a thrown error onto a diagnostic reason without losing specificity.
    static func from(_ error: Error) -> VoiceEnrollmentReason {
        if let issue = error as? EnrollmentSampleIssue {
            return switch issue {
            case .insufficientSpeech: .analyzerInsufficientSpeech
            case .tooQuiet: .analyzerTooQuiet
            case .clipped: .analyzerClipped
            case .noisy: .analyzerNoisy
            case .multipleSpeakers: .analyzerMultipleSpeakers
            case .interrupted: .analyzerInterrupted
            }
        }
        if let voiceError = error as? VoiceRecognitionError {
            return switch voiceError {
            case .modelUnavailable: .modelUnavailable
            case .noSpeech: .fluidAudioNoSpeechDetected
            case .multipleSpeakers: .diarizerSpeakerCountUnexpected
            case .incompatibleModel: .embeddingInvalid
            case .invalidEmbedding: .embeddingInvalid
            case .unauthorized: .unauthorized
            case .configurationMissing: .storageFailed
            case .offline: .offline
            case .interrupted: .audioInterrupted
            }
        }
        if error is CancellationError {
            return .cancelled
        }
        return .unknown
    }
}

/// Structured diagnostics for the Recognize My Voice pipeline.
///
/// Every value logged here is either a state name, a duration, a count, or a
/// reason code. Audio samples, transcript text, display names, and identifiers
/// that could identify a person are deliberately excluded; the user ID is
/// logged `.private` so it is redacted outside Xcode.
nonisolated enum VoiceEnrollmentDiagnostics {
    private static let logger = Logger(
        subsystem: "dev.notjc.Aligna",
        category: "VoiceEnrollment"
    )

    static func logStageChange(from old: String, to new: String) {
        logger.info(
            """
            Enrollment stage. from=\(old, privacy: .public) \
            to=\(new, privacy: .public)
            """
        )
    }

    static func logRecordingStarted(promptIndex: Int, promptCount: Int) {
        logger.info(
            """
            Enrollment recording started. \
            prompt=\(promptIndex + 1, privacy: .public)/\
            \(promptCount, privacy: .public)
            """
        )
    }

    static func logSpeechOnset(atSeconds seconds: TimeInterval) {
        logger.info(
            "Enrollment speech onset. at=\(rounded(seconds), privacy: .public)s"
        )
    }

    static func logSpeechEnd(
        atSeconds seconds: TimeInterval,
        voicedSeconds: TimeInterval
    ) {
        logger.info(
            """
            Enrollment speech end. at=\(rounded(seconds), privacy: .public)s \
            voiced=\(rounded(voicedSeconds), privacy: .public)s
            """
        )
    }

    static func logRecordingStopped(
        totalSeconds: TimeInterval,
        trigger: String
    ) {
        logger.info(
            """
            Enrollment recording stopped. \
            total=\(rounded(totalSeconds), privacy: .public)s \
            trigger=\(trigger, privacy: .public)
            """
        )
    }

    static func logAnalyzerResult(_ quality: EnrollmentSampleQuality) {
        logger.info(
            """
            Enrollment analyzer. \
            duration=\(rounded(quality.durationSeconds), privacy: .public)s \
            voiced=\(rounded(quality.voicedSeconds), privacy: .public)s \
            rms=\(rounded(Double(quality.rootMeanSquare), places: 4), privacy: .public) \
            peak=\(rounded(Double(quality.peakAmplitude), places: 4), privacy: .public) \
            accepted=\(quality.isAccepted, privacy: .public) \
            issue=\(quality.issue?.rawValue ?? "none", privacy: .public)
            """
        )
    }

    /// What actually landed on disk for this utterance, independent of what the
    /// recorder claimed. Answers "did Aligna record the complete phrase?".
    static func logRecordedFile(
        frameCount: Int,
        sampleRate: Double,
        recorderReportedSeconds: TimeInterval
    ) {
        let fileSeconds = sampleRate > 0
            ? Double(frameCount) / sampleRate
            : 0
        logger.info(
            """
            Enrollment recorded file. \
            frames=\(frameCount, privacy: .public) \
            sampleRate=\(Int(sampleRate), privacy: .public) \
            fileSeconds=\(rounded(fileSeconds), privacy: .public) \
            recorderSeconds=\(rounded(recorderReportedSeconds), privacy: .public)
            """
        )
    }

    static func logModelReadiness(prepared: Bool, reason: String) {
        logger.info(
            """
            Enrollment model readiness. \
            prepared=\(prepared, privacy: .public) \
            detail=\(reason, privacy: .public)
            """
        )
    }

    /// Records what FluidAudio actually returned for an enrollment utterance.
    /// This is the line that distinguishes the competing "not enough speech"
    /// explanations from each other.
    static func logDiarizerOutput(
        sampleCount: Int,
        sampleRate: Double,
        segmentCount: Int,
        speakerDatabaseCount: Int,
        embeddingDimension: Int?
    ) {
        logger.info(
            """
            Enrollment diarizer output. \
            samples=\(sampleCount, privacy: .public) \
            seconds=\(rounded(Double(sampleCount) / sampleRate), privacy: .public) \
            segments=\(segmentCount, privacy: .public) \
            speakers=\(speakerDatabaseCount, privacy: .public) \
            dimension=\(embeddingDimension ?? -1, privacy: .public)
            """
        )
    }

    /// Per-segment diarizer output. Cluster IDs (`S1`, `S2`) are internal
    /// identifiers, not user-facing names, so they are safe to log. DEBUG only:
    /// a long utterance can produce many segments.
    static func logDiarizerSegments(
        _ segments: [(id: String, start: TimeInterval, end: TimeInterval)]
    ) {
        logger.info(
            "Enrollment diarizer segments. count=\(segments.count, privacy: .public)"
        )
        #if DEBUG
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            print(
                String(
                    format: "  enrollment segment %.2f–%.2f → %@",
                    segment.start,
                    segment.end,
                    segment.id
                )
            )
        }
        #endif
    }

    static func logSampleAccepted(
        promptIndex: Int,
        embeddingDimension: Int,
        collectedSamples: Int
    ) {
        logger.info(
            """
            Enrollment sample accepted. \
            prompt=\(promptIndex + 1, privacy: .public) \
            dimension=\(embeddingDimension, privacy: .public) \
            collected=\(collectedSamples, privacy: .public)
            """
        )
    }

    static func logRejection(
        reason: VoiceEnrollmentReason,
        stage: String
    ) {
        logger.error(
            """
            Enrollment rejected. \
            reason=\(reason.rawValue, privacy: .public) \
            stage=\(stage, privacy: .public)
            """
        )
    }

    static func logInterruption(kind: String) {
        logger.error(
            "Enrollment interrupted. kind=\(kind, privacy: .public)"
        )
    }

    static func logAggregation(
        sampleCount: Int,
        succeeded: Bool,
        dimension: Int?
    ) {
        logger.info(
            """
            Enrollment aggregation. \
            samples=\(sampleCount, privacy: .public) \
            succeeded=\(succeeded, privacy: .public) \
            dimension=\(dimension ?? -1, privacy: .public)
            """
        )
    }

    /// Per-sample similarity to the computed centroid, plus the survivor count.
    ///
    /// This is what distinguishes "the four samples scattered past the outlier
    /// cutoff" from "storage failed". Only similarities and pass/fail flags are
    /// logged — never the embedding vectors themselves.
    static func logAggregationDetail(
        inputCount: Int,
        minimumSamples: Int,
        outlierDistance: Float,
        similarities: [Float],
        survivorCount: Int,
        succeeded: Bool,
        reason: VoiceEnrollmentReason?
    ) {
        let cutoff = 1 - outlierDistance
        let formatted = similarities
            .map { String(format: "%.4f", $0) }
            .joined(separator: ",")
        let verdicts = similarities
            .map { $0 >= cutoff ? "pass" : "fail" }
            .joined(separator: ",")
        logger.info(
            """
            Enrollment aggregation detail. \
            input=\(inputCount, privacy: .public) \
            minimumSamples=\(minimumSamples, privacy: .public) \
            cutoff=\(rounded(Double(cutoff), places: 4), privacy: .public) \
            similarities=[\(formatted, privacy: .public)] \
            verdicts=[\(verdicts, privacy: .public)] \
            survivors=\(survivorCount, privacy: .public) \
            succeeded=\(succeeded, privacy: .public) \
            reason=\(reason?.rawValue ?? "none", privacy: .public)
            """
        )
    }

    /// Storage attempt, before the network call, so an attempt with no matching
    /// result line means the call never returned.
    static func logStorageAttempt(
        embeddingDimension: Int,
        modelVersion: String
    ) {
        logger.info(
            """
            Enrollment storage attempt. \
            dimension=\(embeddingDimension, privacy: .public) \
            model=\(modelVersion, privacy: .public)
            """
        )
    }

    /// Outcome of the `voice-profiles` call, including transport category and
    /// whether the profile was associated with the expected user.
    ///
    /// Only an equality indicator is recorded — never the identifiers
    /// themselves — since the comparison result is the whole diagnostic value.
    static func logStorageResult(
        succeeded: Bool,
        reason: VoiceEnrollmentReason?,
        category: String,
        httpStatus: Int?,
        associatedWithExpectedUser: String
    ) {
        logger.info(
            """
            Enrollment storage result. \
            succeeded=\(succeeded, privacy: .public) \
            reason=\(reason?.rawValue ?? "none", privacy: .public) \
            category=\(category, privacy: .public) \
            httpStatus=\(httpStatus ?? -1, privacy: .public) \
            associatedWithExpectedUser=\(associatedWithExpectedUser, privacy: .public)
            """
        )
    }

    /// Compares two user identifiers without recording either one.
    static func userAssociation(
        expected: UUID?,
        associated: UUID?
    ) -> String {
        switch (expected, associated) {
        case let (expected?, associated?):
            expected == associated ? "yes" : "no"
        case (nil, nil):
            "unknown"
        default:
            "partial"
        }
    }

    /// Boundary marker for the post-diarizer control flow. Lets a trace show
    /// exactly which statement was last reached when nothing else is logged.
    static func logBoundary(_ marker: String) {
        logger.info(
            "Enrollment boundary. at=\(marker, privacy: .public)"
        )
    }

    /// Concrete Swift error identity, recorded before it is mapped onto a
    /// `VoiceEnrollmentReason`. `localizedDescription` on these types is
    /// developer-authored copy, not user content.
    static func logCaughtError(
        stage: String,
        error: Error
    ) {
        logger.error(
            """
            Enrollment caught error. \
            stage=\(stage, privacy: .public) \
            type=\(String(reflecting: type(of: error)), privacy: .public) \
            reason=\(VoiceEnrollmentReason.from(error).rawValue, privacy: .public) \
            description=\(error.localizedDescription, privacy: .public)
            """
        )
    }

    /// Ties an accepted sample to its position in the aggregation input, so the
    /// per-sample similarities logged later can be attributed back to a prompt.
    static func logEmbeddingProduced(
        promptIndex: Int,
        aggregationIndex: Int,
        dimension: Int
    ) {
        logger.info(
            """
            Enrollment embedding produced. \
            prompt=\(promptIndex + 1, privacy: .public) \
            aggregationIndex=\(aggregationIndex, privacy: .public) \
            dimension=\(dimension, privacy: .public)
            """
        )
    }

    /// Terminal outcome of a whole enrollment run.
    static func logEnrollmentOutcome(
        succeeded: Bool,
        reason: VoiceEnrollmentReason?,
        samplesCollected: Int,
        promptCount: Int
    ) {
        logger.info(
            """
            Enrollment finished. \
            succeeded=\(succeeded, privacy: .public) \
            reason=\(reason?.rawValue ?? "none", privacy: .public) \
            samples=\(samplesCollected, privacy: .public)/\
            \(promptCount, privacy: .public)
            """
        )
    }

    static func logStorage(
        succeeded: Bool,
        reason: VoiceEnrollmentReason?,
        userID: UUID?
    ) {
        logger.info(
            """
            Enrollment storage. \
            succeeded=\(succeeded, privacy: .public) \
            reason=\(reason?.rawValue ?? "none", privacy: .public) \
            user=\(userID?.uuidString ?? "none", privacy: .private)
            """
        )
    }

    static func logProfilePreserved(previousStatus: String) {
        logger.info(
            """
            Enrollment abandoned, previous profile preserved. \
            status=\(previousStatus, privacy: .public)
            """
        )
    }

    private static func rounded(
        _ value: Double,
        places: Int = 2
    ) -> Double {
        guard value.isFinite else { return 0 }
        let factor = pow(10.0, Double(places))
        return (value * factor).rounded() / factor
    }
}
