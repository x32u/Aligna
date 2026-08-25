import Foundation
import FluidAudio

actor FluidAudioVoiceEngine: VoiceProcessing {
    private let model = VoiceModelDescriptor.fluidAudioOfflineV1
    private let manager: OfflineDiarizerManager
    private var isPrepared = false

    init() {
        var configuration = OfflineDiarizerConfig.default
        configuration.exposeChunkEmbeddings = true
        manager = OfflineDiarizerManager(config: configuration)
    }

    func prepareModels() async throws {
        guard !isPrepared else { return }
        let directory = try Self.modelsDirectory()
        do {
            try await manager.prepareModels(directory: directory)
            isPrepared = true
        } catch {
            throw VoiceRecognitionError.modelUnavailable
        }
    }

    func embedding(from samples: [Float]) async throws -> VoiceEmbedding {
        guard !samples.isEmpty else {
            throw VoiceRecognitionError.noSpeech
        }
        try await prepareModels()

        let result: DiarizationResult
        do {
            result = try await manager.process(audio: samples)
        } catch let error as OfflineDiarizationError {
            if case .noSpeechDetected = error {
                throw VoiceRecognitionError.noSpeech
            }
            throw VoiceRecognitionError.modelUnavailable
        } catch {
            throw VoiceRecognitionError.modelUnavailable
        }

        guard let database = result.speakerDatabase,
              database.count == 1
        else {
            if (result.speakerDatabase?.count ?? 0) > 1 {
                throw VoiceRecognitionError.multipleSpeakers
            }
            throw VoiceRecognitionError.noSpeech
        }
        guard let raw = database.values.first,
              let normalized = VoiceVectorMath.normalized(raw),
              normalized.count == model.embeddingDimension
        else {
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
