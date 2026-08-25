import ActivityKit
import Foundation

protocol MeetingRecordingLiveActivityControlling: Sendable {
    func start(
        meetingTitle: String,
        elapsedTime: TimeInterval,
        at date: Date
    ) async
    func update(
        phase: MeetingRecordingActivityPhase,
        elapsedTime: TimeInterval,
        at date: Date
    ) async
    func end(
        phase: MeetingRecordingActivityPhase,
        elapsedTime: TimeInterval,
        at date: Date
    ) async
}

actor MeetingRecordingLiveActivityController:
    MeetingRecordingLiveActivityControlling {
    private var activityID: String?

    func start(
        meetingTitle: String,
        elapsedTime: TimeInterval,
        at date: Date
    ) async {
        guard activityID == nil,
              ActivityAuthorizationInfo().areActivitiesEnabled
        else {
            return
        }

        for activity in Activity<MeetingRecordingAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let attributes = MeetingRecordingAttributes(
            meetingTitle: meetingTitle
        )
        let state = MeetingRecordingAttributes.ContentState(
            phase: .recording,
            elapsedTime: elapsedTime,
            referenceDate: date
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: state,
                    staleDate: nil
                )
            )
            activityID = activity.id
        } catch {
            activityID = nil
        }
    }

    func update(
        phase: MeetingRecordingActivityPhase,
        elapsedTime: TimeInterval,
        at date: Date
    ) async {
        guard let activity = currentActivity else { return }

        let state = MeetingRecordingAttributes.ContentState(
            phase: phase,
            elapsedTime: elapsedTime,
            referenceDate: date
        )
        await activity.update(
            ActivityContent(state: state, staleDate: nil)
        )
    }

    func end(
        phase: MeetingRecordingActivityPhase,
        elapsedTime: TimeInterval,
        at date: Date
    ) async {
        guard let activity = currentActivity else { return }

        let state = MeetingRecordingAttributes.ContentState(
            phase: phase,
            elapsedTime: elapsedTime,
            referenceDate: date
        )
        let dismissalPolicy: ActivityUIDismissalPolicy =
            phase == .completed
                ? .after(date.addingTimeInterval(4))
                : .immediate

        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: dismissalPolicy
        )
        activityID = nil
    }

    private var currentActivity: Activity<MeetingRecordingAttributes>? {
        guard let activityID else { return nil }
        return Activity<MeetingRecordingAttributes>.activities.first {
            $0.id == activityID
        }
    }
}

struct NoopMeetingRecordingLiveActivityController:
    MeetingRecordingLiveActivityControlling {
    func start(
        meetingTitle: String,
        elapsedTime: TimeInterval,
        at date: Date
    ) async {}

    func update(
        phase: MeetingRecordingActivityPhase,
        elapsedTime: TimeInterval,
        at date: Date
    ) async {}

    func end(
        phase: MeetingRecordingActivityPhase,
        elapsedTime: TimeInterval,
        at date: Date
    ) async {}
}
