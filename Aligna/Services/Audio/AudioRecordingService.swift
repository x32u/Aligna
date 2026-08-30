import AVFAudio
import Foundation
import OSLog

/// Diagnostics for the meeting recorder. Records only device-independent
/// settings values, never audio or identifiers.
nonisolated enum RecordingDiagnostics {
    private static let logger = Logger(
        subsystem: "dev.notjc.Aligna",
        category: "Recording"
    )

    static func logInvalidSettings(sampleRate: Int?, bitRate: Int?) {
        logger.error(
            """
            Recorder settings rejected by prepareToRecord. \
            sampleRate=\(sampleRate ?? -1, privacy: .public) \
            bitRate=\(bitRate ?? -1, privacy: .public)
            """
        )
    }
}

nonisolated struct AudioSample: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let time: AVAudioTime?
}

nonisolated enum AudioRecordingEvent: Sendable {
    case level(Float)
    /// The system took the audio session away (call, Siri, another app) or the
    /// input route disappeared. Capture is paused.
    case interruptionBegan
    /// The system handed the audio session back. `canResume` mirrors
    /// `AVAudioSession.InterruptionOptions.shouldResume`.
    case interruptionEnded(canResume: Bool)
    /// The recorder stopped without being asked to — an encode failure or a
    /// media-services reset. Capture is over; the UI must not keep claiming to
    /// be recording.
    case recordingStopped
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

    /// Whether the underlying recorder is actually capturing right now.
    ///
    /// The capture UI must be able to check this rather than trusting its own
    /// state: after an interruption the recorder can be stopped while the view
    /// model still believes it is paused-and-resumable.
    var isActivelyRecording: Bool { get }
}

extension AudioRecording {
    var isActivelyRecording: Bool { true }
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
    /// True once the system has taken the session away and not yet returned it.
    /// `resume()` must re-activate the session before recording can continue.
    private var isInterrupted = false

    var isActivelyRecording: Bool {
        recorder?.isRecording ?? false
    }

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

        // 16 kHz mono is the rate FluidAudio's diarizer resamples to, so the
        // recording is captured at the rate downstream processing wants.
        // AAC-LC at this sample rate has a low valid bitrate ceiling — above
        // ~48 kbps `AVAudioRecorder.prepareToRecord()` fails and recording never
        // starts. 48 kbps is near that ceiling and proportionate to 8 kHz of
        // Nyquist content, so it is not "thin" the way it would be at 44.1 kHz.
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
            // `prepareToRecord()` returning false means the settings are invalid
            // for this device/format (e.g. an out-of-range AAC bitrate), which
            // is a programming error, not a transient session conflict. Surface
            // it distinctly rather than letting it fall through to the generic
            // "check other audio apps" message.
            guard recorder.prepareToRecord() else {
                RecordingDiagnostics.logInvalidSettings(
                    sampleRate: settings[AVSampleRateKey] as? Int,
                    bitRate: settings[AVEncoderBitRateKey] as? Int
                )
                throw MeetingCaptureError.audioSessionFailed
            }
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
        isInterrupted = false
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
            // An interruption deactivates the session. Re-activating is what
            // actually lets the recorder capture again; without it `record()`
            // reports success while no audio reaches the file.
            try await AudioSessionController.activate()
            guard recorder.record() else {
                throw MeetingCaptureError.audioSessionFailed
            }
            // `record()` can return true and still leave the recorder stopped
            // when the session is not usable. Verify with the recorder itself
            // rather than trusting the return value.
            guard recorder.isRecording else {
                throw MeetingCaptureError.recordingInterrupted
            }
            isPaused = false
            isInterrupted = false
            // Metering stops looping once `isRecording` flips false; after a
            // recorder-level stop the task must be restarted.
            startMetering()
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

        // The primary interruption signal. This was previously not observed at
        // all, so a phone call paused capture with no way to learn the system
        // had finished with the session.
        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                let rawType = notification.userInfo?[
                    AVAudioSessionInterruptionTypeKey
                ] as? UInt
                let rawOptions = notification.userInfo?[
                    AVAudioSessionInterruptionOptionKey
                ] as? UInt
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    guard let rawType,
                          let type = AVAudioSession.InterruptionType(
                              rawValue: rawType
                          )
                    else {
                        return
                    }
                    switch type {
                    case .began:
                        self.handleInterruptionBegan()
                    case .ended:
                        let options = AVAudioSession.InterruptionOptions(
                            rawValue: rawOptions ?? 0
                        )
                        self.isInterrupted = false
                        self.eventContinuation?.yield(
                            .interruptionEnded(
                                canResume: options.contains(.shouldResume)
                            )
                        )
                    @unknown default:
                        return
                    }
                }
            }
        )

        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.didBecomeInactiveNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    self.handleInterruptionBegan()
                }
            }
        )

        // A media-services reset invalidates the recorder entirely; it cannot
        // be resumed. Report a hard stop instead of a resumable pause.
        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    self.recorder?.pause()
                    self.isPaused = true
                    self.isInterrupted = true
                    self.eventContinuation?.yield(.recordingStopped)
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
                        self.handleInterruptionBegan()
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

    private func handleInterruptionBegan() {
        guard !isPaused else { return }
        recorder?.pause()
        isPaused = true
        isInterrupted = true
        eventContinuation?.yield(.interruptionBegan)
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
