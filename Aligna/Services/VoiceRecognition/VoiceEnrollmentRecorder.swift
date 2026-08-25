import AVFoundation
import Foundation

@MainActor
final class VoiceEnrollmentRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    var currentTime: TimeInterval {
        recorder?.currentTime ?? 0
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
            throw VoiceRecognitionError.interrupted
        }
        recordingURL = url
        self.recorder = recorder
    }

    func stopAndReadSamples() async throws -> [Float] {
        guard let recorder, let recordingURL else {
            throw VoiceRecognitionError.interrupted
        }
        recorder.stop()
        self.recorder = nil
        defer {
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
            Task { await Self.deactivateAudioSession() }
        }

        let file = try AVAudioFile(forReading: recordingURL)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw VoiceRecognitionError.interrupted
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData,
              buffer.frameLength > 0
        else {
            throw VoiceRecognitionError.noSpeech
        }
        return Array(
            UnsafeBufferPointer(
                start: channels[0],
                count: Int(buffer.frameLength)
            )
        )
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
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
