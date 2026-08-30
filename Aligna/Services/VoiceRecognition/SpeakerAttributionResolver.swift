import Foundation
import OSLog

/// Result of deciding what speaker attribution a meeting actually earned.
nonisolated struct SpeakerAttributionOutcome: Hashable, Sendable {
    let turns: [AttributedTranscriptTurn]
    let intervals: [DiarizationInterval]
    let state: SpeakerAttributionState
    /// Stable reason code when `state == .failed`; `nil` otherwise.
    let failureReason: String?
}

/// Decides whether diarization produced real speaker identities, and builds the
/// transcript turns to store either way.
///
/// This is deliberately a pure value type with injected work: the rule that a
/// failed diarization must never yield a synthetic speaker is the fix for the
/// "everything collapses to one speaker" bug, so it has to be directly testable
/// without a Supabase client.
nonisolated struct SpeakerAttributionResolver: Sendable {
    let matcher: any SpeakerMatching
    let reconciler: any TranscriptReconciling

    init(
        matcher: any SpeakerMatching = SpeakerMatcher(),
        reconciler: any TranscriptReconciling =
            TranscriptReconciliationService()
    ) {
        self.matcher = matcher
        self.reconciler = reconciler
    }

    /// - Parameters:
    ///   - words: Whisper word timings for the whole recording.
    ///   - diarize: Produces the on-device diarization result.
    ///   - candidates: Enrolled voice profiles eligible for this meeting.
    ///   - report: Best-effort progress reporting. Failures here are swallowed
    ///     on purpose — a status round-trip must never discard speaker work that
    ///     already succeeded.
    func resolve(
        words: [WhisperWord],
        diarize: @Sendable () async throws -> DiarizationOutput,
        candidates: @Sendable () async -> [CandidateVoiceProfile],
        report: @Sendable (MeetingProcessingStatus) async throws -> Void
    ) async -> SpeakerAttributionOutcome {
        try? await report(.diarizing)

        do {
            let diarization = try await diarize()
            try? await report(.matchingSpeakers)
            let matches = matcher.match(
                clusters: diarization.clusters,
                candidates: await candidates()
            )
            let turns = reconciler.reconcile(
                words: words,
                intervals: diarization.intervals,
                matches: matches
            )
            return SpeakerAttributionOutcome(
                turns: turns,
                intervals: diarization.intervals,
                state: .attributed,
                failureReason: nil
            )
        } catch VoiceRecognitionError.noSpeech {
            // The one benign outcome: the audio genuinely had no separable
            // speech, so there is nothing to attribute. Keep the transcript.
            return SpeakerAttributionOutcome(
                turns: unattributedTurns(from: words),
                intervals: [],
                state: .skipped,
                failureReason: nil
            )
        } catch {
            // Model unavailable, interrupted, cancelled, or unexpected.
            // Diarization did not run, so inventing a speaker identity here
            // would present a failure as a successful single-speaker meeting.
            return SpeakerAttributionOutcome(
                turns: unattributedTurns(from: words),
                intervals: [],
                state: .failed,
                failureReason: SpeakerAttributionDiagnostics
                    .failureReason(error)
            )
        }
    }

    /// Turns that carry transcript text while making no speaker claim.
    ///
    /// The single spanning interval exists only so every word finds a home in
    /// the reconciler. Its key and display name are deliberately unnumbered so
    /// they can never read as "speaker 1 of several".
    func unattributedTurns(
        from words: [WhisperWord]
    ) -> [AttributedTranscriptTurn] {
        let placeholder = SpeakerMatch(
            stableSpeakerKey: SpeakerAttributionState
                .unattributedSpeakerKey,
            state: .unknown,
            userID: nil,
            displayName: SpeakerAttributionState
                .unattributedDisplayName,
            confidence: nil
        )
        let intervals = words.first.flatMap { first in
            words.last.map { last in
                [
                    DiarizationInterval(
                        stableSpeakerKey: SpeakerAttributionState
                            .unattributedSpeakerKey,
                        startSeconds: first.startSeconds,
                        endSeconds: last.endSeconds
                    ),
                ]
            }
        } ?? []
        return reconciler.reconcile(
            words: words,
            intervals: intervals,
            matches: [placeholder]
        )
    }
}

