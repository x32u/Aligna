import CoreMedia
import Foundation
import Speech

actor AppleSpeechTranscriptionService: SpeechTranscribing {
    private enum LiveModule {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)

        var modules: [any SpeechModule] {
            switch self {
            case let .speech(value): [value]
            case let .dictation(value): [value]
            }
        }
    }

    private let assetManager: any TranscriptionAssetManaging

    private var module: LiveModule?
    private var analyzer: SpeechAnalyzer?
    private var converter: AnalyzerInputConverter?
    private var inputTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var resultContinuation:
        AsyncThrowingStream<TranscriptionEvent, Error>.Continuation?
    private var sourceTimelineOrigin: TimeInterval?
    private var lastRelativeStart: TimeInterval = 0

    init(assetManager: any TranscriptionAssetManaging) {
        self.assetManager = assetManager
    }

    func prepare(
        request: TranscriptionRequest,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        try await assetManager.prepareAssets(
            for: request,
            pass: .live,
            progress: progress
        )

        let locale = Locale(identifier: request.localeIdentifier)
        let module: LiveModule
        switch request.engine {
        case .speechTranscriber:
            guard SpeechTranscriber.isAvailable,
                  let resolved = await SpeechTranscriber.supportedLocale(
                    equivalentTo: locale
                  )
            else {
                throw TranscriptionServiceError.unsupportedLocale(
                    request.localeIdentifier
                )
            }
            module = .speech(
                SpeechTranscriber(
                    locale: resolved,
                    preset: .timeIndexedProgressiveTranscription
                )
            )

        case .dictationTranscriber:
            guard let resolved = await DictationTranscriber.supportedLocale(
                equivalentTo: locale
            ) else {
                throw TranscriptionServiceError.unsupportedLocale(
                    request.localeIdentifier
                )
            }
            module = .dictation(
                DictationTranscriber(
                    locale: resolved,
                    preset: .progressiveLongDictation
                )
            )
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: module.modules
        ) else {
            throw TranscriptionServiceError.modelUnavailable
        }

        do {
            let analyzer = SpeechAnalyzer(
                modules: module.modules,
                options: SpeechAnalyzer.Options(
                    priority: .userInitiated,
                    modelRetention: .whileInUse
                )
            )
            if !request.glossary.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = request.glossary
                try await analyzer.setContext(context)
            }
            let converter = try await AnalyzerInputConverter.converter(
                compatibleWith: module.modules
            )
            try await analyzer.prepareToAnalyze(in: format) {
                modelProgress in
                progress(modelProgress.fractionCompleted)
            }

            self.module = module
            self.analyzer = analyzer
            self.converter = converter
            progress(1)
        } catch let error as TranscriptionServiceError {
            throw error
        } catch {
            throw TranscriptionServiceError.liveAnalyzerFailed
        }
    }

    func startTranscription(
        audioSamples: AsyncThrowingStream<AudioSample, Error>
    ) async throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
        guard let module, let analyzer, let converter else {
            throw TranscriptionServiceError.liveAnalyzerFailed
        }
        sourceTimelineOrigin = nil
        lastRelativeStart = 0

        let resultStream = AsyncThrowingStream<TranscriptionEvent, Error> {
            continuation in
            resultContinuation = continuation
        }
        let analyzerInputStream = AsyncThrowingStream<AnalyzerInput, Error> {
            continuation in
            inputTask = Task {
                do {
                    for try await sample in audioSamples {
                        try Task.checkCancellation()
                        if sourceTimelineOrigin == nil {
                            sourceTimelineOrigin = sample.time?
                                .alignaSampleTimelineSeconds
                        }
                        for input in try converter.convert(
                            sample.buffer,
                            at: sample.time
                        ) {
                            continuation.yield(input)
                        }
                    }
                    for input in try converter.flush() {
                        continuation.yield(input)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                    resultContinuation?.finish(throwing: error)
                }
            }
        }

        analysisTask = Task {
            do {
                try await analyzer.start(inputSequence: analyzerInputStream)
            } catch {
                resultContinuation?.finish(
                    throwing: TranscriptionServiceError.liveAnalyzerFailed
                )
            }
        }

        switch module {
        case let .speech(transcriber):
            resultsTask = Task {
                do {
                    for try await result in transcriber.results {
                        yield(
                            text: String(result.text.characters),
                            range: result.range,
                            isFinal: result.isFinal
                        )
                    }
                    resultContinuation?.finish()
                } catch {
                    resultContinuation?.finish(
                        throwing: TranscriptionServiceError.liveAnalyzerFailed
                    )
                }
            }

        case let .dictation(transcriber):
            resultsTask = Task {
                do {
                    for try await result in transcriber.results {
                        yield(
                            text: String(result.text.characters),
                            range: result.range,
                            isFinal: result.isFinal
                        )
                    }
                    resultContinuation?.finish()
                } catch {
                    resultContinuation?.finish(
                        throwing: TranscriptionServiceError.liveAnalyzerFailed
                    )
                }
            }
        }

        return resultStream
    }

    func finish() async throws {
        _ = await inputTask?.result
        guard let analyzer else {
            throw TranscriptionServiceError.liveAnalyzerFailed
        }

        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            _ = await resultsTask?.result
            clearTasks()
        } catch {
            clearTasks()
            throw TranscriptionServiceError.liveAnalyzerFailed
        }
    }

    func cancel() async {
        inputTask?.cancel()
        analysisTask?.cancel()
        resultsTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        await assetManager.cancel()
        resultContinuation?.finish()
        clearTasks()
    }

    private func yield(
        text: String,
        range: CMTimeRange,
        isFinal: Bool
    ) {
        let origin = sourceTimelineOrigin ?? 0
        let rawStart = range.start.seconds.finiteValue
        let rawEnd = range.end.seconds.finiteValue
        let start = max(
            lastRelativeStart,
            max(0, (rawStart ?? origin) - origin)
        )
        let end = max(start, max(0, (rawEnd ?? origin) - origin))
        lastRelativeStart = start
        let segment = TranscriptSegment(
            text: text,
            startTime: start,
            endTime: end,
            isFinal: isFinal
        )
        resultContinuation?.yield(
            isFinal ? .finalized(segment) : .volatile(segment)
        )
    }

    private func clearTasks() {
        inputTask = nil
        analysisTask = nil
        resultsTask = nil
        resultContinuation = nil
        module = nil
        analyzer = nil
        converter = nil
        sourceTimelineOrigin = nil
        lastRelativeStart = 0
    }
}

private extension AVAudioTime {
    nonisolated var alignaSampleTimelineSeconds: TimeInterval? {
        guard isSampleTimeValid, sampleRate > 0 else { return nil }
        return TimeInterval(sampleTime) / sampleRate
    }
}

private extension Double {
    nonisolated var finiteValue: Double? {
        isFinite ? self : nil
    }
}
