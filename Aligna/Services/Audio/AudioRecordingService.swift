import AVFAudio
import Foundation

nonisolated struct AudioSample: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let time: AVAudioTime?
}

nonisolated enum AudioRecordingEvent: Sendable {
    case level(Float)
    case interruptionBegan
    case routeChanged(inputName: String?)
}

nonisolated struct AudioRecordingSession: Sendable {
    let fileURL: URL
    let samples: AsyncThrowingStream<AudioSample, Error>
    let events: AsyncStream<AudioRecordingEvent>
}

@MainActor
protocol AudioRecording: AnyObject {
    func requestPermission() async -> Bool
    func startRecording() async throws -> AudioRecordingSession
    func pause() throws
    func resume() async throws
    func stop() async throws -> URL
    func cancel() async
}

@MainActor
final class AudioRecordingService: NSObject, AudioRecording {
    private let audioSession = AVAudioSession.sharedInstance()
    private let fileManager: FileManager

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var sampleContinuation:
        AsyncThrowingStream<AudioSample, Error>.Continuation?
    private var eventContinuation:
        AsyncStream<AudioRecordingEvent>.Continuation?
    private var meteringTask: Task<Void, Never>?
    private var notificationTokens: [NSObjectProtocol] = []
    private var isRecording = false
    private var isPaused = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        super.init()
    }

    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            true
        case .denied:
            false
        case .undetermined:
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            false
        }
    }

    func startRecording() async throws -> AudioRecordingSession {
        guard !isRecording else {
            throw MeetingCaptureError.invalidAction
        }

        do {
            try await AudioSessionController.prepareForRecording()
        } catch {
            throw MeetingCaptureError.audioSessionFailed
        }

        let directory = try MeetingFileLocations.recordingsDirectory(
            fileManager: fileManager
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let recordingURL = directory
            .appending(path: UUID().uuidString.lowercased())
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(
                url: recordingURL,
                settings: settings
            )
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record() else {
                throw MeetingCaptureError.audioSessionFailed
            }
            self.recorder = recorder
            fileURL = recordingURL
        } catch let error as MeetingCaptureError {
            await AudioSessionController.deactivate()
            throw error
        } catch {
            await AudioSessionController.deactivate()
            throw MeetingCaptureError.audioSessionFailed
        }

        let samples = AsyncThrowingStream<AudioSample, Error> { continuation in
            sampleContinuation = continuation
        }
        let events = AsyncStream<AudioRecordingEvent> { continuation in
            eventContinuation = continuation
        }

        isRecording = true
        isPaused = false
        registerForAudioNotifications()
        startMetering()

        return AudioRecordingSession(
            fileURL: recordingURL,
            samples: samples,
            events: events
        )
    }

    func pause() throws {
        guard isRecording, !isPaused, let recorder else {
            throw MeetingCaptureError.invalidAction
        }
        recorder.pause()
        isPaused = true
    }

    func resume() async throws {
        guard isRecording, isPaused, let recorder else {
            throw MeetingCaptureError.invalidAction
        }
        do {
            try await AudioSessionController.activate()
            guard recorder.record() else {
                throw MeetingCaptureError.audioSessionFailed
            }
            isPaused = false
        } catch let error as MeetingCaptureError {
            throw error
        } catch {
            throw MeetingCaptureError.audioSessionFailed
        }
    }

    func stop() async throws -> URL {
        guard isRecording, let fileURL else {
            throw MeetingCaptureError.invalidAction
        }
        recorder?.stop()
        await cleanUp(deleteFile: false)

        let values = try fileURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey]
        )
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw MeetingCaptureError.audioSessionFailed
        }
        return fileURL
    }

    func cancel() async {
        recorder?.stop()
        await cleanUp(deleteFile: true)
    }

    private func startMetering() {
        meteringTask?.cancel()
        meteringTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.isRecording {
                if !self.isPaused, let recorder = self.recorder {
                    recorder.updateMeters()
                    let decibels = recorder.averagePower(forChannel: 0)
                    let level = min(max((decibels + 60) / 60, 0), 1)
                    self.eventContinuation?.yield(.level(level))
                }
                try? await Task.sleep(for: .milliseconds(55))
            }
        }
    }

    private func cleanUp(deleteFile: Bool) async {
        isRecording = false
        isPaused = false
        meteringTask?.cancel()
        meteringTask = nil
        sampleContinuation?.finish()
        eventContinuation?.finish()
        sampleContinuation = nil
        eventContinuation = nil
        recorder = nil

        notificationTokens.forEach(
            NotificationCenter.default.removeObserver
        )
        notificationTokens.removeAll()

        await AudioSessionController.deactivate()

        if deleteFile, let fileURL {
            try? fileManager.removeItem(at: fileURL)
        }
        self.fileURL = nil
    }

    private func registerForAudioNotifications() {
        let center = NotificationCenter.default

        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.didBecomeInactiveNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    self.recorder?.pause()
                    self.isPaused = true
                    self.eventContinuation?.yield(.interruptionBegan)
                }
            }
        )

        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.audioSession.currentRoute.inputs.isEmpty {
                        self.recorder?.pause()
                        self.isPaused = true
                        self.eventContinuation?.yield(.interruptionBegan)
                    } else {
                        self.eventContinuation?.yield(
                            .routeChanged(
                                inputName: self.audioSession.currentRoute
                                    .inputs.first?.portName
                            )
                        )
                    }
                }
            }
        )
    }
}

nonisolated private enum AudioSessionController {
    static func prepareForRecording() async throws {
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

    static func activate() async throws {
        try await Task.detached(priority: .userInitiated) {
            try AVAudioSession.sharedInstance().setActive(true)
        }.value
    }

    static func deactivate() async {
        await Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        }.value
    }
}
