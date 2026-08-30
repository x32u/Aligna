import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class VoiceSetupViewModel {
    enum Stage: Equatable {
        case introduction
        case preparing
        case ready
        case recording
        case evaluating
        case saving
        case completed
    }

    private(set) var stage: Stage = .introduction
    private(set) var phraseIndex = 0
    private(set) var microphoneLevel: Float = 0
    private(set) var message: String?
    private(set) var isFailure = false

    let phrases: [String]

    private let engine: any VoiceProcessing
    private let profiles: any VoiceProfileServicing
    private let recorder: VoiceEnrollmentRecorder
    private let qualityAnalyzer: EnrollmentAudioQualityAnalyzer
    private let speechLevelThreshold: Float = 0.005
    private let visualLevelGain: Float = 10
    private var embeddings: [VoiceEmbedding] = []
    private var monitoringTask: Task<Void, Never>?

    init(
        displayName: String,
        locale: Locale = .current,
        engine: any VoiceProcessing,
        profiles: any VoiceProfileServicing,
        recorder: VoiceEnrollmentRecorder? = nil,
        qualityAnalyzer: EnrollmentAudioQualityAnalyzer =
            EnrollmentAudioQualityAnalyzer()
    ) {
        self.engine = engine
        self.profiles = profiles
        self.recorder = recorder ?? VoiceEnrollmentRecorder()
        self.qualityAnalyzer = qualityAnalyzer
        phrases = Self.prompts(
            displayName: displayName,
            locale: locale
        )
    }

    var currentPhrase: String {
        phrases[min(phraseIndex, phrases.count - 1)]
    }

    var progress: Double {
        Double(phraseIndex) / Double(phrases.count)
    }

    var canCancel: Bool {
        stage != .saving && stage != .completed
    }

    func begin() async {
        guard stage == .introduction else { return }
        setStage(.preparing)
        message = "Preparing voice recognition…"
        isFailure = false
        do {
            try await profiles.updateStatus(.inProgress)
            try await engine.prepareModels()
            setStage(.ready)
            message = nil
        } catch {
            VoiceEnrollmentDiagnostics.logCaughtError(
                stage: "begin_prepare",
                error: error
            )
            setStage(.introduction)
            message = error.localizedDescription
            isFailure = true
        }
    }

    func startPhrase() async {
        guard stage == .ready else { return }
        message = nil
        isFailure = false

        guard await recorder.requestPermission() else {
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .permissionDenied,
                stage: "start_phrase_permission"
            )
            message =
                "Allow microphone access in Settings to set up voice recognition."
            isFailure = true
            return
        }

        do {
            try await recorder.start()
            VoiceEnrollmentDiagnostics.logRecordingStarted(
                promptIndex: phraseIndex,
                promptCount: phrases.count
            )
            setStage(.recording)
            monitorRecording()
        } catch {
            VoiceEnrollmentDiagnostics.logCaughtError(
                stage: "start_phrase_recorder_start",
                error: error
            )
            setStage(.ready)
            message = error.localizedDescription
            isFailure = true
        }
    }

    func retryPhrase() {
        message = nil
        isFailure = false
        setStage(.ready)
    }

    func cancelRecording() {
        monitoringTask?.cancel()
        monitoringTask = nil
        recorder.cancel()
        microphoneLevel = 0
        setStage(.ready)
        message = nil
    }

    func resetToIntroduction() {
        cancelRecording()
        setStage(.introduction)
    }

    private func monitorRecording() {
        monitoringTask?.cancel()
        monitoringTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var voicedSeconds: TimeInterval = 0
            var silenceAfterVoice: TimeInterval = 0
            var hasLoggedOnset = false

            while !Task.isCancelled, stage == .recording {
                let level = recorder.normalizedLevel
                let visualLevel = min(1, level * visualLevelGain)
                microphoneLevel =
                    (microphoneLevel * 0.65) + (visualLevel * 0.35)
                if level > speechLevelThreshold {
                    if !hasLoggedOnset {
                        hasLoggedOnset = true
                        VoiceEnrollmentDiagnostics.logSpeechOnset(
                            atSeconds: recorder.currentTime
                        )
                    }
                    voicedSeconds += 0.1
                    silenceAfterVoice = 0
                } else if voicedSeconds > 0.4 {
                    silenceAfterVoice += 0.1
                }

                if recorder.currentTime >= 7
                    || (
                        voicedSeconds >= 1
                            && silenceAfterVoice >= 0.7
                    ) {
                    VoiceEnrollmentDiagnostics.logSpeechEnd(
                        atSeconds: recorder.currentTime,
                        voicedSeconds: voicedSeconds
                    )
                    await finishPhrase()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func finishPhrase() async {
        // This method is called by monitoringTask itself. Cancelling that
        // stored task here also cancels FluidAudio's upcoming async work.
        monitoringTask = nil
        setStage(.evaluating)
        microphoneLevel = 0

        do {
            VoiceEnrollmentDiagnostics.logBoundary(
                "finish_phrase_before_stop_and_read"
            )
            let samples = try await recorder.stopAndReadSamples()
            VoiceEnrollmentDiagnostics.logBoundary(
                "finish_phrase_after_stop_and_read"
            )

            let quality = qualityAnalyzer.analyze(samples)
            VoiceEnrollmentDiagnostics.logAnalyzerResult(quality)
            if let issue = quality.issue {
                VoiceEnrollmentDiagnostics.logRejection(
                    reason: VoiceEnrollmentReason.from(issue),
                    stage: "finish_phrase_analyzer"
                )
                throw issue
            }

            VoiceEnrollmentDiagnostics.logBoundary(
                "finish_phrase_before_embedding"
            )
            let embedding = try await engine.embedding(from: samples)
            VoiceEnrollmentDiagnostics.logBoundary(
                "finish_phrase_after_embedding"
            )
            embeddings.append(embedding)
            VoiceEnrollmentDiagnostics.logEmbeddingProduced(
                promptIndex: phraseIndex,
                aggregationIndex: embeddings.count - 1,
                dimension: embedding.values.count
            )
            VoiceEnrollmentDiagnostics.logSampleAccepted(
                promptIndex: phraseIndex,
                embeddingDimension: embedding.values.count,
                collectedSamples: embeddings.count
            )

            if phraseIndex + 1 < phrases.count {
                phraseIndex += 1
                setStage(.ready)
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.success)
            } else {
                VoiceEnrollmentDiagnostics.logBoundary(
                    "finish_phrase_before_save_profile"
                )
                try await saveProfile()
                VoiceEnrollmentDiagnostics.logBoundary(
                    "finish_phrase_after_save_profile"
                )
            }
        } catch let issue as EnrollmentSampleIssue {
            VoiceEnrollmentDiagnostics.logCaughtError(
                stage: "finish_phrase_sample_issue",
                error: issue
            )
            setStage(.ready)
            message = issue.message
            isFailure = true
            UINotificationFeedbackGenerator()
                .notificationOccurred(.warning)
        } catch is CancellationError {
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .cancelled,
                stage: "finish_phrase_cancelled"
            )
            setStage(.ready)
            message = EnrollmentSampleIssue.interrupted.message
            isFailure = true
            UINotificationFeedbackGenerator()
                .notificationOccurred(.warning)
        } catch {
            // First line of the generic catch: record the concrete error before
            // anything maps or summarizes it. This path was previously silent.
            VoiceEnrollmentDiagnostics.logBoundary(
                "finish_phrase_generic_catch_entered"
            )
            VoiceEnrollmentDiagnostics.logCaughtError(
                stage: "finish_phrase_generic",
                error: error
            )
            VoiceEnrollmentDiagnostics.logEnrollmentOutcome(
                succeeded: false,
                reason: VoiceEnrollmentReason.from(error),
                samplesCollected: embeddings.count,
                promptCount: phrases.count
            )
            setStage(.ready)
            message = error.localizedDescription
            isFailure = true
            UINotificationFeedbackGenerator()
                .notificationOccurred(.warning)
        }
    }

    private func saveProfile() async throws {
        setStage(.saving)

        VoiceEnrollmentDiagnostics.logBoundary(
            "save_profile_before_aggregation"
        )
        let outcome = VoiceVectorMath.aggregateEnrollmentDetailed(
            embeddings.map(\.values)
        )
        VoiceEnrollmentDiagnostics.logBoundary(
            "save_profile_after_aggregation"
        )
        VoiceEnrollmentDiagnostics.logAggregationDetail(
            inputCount: outcome.inputCount,
            minimumSamples: outcome.minimumSamples,
            outlierDistance: outcome.outlierDistance,
            similarities: outcome.similarities,
            survivorCount: outcome.survivorCount,
            succeeded: outcome.aggregate != nil,
            reason: outcome.aggregate == nil ? .aggregationFailed : nil
        )
        VoiceEnrollmentDiagnostics.logAggregation(
            sampleCount: outcome.inputCount,
            succeeded: outcome.aggregate != nil,
            dimension: outcome.aggregate?.count
        )

        guard let aggregate = outcome.aggregate,
              let model = embeddings.first?.model else {
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .aggregationFailed,
                stage: "save_profile_aggregation"
            )
            VoiceEnrollmentDiagnostics.logEnrollmentOutcome(
                succeeded: false,
                reason: .aggregationFailed,
                samplesCollected: embeddings.count,
                promptCount: phrases.count
            )
            embeddings.removeAll()
            phraseIndex = 0
            setStage(.ready)
            throw VoiceRecognitionError.invalidEmbedding
        }

        let collectedSamples = embeddings.count
        do {
            VoiceEnrollmentDiagnostics.logBoundary(
                "save_profile_before_enroll"
            )
            try await profiles.enroll(
                embedding: VoiceEmbedding(
                    values: aggregate,
                    model: model
                ),
                consentedAt: .now
            )
            VoiceEnrollmentDiagnostics.logBoundary(
                "save_profile_after_enroll"
            )
        } catch {
            VoiceEnrollmentDiagnostics.logCaughtError(
                stage: "save_profile_enroll",
                error: error
            )
            VoiceEnrollmentDiagnostics.logEnrollmentOutcome(
                succeeded: false,
                reason: VoiceEnrollmentReason.from(error),
                samplesCollected: collectedSamples,
                promptCount: phrases.count
            )
            throw error
        }

        embeddings.removeAll()
        setStage(.completed)
        VoiceEnrollmentDiagnostics.logEnrollmentOutcome(
            succeeded: true,
            reason: nil,
            samplesCollected: collectedSamples,
            promptCount: phrases.count
        )
        UINotificationFeedbackGenerator()
            .notificationOccurred(.success)
    }

    /// Single place stage changes are applied, so every transition is logged.
    /// Behavior is unchanged: this only wraps the existing assignment.
    private func setStage(_ newStage: Stage) {
        guard newStage != stage else { return }
        VoiceEnrollmentDiagnostics.logStageChange(
            from: String(describing: stage),
            to: String(describing: newStage)
        )
        stage = newStage
    }

    nonisolated static func prompts(
        displayName: String,
        locale: Locale
    ) -> [String] {
        let name = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty ? "there" : displayName
        let language = locale.language.languageCode?.identifier
            ?? locale.identifier.split(separator: "_").first.map(String.init)
            ?? "en"

        if language == "fil" || language == "tl" {
            return [
                "Hi Aligna, ako si \(name).",
                "Let’s turn this meeting into clear next steps.",
                "Ako ang bahala sa task at tatapusin ko ito bukas.",
                "Okay, let’s review the notes before we finish.",
            ]
        }
        return [
            "Hi Aligna, I’m \(name).",
            "Let’s turn this conversation into clear next steps.",
            "I’ll review the notes and finish my tasks tomorrow.",
            "Okay, let’s make sure everyone knows what happens next.",
        ]
    }
}

extension EnrollmentSampleIssue: Error {}
