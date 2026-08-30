import Foundation

/// Stand-in for the on-device final transcription pass.
///
/// The real Apple `SpeechAnalyzer` implementation was removed: it was never
/// instantiated anywhere in the app, because the shipped product direction is
/// post-meeting cloud transcription (Groq Whisper) rather than on-device
/// transcription. The `FinalTranscriptionServicing` seam and this mock are kept
/// so `MeetingCaptureDependencies` still compiles and the capture flow's
/// transcript plumbing stays exercised by tests.
///
/// If on-device transcription is revived, implement a new conformance here
/// rather than restoring the deleted analyzer wholesale.
actor MockFinalTranscriptionService: FinalTranscriptionServicing {
    private let segments: [TranscriptSegment]
    private let failure: TranscriptionServiceError?
    private(set) var cancellationCount = 0

    init(
        segments: [TranscriptSegment] = [],
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