/// Permanent diagnostics for speaker attribution.
///
/// The previous implementation recorded failures with a `print` compiled out of
/// release builds, which destroyed the only evidence of why attribution failed.
nonisolated enum SpeakerAttributionDiagnostics {
    private static let logger = Logger(
        subsystem: "dev.notjc.Aligna",
        category: "SpeakerAttribution"
    )

    private static let identityLogger = Logger(
        subsystem: "dev.notjc.Aligna",
        category: "SpeakerIdentity"
    )

    // MARK: - Identity candidate loading

    static func logCandidateFetchStarted() {
        identityLogger.info("identity candidate fetch started")
    }

    /// A successful fetch, including `count=0`. Distinct from a failure so the
    /// two can never be confused for each other.
    static func logCandidateFetchSucceeded(count: Int) {
        identityLogger.info(
            "identity candidate fetch succeeded count=\(count, privacy: .public)"
        )
    }

    static func logCandidateFetchFailed(
        error: Error,
        category: String,
        httpStatus: Int?
    ) {
        identityLogger.error(
            """
            identity candidate fetch failed \
            type=\(String(reflecting: type(of: error)), privacy: .public) \
            category=\(category, privacy: .public) \
            httpStatus=\(httpStatus ?? -1, privacy: .public)
            """
        )
    }

    /// Per-stage candidate counts through the client-side compatibility filters.
    /// Only counts and non-identifying model metadata are recorded.
    static func logCandidateRetrievalStages(
        serverReturned: Int,
        afterCompatibilityKeyFilter: Int,
        afterNormalizationFilter: Int,
        afterDimensionFilter: Int,
        finalCandidates: Int,
        expectedProvider: String,
        expectedModelVersion: String,
        expectedDimension: Int
    ) {
        identityLogger.info(
            """
            identity candidate retrieval \
            serverReturned=\(serverReturned, privacy: .public) \
            afterCompatibilityKeyFilter=\(afterCompatibilityKeyFilter, privacy: .public) \
            afterNormalizationFilter=\(afterNormalizationFilter, privacy: .public) \
            afterDimensionFilter=\(afterDimensionFilter, privacy: .public) \
            finalCandidates=\(finalCandidates, privacy: .public) \
            expectedProvider=\(expectedProvider, privacy: .public) \
            expectedModelVersion=\(expectedModelVersion, privacy: .public) \
            expectedDimension=\(expectedDimension, privacy: .public)
            """
        )
    }

    /// Records the model metadata a rejected candidate actually carried, so a
    /// compatibility mismatch names both sides. No identifiers.
    static func logCandidateRejected(
        provider: String,
        modelVersion: String,
        dimension: Int,
        reason: String
    ) {
        identityLogger.error(
            """
            identity candidate rejected \
            provider=\(provider, privacy: .public) \
            modelVersion=\(modelVersion, privacy: .public) \
            dimension=\(dimension, privacy: .public) \
            reason=\(reason, privacy: .public)
            """
        )
    }

    // MARK: - Identity matching

    static func logMatchingStarted(clusters: Int, candidates: Int) {
        identityLogger.info(
            """
            identity matching started \
            clusters=\(clusters, privacy: .public) \
            candidates=\(candidates, privacy: .public)
            """
        )
    }

    static func logMatchingSkipped(reason: String) {
        identityLogger.error(
            "identity matching skipped reason=\(reason, privacy: .public)"
        )
    }

    static func logThresholds(
        similarity: Float,
        separation: Float
    ) {
        identityLogger.info(
            """
            identity thresholds \
            similarity=\(similarity, privacy: .public) \
            separation=\(separation, privacy: .public)
            """
        )
    }

    static func logSimilarity(
        clusterIndex: Int,
        candidateIndex: Int,
        similarity: Float
    ) {
        identityLogger.info(
            """
            identity similarity \
            clusterIndex=\(clusterIndex, privacy: .public) \
            candidateIndex=\(candidateIndex, privacy: .public) \
            similarity=\(similarity, privacy: .public)
            """
        )
    }

    static func logMatchDecision(
        clusterIndex: Int,
        state: String,
        confidence: Float?
    ) {
        identityLogger.info(
            """
            identity match \
            clusterIndex=\(clusterIndex, privacy: .public) \
            state=\(state, privacy: .public) \
            confidence=\(confidence ?? -1, privacy: .public)
            """
        )
    }

    // MARK: - Transcript label resolution

    /// Whether a recognized identity actually reached the transcript, or the
    /// label fell back. Speaker keys (`S1`) are internal cluster IDs, not names.
    static func logTranscriptIdentityResolution(
        speakerKey: String,
        state: String,
        labelSource: String,
        hasUserID: Bool
    ) {
        identityLogger.info(
            """
            transcript identity resolution \
            speakerKey=\(speakerKey, privacy: .public) \
            state=\(state, privacy: .public) \
            labelSource=\(labelSource, privacy: .public) \
            hasUserID=\(hasUserID, privacy: .public)
            """
        )
    }

    /// Stable, low-cardinality reason code safe to persist. Deliberately avoids
    /// `localizedDescription` so no transcript or account detail can leak into
    /// a diagnostics record.
    static func failureReason(_ error: Error) -> String {
        if let voiceError = error as? VoiceRecognitionError {
            return "voice_\(voiceError.diagnosticCode)"
        }
        if error is CancellationError {
            return "cancelled"
        }
        if let urlError = error as? URLError {
            return "url_\(urlError.code.rawValue)"
        }
        return "unexpected"
    }

    /// Logs why speaker attribution failed. The reason code is emitted in all
    /// builds so a real-device failure is diagnosable from Console; the full
    /// error dump stays in DEBUG.
    static func logFailure(
        meetingID: UUID,
        stage: String,
        error: Error
    ) {
        logger.error(
            """
            Speaker attribution failed. stage=\(stage, privacy: .public) \
            reason=\(failureReason(error), privacy: .public) \
            meeting=\(meetingID.uuidString, privacy: .private)
            """
        )
        #if DEBUG
        print(
            "Speaker attribution failed:",
            stage,
            String(describing: error)
        )
        #endif
    }

    /// Logs the shape of the diarization result: enough to see the speaker count
    /// without persisting the whole timeline. The raw interval list is printed in
    /// DEBUG only.
    static func logOutcome(
        meetingID: UUID,
        outcome: SpeakerAttributionOutcome
    ) {
        let speakerKeys = Set(
            outcome.intervals.map(\.stableSpeakerKey)
        ).sorted()
        logger.info(
            """
            Speaker attribution finished. \
            state=\(outcome.state.rawValue, privacy: .public) \
            speakers=\(speakerKeys.count, privacy: .public) \
            intervals=\(outcome.intervals.count, privacy: .public) \
            keys=\(speakerKeys.joined(separator: ","), privacy: .public) \
            reason=\(outcome.failureReason ?? "none", privacy: .public) \
            meeting=\(meetingID.uuidString, privacy: .private)
            """
        )
        #if DEBUG
        for interval in outcome.intervals.sorted(by: {
            $0.startSeconds < $1.startSeconds
        }) {
            print(
                String(
                    format: "  raw diarization %.2f–%.2f → %@",
                    interval.startSeconds,
                    interval.endSeconds,
                    interval.stableSpeakerKey
                )
            )
        }
        #endif
    }
}
