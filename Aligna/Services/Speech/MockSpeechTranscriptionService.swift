import Foundation

actor MockSpeechTranscriptionService: SpeechTranscribing {
    var prepareError: MeetingCaptureError?
    var startError: MeetingCaptureError?

    private let scriptedEvents: [TranscriptionEvent]
    private let eventDelay: Duration
    private var emissionTask: Task<Void, Never>?
    private var continuation:
        AsyncThrowingStream<TranscriptionEvent, Error>.Continuation?

    init(
        scriptedEvents: [TranscriptionEvent] = MockSpeechTranscriptionService.defaultEvents,
        eventDelay: Duration = .milliseconds(650),
        prepareError: MeetingCaptureError? = nil,
        startError: MeetingCaptureError? = nil
    ) {
        self.scriptedEvents = scriptedEvents
        self.eventDelay = eventDelay
        self.prepareError = prepareError
        self.startError = startError
    }

    func prepare(
        request: TranscriptionRequest,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        if let prepareError {
            throw prepareError
        }
        progress(0.25)
        await Task.yield()
        progress(0.7)
        await Task.yield()
        progress(1)
    }

    func startTranscription(
        audioSamples: AsyncThrowingStream<AudioSample, Error>
    ) async throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
        if let startError {
            throw startError
        }

        let stream = AsyncThrowingStream<TranscriptionEvent, Error> {
            continuation in
            self.continuation = continuation
        }
        emissionTask = Task {
            for event in scriptedEvents {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: eventDelay)
                continuation?.yield(event)
            }
        }
        return stream
    }

    func finish() async throws {
        emissionTask?.cancel()
        for event in scriptedEvents {
            if case .finalized = event {
                continuation?.yield(event)
            }
        }
        continuation?.finish()
        emissionTask = nil
        continuation = nil
    }

    func cancel() async {
        emissionTask?.cancel()
        continuation?.finish()
        emissionTask = nil
        continuation = nil
    }

    nonisolated private static let defaultEvents: [TranscriptionEvent] = [
        .volatile(
            TranscriptSegment(
                text: "Thanks everyone",
                startTime: 0,
                endTime: 1.4,
                isFinal: false
            )
        ),
        .volatile(
            TranscriptSegment(
                text: "Thanks everyone for joining today.",
                startTime: 0,
                endTime: 2.8,
                isFinal: false
            )
        ),
        .finalized(
            TranscriptSegment(
                text: "Thanks everyone for joining today.",
                startTime: 0,
                endTime: 2.8,
                isFinal: true
            )
        ),
        .volatile(
            TranscriptSegment(
                text: "Let’s review the launch",
                startTime: 3.1,
                endTime: 4.9,
                isFinal: false
            )
        ),
        .finalized(
            TranscriptSegment(
                text: "Let’s review the launch timeline and the remaining design work.",
                startTime: 3.1,
                endTime: 7.2,
                isFinal: true
            )
        )
    ]
}
