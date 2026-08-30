import AVFoundation
import Foundation

@MainActor
final class VoiceEnrollmentRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    /// Wall-clock start, so a stopped recorder can still report how long it ran.
    /// `AVAudioRecorder.currentTime` is only valid while recording.
    private var startedAt: Date?
    private var lastKnownDuration: TimeInterval = 0

    var currentTime: TimeInterval {
        recorder?.currentTime ?? 0
    }

    /// Whether the underlying recorder is actually capturing right now.
    /// Diagnostic only — no caller behavior depends on it yet.
    var isActivelyRecording: Bool {
        recorder?.isRecording ?? false
    }

    var normalizedLevel: Float {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        return min(1, max(0, pow(10, power / 20)))
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
    }

    func start() async throws {
        cleanup()
        try await Self.activateAudioSession()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "aligna-voice-\(UUID().uuidString.lowercased()).caf"
            )
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let recorder = try AVAudioRecorder(
            url: url,
            settings: settings
        )
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            try? FileManager.default.removeItem(at: url)
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .recordingFailed,
                stage: "start_record_refused"
            )
            throw VoiceRecognitionError.interrupted
        }
        recordingURL = url
        self.recorder = recorder
        startedAt = Date()
        lastKnownDuration = 0
    }

    func stopAndReadSamples() async throws -> [Float] {
        guard let recorder, let recordingURL else {
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .recordingFailed,
                stage: "stop_no_recorder"
            )
            throw VoiceRecognitionError.interrupted
        }
        // Capture duration and live state BEFORE stopping: `currentTime` is only
        // valid while the recorder is running.
        let wasActivelyRecording = recorder.isRecording
        let recordedDuration = recorder.currentTime
        lastKnownDuration = recordedDuration > 0
            ? recordedDuration
            : (startedAt.map { Date().timeIntervalSince($0) } ?? 0)
        recorder.stop()
        self.recorder = nil
        VoiceEnrollmentDiagnostics.logRecordingStopped(
            totalSeconds: lastKnownDuration,
            trigger: wasActivelyRecording
                ? "stop_requested_while_recording"
                : "stop_requested_while_not_recording"
        )
        defer {
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
            startedAt = nil
            Task { await Self.deactivateAudioSession() }
        }

        let file = try AVAudioFile(forReading: recordingURL)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .recordingFailed,
                stage: "stop_buffer_allocation"
            )
            throw VoiceRecognitionError.interrupted
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData,
              buffer.frameLength > 0
        else {
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .fluidAudioNoSpeechDetected,
                stage: "stop_empty_buffer"
            )
            throw VoiceRecognitionError.noSpeech
        }
        VoiceEnrollmentDiagnostics.logRecordedFile(
            frameCount: Int(buffer.frameLength),
            sampleRate: file.processingFormat.sampleRate,
            recorderReportedSeconds: lastKnownDuration
        )
        return Array(
            UnsafeBufferPointer(
                start: channels[0],
                count: Int(buffer.frameLength)
            )
        )
    }

    func cancel() {
        let wasRecording = recorder?.isRecording ?? false
        let duration = recorder?.currentTime
            ?? startedAt.map { Date().timeIntervalSince($0) }
            ?? 0
        recorder?.stop()
        recorder = nil
        startedAt = nil
        VoiceEnrollmentDiagnostics.logRecordingStopped(
            totalSeconds: duration,
            trigger: wasRecording
                ? "cancelled_while_recording"
                : "cancelled_while_not_recording"
        )
        cleanup()
        Task { await Self.deactivateAudioSession() }
    }

    private func cleanup() {
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
    }

    nonisolated private static func activateAudioSession() async throws {
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .record,
                mode: .measurement,
                options: [.allowBluetoothHFP]
            )
            try session.setPreferredSampleRate(16_000)
            try session.setActive(true)
        }.value
    }

    nonisolated private static func deactivateAudioSession() async {
        await Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        }.value
    }

    deinit {
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
    }
}
