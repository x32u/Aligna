import AVFAudio
import Foundation

@MainActor
final class MockAudioRecordingService: AudioRecording {
    var permissionGranted = true
    var startError: MeetingCaptureError?
    /// Thrown by `resume()`, simulating a session that will not re-activate.
    var resumeError: MeetingCaptureError?
    /// When true, `resume()` succeeds but the recorder stays stopped — the
    /// real-device failure where `record()` reports success and captures
    /// nothing.
    var resumeSilentlyFails = false
    private(set) var cancelCount = 0
    private(set) var requestCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var latestFileURL: URL?

    private let fileManager: FileManager
    private var fileURL: URL?
    private var sampleContinuation: AsyncThrowingStream<AudioSample, Error>.Continuation?
    private var eventContinuation: AsyncStream<AudioRecordingEvent>.Continuation?
    private var levelTask: Task<Void, Never>?
    private var isPaused = false
    private var isCapturing = false

    var isActivelyRecording: Bool {
        isCapturing && !isPaused
    }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Simulates the system taking the audio session away.
    func simulateInterruptionBegan() {
        isPaused = true
        eventContinuation?.yield(.interruptionBegan)
    }

    /// Simulates the system returning the audio session.
    func simulateInterruptionEnded(canResume: Bool) {
        eventContinuation?.yield(.interruptionEnded(canResume: canResume))
    }

    /// Simulates a media-services reset invalidating the recorder.
    func simulateRecordingStopped() {
        isPaused = true
        isCapturing = false
        eventContinuation?.yield(.recordingStopped)
    }

    func requestPermission() async -> Bool {
        requestCount += 1
        return permissionGranted
    }

    func startRecording() async throws -> AudioRecordingSession {
        startCount += 1
        if let startError {
            throw startError
        }

        let directory = fileManager.temporaryDirectory
            .appending(path: "AlignaMockRecordings", directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("m4a")
        try createSilentRecording(at: url)
        fileURL = url
        latestFileURL = url
        isCapturing = true
        isPaused = false

        let samples = AsyncThrowingStream<AudioSample, Error> { continuation in
            sampleContinuation = continuation
        }
        let events = AsyncStream<AudioRecordingEvent> { continuation in
            eventContinuation = continuation
        }

        levelTask = Task { [weak self] in
            let levels: [Float] = [0.18, 0.35, 0.62, 0.43, 0.75, 0.28]
            var index = 0
            while !Task.isCancelled {
                if self?.isPaused == false {
                    self?.eventContinuation?.yield(
                        .level(levels[index % levels.count])
                    )
                    index += 1
                }
                try? await Task.sleep(for: .milliseconds(140))
            }
        }

        return AudioRecordingSession(
            fileURL: url,
            samples: samples,
            events: events
        )
    }

    func pause() throws {
        pauseCount += 1
        isPaused = true
    }

    func resume() async throws {
        resumeCount += 1
        if let resumeError {
            throw resumeError
        }
        // `resumeSilentlyFails` leaves the recorder stopped even though the call
        // returned successfully.
        isPaused = false
        if resumeSilentlyFails {
            isCapturing = false
        }
    }

    func stop() async throws -> URL {
        stopCount += 1
        guard let fileURL else {
            throw MeetingCaptureError.invalidAction
        }
        isCapturing = false
        finishStreams()
        return fileURL
    }

    func cancel() async {
        cancelCount += 1
        isCapturing = false
        finishStreams()
        if let fileURL {
            try? fileManager.removeItem(at: fileURL)
        }
        fileURL = nil
    }

    private func finishStreams() {
        levelTask?.cancel()
        levelTask = nil
        sampleContinuation?.finish()
        eventContinuation?.finish()
        sampleContinuation = nil
        eventContinuation = nil
    }

    private func createSilentRecording(at url: URL) throws {
        guard
            let format = AVAudioFormat(
                standardFormatWithSampleRate: 16_000,
                channels: 1
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: 16_000
            )
        else {
            throw MeetingCaptureError.audioSessionFailed
        }

        buffer.frameLength = buffer.frameCapacity
        if let channelData = buffer.floatChannelData?.pointee {
            channelData.initialize(
                repeating: 0,
                count: Int(buffer.frameLength)
            )
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 48_000,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }
}
