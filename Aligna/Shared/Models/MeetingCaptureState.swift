import Foundation

nonisolated enum MeetingCaptureState: Equatable, Sendable {
    case idle
    case requestingPermission
    case preparingModel(progress: Double?)
    case ready
    case recording
    case paused
    case finishing
    case finalizingTranscript(progress: Double?)
    case completed
    case failed(MeetingCaptureError)

    var canStart: Bool {
        self == .idle
    }

    var canPause: Bool {
        self == .recording
    }

    var canResume: Bool {
        self == .paused
    }

    var canFinish: Bool {
        self == .recording || self == .paused
    }
}

nonisolated enum MeetingCaptureError: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case microphoneUnavailable
    case unsupportedLocale(String)
    case modelPreparationFailed
    case audioSessionFailed
    case recordingInterrupted
    case persistenceFailed
    case invalidAction
    case transcriptionFailed

    var title: String {
        switch self {
        case .microphonePermissionDenied: "Microphone access needed"
        case .microphoneUnavailable: "Microphone unavailable"
        case .unsupportedLocale: "Language unavailable"
        case .modelPreparationFailed: "Language model unavailable"
        case .audioSessionFailed: "Couldn’t start recording"
        case .recordingInterrupted: "Recording interrupted"
        case .persistenceFailed: "Couldn’t save meeting"
        case .invalidAction: "Action unavailable"
        case .transcriptionFailed: "Transcription stopped"
        }
    }

    var message: String {
        switch self {
        case .microphonePermissionDenied:
            "Allow microphone access in Settings to record meetings."
        case .microphoneUnavailable:
            "Aligna can’t find an available audio input. Check your microphone or audio route."
        case let .unsupportedLocale(identifier):
            TranscriptionLanguage.isFilipino(identifier)
                ? "Filipino transcription isn’t available on this iPhone yet."
                : "This transcription language isn’t available on this iPhone. Choose another language."
        case .modelPreparationFailed:
            "The on-device language model could not be prepared. Check storage and try again."
        case .audioSessionFailed:
            "The audio session could not be configured. Check other audio apps and try again."
        case .recordingInterrupted:
            "Audio input was interrupted. Resume when your microphone is available."
        case .persistenceFailed:
            "The recording is safe, but the meeting could not be saved."
        case .invalidAction:
            "That action is not valid in the current recording state."
        case .transcriptionFailed:
            "Live transcription encountered a problem. Your recording has been stopped safely."
        }
    }

    var recoveryTitle: String {
        switch self {
        case .microphonePermissionDenied: "Open Settings"
        default: "Try Again"
        }
    }
}

nonisolated struct MeetingCaptureStateMachine: Equatable, Sendable {
    private(set) var state: MeetingCaptureState = .idle

    @discardableResult
    mutating func transition(to newState: MeetingCaptureState) -> Bool {
        guard Self.isValidTransition(from: state, to: newState) else {
            return false
        }
        state = newState
        return true
    }

    static func isValidTransition(
        from current: MeetingCaptureState,
        to next: MeetingCaptureState
    ) -> Bool {
        if case .failed = next {
            return current != .completed
        }

        switch (current, next) {
        case (.idle, .requestingPermission),
             (.requestingPermission, .ready),
             (.requestingPermission, .preparingModel),
             (.preparingModel, .ready),
             (.ready, .recording),
             (.recording, .paused),
             (.paused, .recording),
             (.recording, .finishing),
             (.paused, .finishing),
             (.finishing, .finalizingTranscript),
             (.finalizingTranscript, .finalizingTranscript),
             (.finalizingTranscript, .completed),
             (.finishing, .completed),
             (.requestingPermission, .idle),
             (.preparingModel, .idle),
             (.ready, .idle),
             (.recording, .idle),
             (.paused, .idle),
             (.finishing, .idle),
             (.finalizingTranscript, .idle),
             (.failed, .idle),
             (.failed, .requestingPermission):
            return true
        case (.preparingModel, .preparingModel):
            return true
        default:
            return false
        }
    }
}
