import SwiftUI

struct MeetingRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: AlignaSpacing.small) {
            HStack(alignment: .top, spacing: AlignaSpacing.compact) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(
                        width: AlignaSize.standardIcon,
                        height: AlignaSize.standardIcon
                    )
                    .background(
                        tint.opacity(0.12),
                        in: RoundedRectangle(
                            cornerRadius: AlignaRadius.small
                        )
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AlignaSpacing.extraSmall) {
                    Text(meeting.title)
                        .font(.headline)
                        .foregroundStyle(AlignaColors.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    Text(meeting.projectName)
                        .font(.subheadline)
                        .foregroundStyle(AlignaColors.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !dynamicTypeSize.isAccessibilitySize {
                    StatusBadge(
                        title: rowStatusTitle,
                        systemImage: badgeSymbol,
                        tone: tone
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                StatusBadge(
                    title: rowStatusTitle,
                    systemImage: badgeSymbol,
                    tone: tone
                )
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, AlignaSize.standardIcon + AlignaSpacing.compact)
            }

            metadata
                .meetingMetadataStyle()
                .padding(
                    .leading,
                    dynamicTypeSize.isAccessibilitySize
                        ? AlignaSpacing.zero
                        : AlignaSize.standardIcon + AlignaSpacing.compact
                )
        }
        .padding(.vertical, AlignaSpacing.small)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Opens meeting details")
    }

    @ViewBuilder
    private var metadata: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AlignaSpacing.small) {
                metadataDate

                if let durationMinutes = meeting.durationMinutes {
                    metadataDuration(durationMinutes)
                }

                metadataParticipants

                if meeting.ownerUserID != nil {
                    metadataSyncState
                }
            }
        } else {
            HStack(spacing: AlignaSpacing.medium) {
                metadataDate

                if let durationMinutes = meeting.durationMinutes {
                    metadataDuration(durationMinutes)
                }

                metadataParticipants

                if meeting.ownerUserID != nil {
                    metadataSyncState
                }
            }
        }
    }

    private var metadataDate: some View {
        Label(
            meeting.scheduledAt.formatted(
                date: .abbreviated,
                time: .omitted
            ),
            systemImage: "calendar"
        )
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func metadataDuration(_ minutes: Int) -> some View {
        Label("\(minutes) min", systemImage: "clock")
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var metadataParticipants: some View {
        Label(
            meeting.attendeeCount == 0
                ? "None"
                : "\(meeting.attendeeCount)",
            systemImage: "person.2"
        )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(
                meeting.attendeeCount == 0
                    ? "No participants added"
                    : "\(meeting.attendeeCount) participants"
            )
    }

    private var metadataSyncState: some View {
        Label(
            meeting.syncState.title,
            systemImage: syncSymbol
        )
        .lineLimit(1)
        .foregroundStyle(
            meeting.syncState == .failed
                ? AlignaColors.warning
                : AlignaColors.secondaryLabel
        )
    }

    private var syncSymbol: String {
        switch meeting.syncState {
        case .local: "iphone"
        case .syncing: "arrow.triangle.2.circlepath"
        case .synced: "checkmark.icloud"
        case .failed: "exclamationmark.icloud"
        }
    }

    private var symbol: String {
        switch meeting.status {
        case .scheduled: return "calendar"
        case .processing: return "waveform"
        case .needsReview: return "sparkles"
        case .complete: return "checkmark"
        }
    }

    private var badgeSymbol: String? {
        if meeting.processingStatus == .failed {
            return "exclamationmark.arrow.triangle.2.circlepath"
        }
        if meeting.processingStatus.isProcessing {
            return "clock"
        }
        switch meeting.status {
        case .scheduled: return "calendar"
        case .processing: return "clock"
        case .needsReview: return "sparkles"
        case .complete: return "checkmark"
        }
    }

    private var tint: Color {
        if meeting.processingStatus == .failed {
            return AlignaColors.warning
        }
        switch meeting.status {
        case .scheduled: return AlignaColors.accent
        case .processing: return AlignaColors.accent
        case .needsReview: return AlignaColors.warning
        case .complete: return AlignaColors.success
        }
    }

    private var tone: StatusBadge.Tone {
        if meeting.processingStatus == .failed {
            return .warning
        }
        switch meeting.status {
        case .scheduled: return .accent
        case .processing: return .accent
        case .needsReview: return .warning
        case .complete: return .success
        }
    }

    private var accessibilityDescription: String {
        var parts = [
            meeting.title,
            meeting.projectName,
            rowStatusTitle,
            meeting.scheduledAt.formatted(date: .long, time: .shortened),
            meeting.attendeeCount == 0
                ? "No participants added"
                : "\(meeting.attendeeCount) participants"
        ]

        if let durationMinutes = meeting.durationMinutes {
            parts.append("\(durationMinutes) minutes")
        }
        if meeting.ownerUserID != nil {
            parts.append(meeting.syncState.title)
        }

        return parts.joined(separator: ", ")
    }

    private var rowStatusTitle: String {
        switch meeting.processingStatus {
        case .failed:
            "Needs processing"
        case .queued, .uploading, .transcribing, .preparingSpeakers,
             .diarizing, .matchingSpeakers, .mergingTranscript, .analyzing:
            meeting.processingStatus.customerTitle
        case .complete:
            meeting.status.title
        }
    }
}

private extension View {
    func meetingMetadataStyle() -> some View {
        font(.caption)
            .foregroundStyle(AlignaColors.secondaryLabel)
            .labelStyle(.titleAndIcon)
    }
}

private extension Meeting {
    /// Preview fixture, local to this file so no shared sample-data type can be
    /// reached from production code.
    static var previewSample: Meeting {
        Meeting(
            title: "Launch readiness review",
            projectName: "Aligna Mobile Launch",
            scheduledAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationSeconds: 38 * 60,
            participants: [
                TeamMember(name: "Maya Chen"),
                TeamMember(name: "Liam Rivera"),
            ],
            status: .needsReview
        )
    }
}

#Preview("Meeting row") {
    MeetingRow(meeting: .previewSample)
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Meeting row dark") {
    MeetingRow(meeting: .previewSample)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Meeting row accessibility") {
    MeetingRow(meeting: .previewSample)
        .padding()
        .dynamicTypeSize(.accessibility2)
}
