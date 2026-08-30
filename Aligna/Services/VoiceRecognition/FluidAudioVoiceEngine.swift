import Foundation
import FluidAudio

actor FluidAudioVoiceEngine: VoiceProcessing {
    /// The rate the offline diarizer's segmentation stage expects. Used only to
    /// convert sample counts into seconds for diagnostics.
    nonisolated static let sampleRate: Double = 16_000

    private let model = VoiceModelDescriptor.fluidAudioOfflineV1
    private let manager: OfflineDiarizerManager
    private var isPrepared = false

    init() {
        var configuration = OfflineDiarizerConfig.default
        configuration.exposeChunkEmbeddings = true
        // Device evidence (2 centroids, ~even frame split, but only S1 in the
        // reconstructed segments) shows the reconstruction stage absorbing a
        // real speaker's turns into its neighbour. FluidAudio ships this
        // re-embed pass disabled; it re-embeds zero-vote spans and assigns them
        // to the nearest centroid instead of collapsing them. Controlled
        // hypothesis test for the "2 clusters → 1 speaker" failure — measure on
        // device before keeping.
        configuration.zeroVoteReembed = .init(
            enabled: true,
            minDurationSeconds: 0.4
        )
        manager = OfflineDiarizerManager(config: configuration)
    }

    func prepareModels() async throws {
        guard !isPrepared else {
            VoiceEnrollmentDiagnostics.logModelReadiness(
                prepared: true,
                reason: "already_prepared"
            )
            return
        }
        let directory = try Self.modelsDirectory()
        do {
            try await manager.prepareModels(directory: directory)
            isPrepared = true
            VoiceEnrollmentDiagnostics.logModelReadiness(
                prepared: true,
                reason: "loaded"
            )
        } catch {
            VoiceEnrollmentDiagnostics.logModelReadiness(
                prepared: false,
                reason: "load_failed"
            )
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .modelUnavailable,
                stage: "prepare_models"
            )
            throw VoiceRecognitionError.modelUnavailable
        }
    }

    func embedding(from samples: [Float]) async throws -> VoiceEmbedding {
        guard !samples.isEmpty else {
            VoiceEnrollmentDiagnostics.logDiarizerOutput(
                sampleCount: 0,
                sampleRate: Self.sampleRate,
                segmentCount: 0,
                speakerDatabaseCount: 0,
                embeddingDimension: nil
            )
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .fluidAudioNoSpeechDetected,
                stage: "embedding_empty_samples"
            )
            throw VoiceRecognitionError.noSpeech
        }
        try await prepareModels()

        let result: DiarizationResult
        do {
            result = try await manager.process(audio: samples)
        } catch let error as OfflineDiarizationError {
            if case .noSpeechDetected = error {
                // FluidAudio produced no embeddings at all for this utterance.
                VoiceEnrollmentDiagnostics.logDiarizerOutput(
                    sampleCount: samples.count,
                    sampleRate: Self.sampleRate,
                    segmentCount: 0,
                    speakerDatabaseCount: 0,
                    embeddingDimension: nil
                )
                VoiceEnrollmentDiagnostics.logRejection(
                    reason: .fluidAudioNoSpeechDetected,
                    stage: "embedding_process"
                )
                throw VoiceRecognitionError.noSpeech
            }
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .modelUnavailable,
                stage: "embedding_process_offline_error"
            )
            throw VoiceRecognitionError.modelUnavailable
        } catch {
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .modelUnavailable,
                stage: "embedding_process_unexpected"
            )
            throw VoiceRecognitionError.modelUnavailable
        }

        // Raw diarizer output, captured before any transformation or discard.
        let databaseCount = result.speakerDatabase?.count ?? 0
        VoiceEnrollmentDiagnostics.logDiarizerOutput(
            sampleCount: samples.count,
            sampleRate: Self.sampleRate,
            segmentCount: result.segments.count,
            speakerDatabaseCount: databaseCount,
            embeddingDimension: result.speakerDatabase?.values.first?.count
        )
        VoiceEnrollmentDiagnostics.logDiarizerSegments(
            result.segments.map {
                (
                    $0.speakerId,
                    TimeInterval($0.startTimeSeconds),
                    TimeInterval($0.endTimeSeconds)
                )
            }
        )

        guard let database = result.speakerDatabase,
              database.count == 1
        else {
            if databaseCount > 1 {
                VoiceEnrollmentDiagnostics.logRejection(
                    reason: .diarizerSpeakerCountUnexpected,
                    stage: "embedding_speaker_count"
                )
                throw VoiceRecognitionError.multipleSpeakers
            }
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .diarizerEmptyClusters,
                stage: "embedding_speaker_count"
            )
            throw VoiceRecognitionError.noSpeech
        }
        guard let raw = database.values.first,
              let normalized = VoiceVectorMath.normalized(raw),
              normalized.count == model.embeddingDimension
        else {
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .embeddingInvalid,
                stage: "embedding_normalization"
            )
            throw VoiceRecognitionError.invalidEmbedding
        }
        return VoiceEmbedding(values: normalized, model: model)
    }

    func diarize(audioURL: URL) async throws -> DiarizationOutput {
        try await prepareModels()

        let result: DiarizationResult
        do {
            result = try await manager.process(audioURL)
        } catch let error as OfflineDiarizationError {
            if case .noSpeechDetected = error {
                throw VoiceRecognitionError.noSpeech
            }
            throw VoiceRecognitionError.interrupted
        } catch {
            throw VoiceRecognitionError.interrupted
        }

        let intervals = result.segments.map {
            DiarizationInterval(
                stableSpeakerKey: $0.speakerId,
                startSeconds: TimeInterval($0.startTimeSeconds),
                endSeconds: TimeInterval($0.endTimeSeconds)
            )
        }
        let clusters = (result.speakerDatabase ?? [:])
            .sorted { $0.key < $1.key }
            .compactMap { key, raw -> SpeakerCluster? in
                guard let normalized = VoiceVectorMath.normalized(raw),
                      normalized.count == model.embeddingDimension
                else {
                    return nil
                }
                return SpeakerCluster(
                    stableSpeakerKey: key,
                    embedding: VoiceEmbedding(
                        values: normalized,
                        model: model
                    )
                )
            }

        guard !intervals.isEmpty, !clusters.isEmpty else {
            throw VoiceRecognitionError.noSpeech
        }
        return DiarizationOutput(
            intervals: intervals,
            clusters: clusters
        )
    }

    private static func modelsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("VoiceRecognition", isDirectory: true)
            .appendingPathComponent(
                VoiceModelDescriptor.fluidAudioOfflineV1.modelVersion,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [
                .protectionKey:
                    FileProtectionType.completeUntilFirstUserAuthentication
            ]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
        return directory
    }
}
