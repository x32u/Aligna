import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class MeetingCaptureViewModel {
    private(set) var state: MeetingCaptureState = .idle
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var audioLevels = AudioLevelHistory().samples
    private(set) var savedMeeting: Meeting?

    let configuration: NewMeetingConfiguration

    private let audio: any AudioRecording
    private let liveActivity: any MeetingRecordingLiveActivityControlling
    private let repository: any MeetingRepository
    private let now: () -> Date
    private let onSaved: (Meeting) -> Void

    private var machine = MeetingCaptureStateMachine()
    private var durationTracker = RecordingDurationTracker()
    private var audioLevelHistory = AudioLevelHistory()
    private var pendingPeakLevel: Float = 0
    private var lastLevelPresentationDate = Date.distantPast
    private var recordingStartedAt: Date?
    private var audioEventsTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var completedAudioURL: URL?

    init(
        configuration: NewMeetingConfiguration,
        dependencies: MeetingCaptureDependencies,
        repository: any MeetingRepository,
        now: @escaping () -> Date = Date.init,
        onSaved: @escaping (Meeting) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.audio = dependencies.audio
        self.liveActivity = dependencies.liveActivity
        self.repository = repository
        self.now = now
        self.onSaved = onSaved
    }

    var stateTitle: String {
        switch state {
        case .idle, .ready:
            "Ready"
        case .requestingPermission, .preparingModel:
            "Starting"
        case .recording:
            "Recording"
        case .paused:
            "Paused"
        case .finishing, .finalizingTranscript:
            "Saving"
        case .completed:
            "Saved"
        case .failed:
            "Needs attention"
        }
    }

    var formattedElapsedTime: String {
        let seconds = max(0, Int(elapsedTime.rounded(.down)))
        return String(
            format: "%02d:%02d:%02d",
            seconds / 3_600,
            (seconds % 3_600) / 60,
            seconds % 60
        )
    }

    func start() async {
        guard transition(to: .requestingPermission) else { return }
        completedAudioURL = nil
        announce("Requesting microphone access")

        guard await audio.requestPermission() else {
            fail(.microphonePermissionDenied, cleanUp: false)
            return
        }

        do {
            transition(to: .ready)
            let session = try await audio.startRecording()
            let startDate = now()
            recordingStartedAt = startDate
            durationTracker.start(at: startDate)
            transition(to: .recording)
            observeAudioEvents(session.events)
            startTimer()
            announce("Recording started")
            await liveActivity.start(
                meetingTitle: "Meeting in progress",
                elapsedTime: elapsedTime,
                at: startDate
            )
        } catch let captureError as MeetingCaptureError {
            await failAndCleanUp(captureError)
        } catch {
            await failAndCleanUp(.audioSessionFailed)
        }
    }

    func pause() async {
        guard state.canPause else { return }
        do {
            try audio.pause()
            let pauseDate = now()
            durationTracker.pause(at: pauseDate)
            updateElapsedTime()
            audioLevels = audioLevelHistory.settle()
            transition(to: .paused)
            announce("Recording paused")
            await liveActivity.update(
                phase: .paused,
                elapsedTime: elapsedTime,
                at: pauseDate
            )
        } catch let captureError as MeetingCaptureError {
            await failAndCleanUp(captureError)
        } catch {
            await failAndCleanUp(.audioSessionFailed)
        }
    }

    func resume() async {
        guard state.canResume else { return }
        do {
            try await audio.resume()
            let resumeDate = now()
            durationTracker.resume(at: resumeDate)
            transition(to: .recording)
            announce("Recording resumed")
            await liveActivity.update(
                phase: .recording,
                elapsedTime: elapsedTime,
                at: resumeDate
            )
        } catch let captureError as MeetingCaptureError {
            await failAndCleanUp(captureError)
        } catch {
            await failAndCleanUp(.audioSessionFailed)
        }
    }

    func finish() async {
        guard state.canFinish, transition(to: .finishing) else { return }
        announce("Saving recording")

        let finishDate = now()
        let duration = durationTracker.finish(at: finishDate)
        updateElapsedTime()
        timerTask?.cancel()
        await liveActivity.update(
            phase: .finishing,
            elapsedTime: duration,
            at: finishDate
        )

        do {
            // Stopping closes the M4A container before persistence or upload.
            let audioURL = try await audio.stop()
            completedAudioURL = audioURL
            let meeting = Meeting(
                title: configuration.title,
                projectName: configuration.workspace?.name
                    ?? "Aligna workspace",
                scheduledAt: recordingStartedAt ?? now(),
                durationSeconds: duration,
                participants: configuration.participants,
                status: .processing,
                transcript: [],
                transcriptDocument: nil,
                audioFileName: audioURL.lastPathComponent,
                transcriptionLocaleIdentifier: nil,
                ownerUserID: configuration.organizerUserID,
                workspaceID: configuration.workspace?.id,
                organizerUserID: configuration.organizerUserID,
                participantUserIDs: configuration.selectedMembers.map(
                    \.userID
                ),
                syncState: .local,
                processingStatus: .queued,
                analysis: nil
            )

            let persistedMeeting = try await repository.save(meeting)
            savedMeeting = persistedMeeting
            transition(to: .completed)
            onSaved(persistedMeeting)
            cancelCaptureTasks()
            announce("Meeting saved")
            await liveActivity.end(
                phase: .completed,
                elapsedTime: duration,
                at: now()
            )
        } catch let captureError as MeetingCaptureError {
            await failAndCleanUp(captureError)
        } catch {
            fail(.persistenceFailed, cleanUp: false)
            await liveActivity.end(
                phase: .failed,
                elapsedTime: duration,
                at: now()
            )
        }
    }

    func cancel() async {
        let cancellationDate = now()
        let cancellationDuration = durationTracker.elapsed(
            at: cancellationDate
        )
        cancelCaptureTasks()
        if completedAudioURL == nil {
            await audio.cancel()
        }
        await liveActivity.end(
            phase: .failed,
            elapsedTime: cancellationDuration,
            at: cancellationDate
        )

        if state != .completed {
            machine = MeetingCaptureStateMachine()
            state = .idle
            elapsedTime = 0
            recordingStartedAt = nil
            audioLevelHistory = AudioLevelHistory()
            audioLevels = audioLevelHistory.samples
            pendingPeakLevel = 0
            lastLevelPresentationDate = .distantPast
            completedAudioURL = nil
        }
    }

    func retry() async {
        await cancel()
        await start()
    }

    private func observeAudioEvents(
        _ events: AsyncStream<AudioRecordingEvent>
    ) {
        audioEventsTask = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case let .level(level):
                    presentAudioLevel(level)
                case .interruptionBegan:
                    if state == .recording {
                        durationTracker.pause(at: now())
                        updateElapsedTime()
                        audioLevels = audioLevelHistory.settle()
                        transition(to: .paused)
                        announce("Recording interrupted and paused")
                    }
                case .routeChanged:
                    break
                }
            }
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled else { return }
                updateElapsedTime()
            }
        }
    }

    private func updateElapsedTime() {
        elapsedTime = durationTracker.elapsed(at: now())
    }

    private func presentAudioLevel(_ level: Float) {
        pendingPeakLevel = max(pendingPeakLevel, level)
        let date = now()
        guard date.timeIntervalSince(lastLevelPresentationDate) >= 0.055
        else {
            return
        }
        audioLevels = audioLevelHistory.append(rawLevel: pendingPeakLevel)
        pendingPeakLevel = 0
        lastLevelPresentationDate = date
    }

    @discardableResult
    private func transition(to newState: MeetingCaptureState) -> Bool {
        guard machine.transition(to: newState) else { return false }
        state = machine.state
        return true
    }

    private func fail(
        _ error: MeetingCaptureError,
        cleanUp: Bool
    ) {
        transition(to: .failed(error))
        announce(error.title)
        if cleanUp {
            cancelCaptureTasks()
        }
    }

    private func failAndCleanUp(
        _ error: MeetingCaptureError
    ) async {
        fail(error, cleanUp: true)
        await audio.cancel()
        await liveActivity.end(
            phase: .failed,
            elapsedTime: elapsedTime,
            at: now()
        )
    }

    private func cancelCaptureTasks() {
        audioEventsTask?.cancel()
        timerTask?.cancel()
        audioEventsTask = nil
        timerTask = nil
    }

    private func announce(_ message: String) {
        UIAccessibility.post(
            notification: .announcement,
            argument: message
        )
    }
}
