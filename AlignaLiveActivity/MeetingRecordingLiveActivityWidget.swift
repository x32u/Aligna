import ActivityKit
import SwiftUI
import WidgetKit

@main
struct AlignaLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        MeetingRecordingLiveActivityWidget()
    }
}

struct MeetingRecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeetingRecordingAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.9))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RecordingWaveformMark(
                        phase: context.state.phase,
                        compact: false
                    )
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.meetingTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.phase.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    elapsedTime(state: context.state)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.mint)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Label(
                        "On-device meeting capture",
                        systemImage: "lock.shield.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                RecordingWaveformMark(
                    phase: context.state.phase,
                    compact: true
                )
            } compactTrailing: {
                elapsedTime(state: context.state)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.mint)
                    .frame(maxWidth: 42)
            } minimal: {
                Image(
                    systemName: context.state.phase == .paused
                        ? "pause.fill"
                        : "waveform"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.mint)
                .accessibilityLabel(context.state.phase.title)
            }
            .keylineTint(.mint)
        }
    }

    private func lockScreenView(
        context: ActivityViewContext<MeetingRecordingAttributes>
    ) -> some View {
        HStack(spacing: 14) {
            RecordingWaveformMark(
                phase: context.state.phase,
                compact: false
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.meetingTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(context.state.phase.title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer(minLength: 8)

            elapsedTime(state: context.state)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.mint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(context.attributes.meetingTitle), \(context.state.phase.title)"
        )
    }

    @ViewBuilder
    private func elapsedTime(
        state: MeetingRecordingAttributes.ContentState
    ) -> some View {
        if let timerStartDate = state.timerStartDate {
            Text(timerStartDate, style: .timer)
        } else {
            Text(state.formattedElapsedTime)
        }
    }
}

private struct RecordingWaveformMark: View {
    let phase: MeetingRecordingActivityPhase
    let compact: Bool

    private let activeHeights: [CGFloat] = [4, 9, 18, 26, 15, 8]

    var body: some View {
        HStack(spacing: compact ? 2 : 3) {
            ForEach(Array(activeHeights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(phase == .failed ? Color.red : Color.mint)
                    .frame(
                        width: compact ? 2 : 3,
                        height: phase == .paused ? 4 : (compact ? height * 0.7 : height)
                    )
            }
        }
        .frame(minWidth: compact ? 24 : 36)
        .accessibilityHidden(true)
    }
}
