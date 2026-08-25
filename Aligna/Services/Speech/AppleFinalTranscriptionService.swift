import AVFAudio
import CoreMedia
import Foundation
import OSLog
import Speech

actor AppleFinalTranscriptionService: FinalTranscriptionServicing {
#if DEBUG
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Aligna",
        category: "FinalTranscription"
    )
#endif

    private let assetManager: any TranscriptionAssetManaging
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<[TranscriptSegment], Error>?

    init(assetManager: any TranscriptionAssetManaging) {
        self.assetManager = assetManager
    }

    func transcribe(
        audioURL: URL,
        meetingID: UUID,
        request: TranscriptionRequest,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> TranscriptVersion {
        guard FileManager.default.fileExists(atPath: audioURL.path())
        else {
            throw TranscriptionServiceError.invalidAudioFile
        }

        progress(0)
        try await assetManager.prepareAssets(
            for: request,
            pass: .final
        ) { assetProgress in
            progress(assetProgress.map { min(0.25, $0 * 0.25) })
        }
        try Task.checkCancellation()

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: audioURL)
        } catch {
            Self.log(error, stage: "Opening saved recording")
            throw TranscriptionServiceError.invalidAudioFile
        }
        let sampleRate = audioFile.processingFormat.sampleRate
        guard audioFile.length > 0, sampleRate > 0 else {
            throw TranscriptionServiceError.invalidAudioFile
        }
        let recordingDuration =
            TimeInterval(audioFile.length) / sampleRate

        let locale = Locale(identifier: request.localeIdentifier)
        let analysisContext = AnalysisContext()
        if !request.glossary.isEmpty {
            analysisContext.contextualStrings[.general] = request.glossary
        }

        do {
            let segments: [TranscriptSegment]
            switch request.engine {
            case .speechTranscriber:
                guard let resolved =
                    await SpeechTranscriber.supportedLocale(
                        equivalentTo: locale
                    )
                else {
                    throw TranscriptionServiceError.unsupportedLocale(
                        request.localeIdentifier
                    )
                }
                let transcriber = SpeechTranscriber(
                    locale: resolved,
                    preset: .timeIndexedTranscriptionWithAlternatives
                )
                segments = try await analyze(
                    audioFile: audioFile,
                    module: transcriber,
                    analysisContext: analysisContext,
                    progress: progress
                )

            case .dictationTranscriber:
                guard let resolved =
                    await DictationTranscriber.supportedLocale(
                        equivalentTo: locale
                    )
                else {
                    throw TranscriptionServiceError.unsupportedLocale(
                        request.localeIdentifier
                    )
                }
                let transcriber = DictationTranscriber(
                    locale: resolved,
                    preset: .timeIndexedLongDictation
                )
                segments = try await analyze(
                    audioFile: audioFile,
                    module: transcriber,
                    analysisContext: analysisContext,
                    progress: progress
                )
            }

            let normalizedSegments = TranscriptTimelineNormalizer.normalize(
                segments,
                recordingDuration: recordingDuration
            )
            guard !normalizedSegments.isEmpty else {
                throw TranscriptionServiceError.offlineAnalyzerFailed
            }
            progress(1)
            return TranscriptVersion(
                source: .offlineApple,
                engineIdentifier: request.engine.rawValue,
                localeIdentifier: request.localeIdentifier,
                segments: normalizedSegments,
                processingStatus: .succeeded
            )
        } catch is CancellationError {
            throw TranscriptionServiceError.cancelled
        } catch let error as TranscriptionServiceError {
            throw error
        } catch {
            Self.log(error, stage: "Analyzing saved recording")
            throw TranscriptionServiceError.offlineAnalyzerFailed
        }
    }

    func cancel() async {
        resultsTask?.cancel()
        resultsTask = nil
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
        await assetManager.cancel()
    }

    private func analyze(
        audioFile: AVAudioFile,
        module: SpeechTranscriber,
        analysisContext: AnalysisContext,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> [TranscriptSegment] {
        let analyzer = SpeechAnalyzer(
            modules: [module],
            options: SpeechAnalyzer.Options(
                priority: .userInitiated,
                modelRetention: .whileInUse
            )
        )
        if !analysisContext.contextualStrings.isEmpty {
            try await analyzer.setContext(analysisContext)
        }
        self.analyzer = analyzer

        let task = Task {
            try await Self.collectSpeechResults(from: module)
        }
        resultsTask = task
        progress(nil)
        guard let endTime = try await analyzer.analyzeSequence(from: audioFile)
        else {
            task.cancel()
            throw TranscriptionServiceError.invalidAudioFile
        }
        try Task.checkCancellation()
        try await analyzer.finalizeAndFinish(through: endTime)
        let segments = try await task.value
        clear()
        return segments
    }

    private func analyze(
        audioFile: AVAudioFile,
        module: DictationTranscriber,
        analysisContext: AnalysisContext,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> [TranscriptSegment] {
        let analyzer = SpeechAnalyzer(
            modules: [module],
            options: SpeechAnalyzer.Options(
                priority: .userInitiated,
                modelRetention: .whileInUse
            )
        )
        if !analysisContext.contextualStrings.isEmpty {
            try await analyzer.setContext(analysisContext)
        }
        self.analyzer = analyzer

        let task = Task {
            try await Self.collectDictationResults(from: module)
        }
        resultsTask = task
        progress(nil)
        guard let endTime = try await analyzer.analyzeSequence(from: audioFile)
        else {
            task.cancel()
            throw TranscriptionServiceError.invalidAudioFile
        }
        try Task.checkCancellation()
        try await analyzer.finalizeAndFinish(through: endTime)
        let segments = try await task.value
        clear()
        return segments
    }

    nonisolated private static func collectSpeechResults(
        from transcriber: SpeechTranscriber
    ) async throws -> [TranscriptSegment] {
        var accumulator = TranscriptAccumulator()
        for try await result in transcriber.results {
            guard result.isFinal else { continue }
            accumulator.consume(
                .finalized(
                    segment(
                        text: String(result.text.characters),
                        range: result.range
                    )
                )
            )
        }
        return accumulator.finalizedSegments
    }

    nonisolated private static func collectDictationResults(
        from transcriber: DictationTranscriber
    ) async throws -> [TranscriptSegment] {
        var accumulator = TranscriptAccumulator()
        for try await result in transcriber.results {
            guard result.isFinal else { continue }
            accumulator.consume(
                .finalized(
                    segment(
                        text: String(result.text.characters),
                        range: result.range
                    )
                )
            )
        }
        return accumulator.finalizedSegments
    }

    nonisolated private static func segment(
        text: String,
        range: CMTimeRange
    ) -> TranscriptSegment {
        TranscriptSegment(
            text: text,
            startTime: range.start.seconds.isFinite
                ? range.start.seconds
                : nil,
            endTime: range.end.seconds.isFinite
                ? range.end.seconds
                : nil,
            isFinal: true
        )
    }

    private func clear() {
        resultsTask = nil
        analyzer = nil
    }

    nonisolated private static func log(
        _ error: Error,
        stage: String
    ) {
#if DEBUG
        logger.error(
            "\(stage, privacy: .public) failed: \(String(describing: error), privacy: .public)"
        )
#endif
    }
}

actor MockFinalTranscriptionService: FinalTranscriptionServicing {
    private let segments: [TranscriptSegment]
    private let failure: TranscriptionServiceError?
    private(set) var cancellationCount = 0

    init(
        segments: [TranscriptSegment] = [
            TranscriptSegment(
                text: "Thanks everyone for joining today.",
                startTime: 0,
                endTime: 2.8,
                isFinal: true
            ),
            TranscriptSegment(
                text: "Let’s review the launch timeline and the remaining design work.",
                startTime: 3.1,
                endTime: 7.2,
                isFinal: true
            )
        ],
        failure: TranscriptionServiceError? = nil
    ) {
        self.segments = segments
        self.failure = failure
    }

    func transcribe(
        audioURL: URL,
        meetingID: UUID,
        request: TranscriptionRequest,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> TranscriptVersion {
        if let failure {
            throw failure
        }
        progress(nil)
        await Task.yield()
        progress(1)
        return TranscriptVersion(
            source: .offlineApple,
            engineIdentifier: request.engine.rawValue,
            localeIdentifier: request.localeIdentifier,
            segments: segments,
            processingStatus: .succeeded
        )
    }

    func cancel() {
        cancellationCount += 1
    }
}
