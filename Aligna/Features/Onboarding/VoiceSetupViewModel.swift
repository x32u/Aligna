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
        stage = .preparing
        message = "Preparing voice recognition…"
        isFailure = false
        do {
            try await profiles.updateStatus(.inProgress)
            try await engine.prepareModels()
            stage = .ready
            message = nil
        } catch {
            stage = .introduction
            message = error.localizedDescription
            isFailure = true
        }
    }

    func startPhrase() async {
        guard stage == .ready else { return }
        message = nil
        isFailure = false

        guard await recorder.requestPermission() else {
            message =
                "Allow microphone access in Settings to set up voice recognition."
            isFailure = true
            return
        }

        do {
            try await recorder.start()
            stage = .recording
            monitorRecording()
        } catch {
            stage = .ready
            message = error.localizedDescription
            isFailure = true
        }
    }

    func retryPhrase() {
        message = nil
        isFailure = false
        stage = .ready
    }

    func cancelRecording() {
        monitoringTask?.cancel()
        monitoringTask = nil
        recorder.cancel()
        microphoneLevel = 0
        stage = .ready
        message = nil
    }

    func resetToIntroduction() {
        cancelRecording()
        stage = .introduction
    }

    private func monitorRecording() {
        monitoringTask?.cancel()
        monitoringTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var voicedSeconds: TimeInterval = 0
            var silenceAfterVoice: TimeInterval = 0

            while !Task.isCancelled, stage == .recording {
                let level = recorder.normalizedLevel
                let visualLevel = min(1, level * visualLevelGain)
                microphoneLevel =
                    (microphoneLevel * 0.65) + (visualLevel * 0.35)
                if level > speechLevelThreshold {
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
        stage = .evaluating
        microphoneLevel = 0

        do {
            let samples = try await recorder.stopAndReadSamples()
            let quality = qualityAnalyzer.analyze(samples)
            if let issue = quality.issue {
                throw issue
            }
            let embedding = try await engine.embedding(from: samples)
            embeddings.append(embedding)

            if phraseIndex + 1 < phrases.count {
                phraseIndex += 1
                stage = .ready
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.success)
            } else {
                try await saveProfile()
            }
        } catch let issue as EnrollmentSampleIssue {
            stage = .ready
            message = issue.message
            isFailure = true
            UINotificationFeedbackGenerator()
                .notificationOccurred(.warning)
        } catch is CancellationError {
            stage = .ready
            message = EnrollmentSampleIssue.interrupted.message
            isFailure = true
            UINotificationFeedbackGenerator()
                .notificationOccurred(.warning)
        } catch {
            stage = .ready
            message = error.localizedDescription
            isFailure = true
            UINotificationFeedbackGenerator()
                .notificationOccurred(.warning)
        }
    }

    private func saveProfile() async throws {
        stage = .saving
        guard let aggregate = VoiceVectorMath.aggregateEnrollment(
            embeddings.map(\.values)
        ), let model = embeddings.first?.model else {
            embeddings.removeAll()
            phraseIndex = 0
            stage = .ready
            throw VoiceRecognitionError.invalidEmbedding
        }

        try await profiles.enroll(
            embedding: VoiceEmbedding(
                values: aggregate,
                model: model
            ),
            consentedAt: .now
        )
        embeddings.removeAll()
        stage = .completed
        UINotificationFeedbackGenerator()
            .notificationOccurred(.success)
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
