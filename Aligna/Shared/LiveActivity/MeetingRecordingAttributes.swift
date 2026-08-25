import ActivityKit
import Foundation

nonisolated enum MeetingRecordingActivityPhase: String, Codable, Hashable, Sendable {
    case recording
    case paused
    case finishing
    case completed
    case failed

    var title: String {
        switch self {
        case .recording:
            "Recording"
        case .paused:
            "Paused"
        case .finishing:
            "Saving"
        case .completed:
            "Saved"
        case .failed:
            "Recording ended"
        }
    }
}

nonisolated struct MeetingRecordingAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        let phase: MeetingRecordingActivityPhase
        let elapsedSeconds: Int
        let timerStartDate: Date?

        init(
            phase: MeetingRecordingActivityPhase,
            elapsedTime: TimeInterval,
            referenceDate: Date
        ) {
            self.phase = phase
            elapsedSeconds = max(0, Int(elapsedTime.rounded(.down)))
            timerStartDate = phase == .recording
                ? referenceDate.addingTimeInterval(-elapsedTime)
                : nil
        }

        var formattedElapsedTime: String {
            let hours = elapsedSeconds / 3_600
            let minutes = (elapsedSeconds % 3_600) / 60
            let seconds = elapsedSeconds % 60

            if hours > 0 {
                return String(
                    format: "%d:%02d:%02d",
                    hours,
                    minutes,
                    seconds
                )
            }

            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    let meetingTitle: String
}
