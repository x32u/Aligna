import SwiftUI

struct MeetingReviewDetailView: View {
    let review: MeetingReview
    /// `nil` when the analyzer reported no assignment confidence. Absent
    /// confidence is shown as absent rather than as an invented score.
    let confidenceText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlignaSpacing.large) {
                HStack {
                    StatusBadge(
                        title: review.status.title,
                        systemImage: "person.crop.circle.badge.checkmark",
                        tone: .warning
                    )

                    Spacer()

                    if let confidenceText {
                        StatusBadge(
                            title: confidenceText,
                            tone: .accent
                        )
                    }
                }

                AlignaCard {
                    VStack(alignment: .leading, spacing: AlignaSpacing.medium) {
                        Label("AI-generated summary", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(AlignaColors.label)

                        Text(review.summary)
                            .font(.body)
                            .foregroundStyle(AlignaColors.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                AlignaCard {
                    HStack(spacing: AlignaSpacing.medium) {
                        Image(systemName: "checklist")
                            .font(.title3)
                            .foregroundStyle(AlignaColors.accent)
                            .frame(
                                width: AlignaSize.standardIcon,
                                height: AlignaSize.standardIcon
                            )
                            .background(
                                AlignaColors.accent.opacity(0.11),
                                in: RoundedRectangle(cornerRadius: AlignaRadius.small)
                            )
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: AlignaSpacing.extraSmall) {
                            Text("\(review.actionItemCount) suggested action items")
                                .font(.headline)
                            Text("Assignees and deadlines will be reviewed here before becoming official.")
                                .font(.subheadline)
                                .foregroundStyle(AlignaColors.secondaryLabel)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                EmptyStateView(
                    symbol: "checkmark.shield",
                    title: "Human approval comes next",
                    message: "Approve, edit, and dismiss controls will be implemented with the AI review workflow. This screen is intentionally read-only for now."
                )
                .alignaCard()
            }
            .padding(AlignaSpacing.medium)
        }
        .background(AlignaColors.background)
        .navigationTitle(review.meetingTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Review detail") {
    let review = MeetingReview(
        meetingTitle: "Launch readiness review",
        summary: "The team aligned on beta scope and identified two launch risks that still need owners.",
        actionItemCount: 5,
        confidence: 0.92
    )

    NavigationStack {
        MeetingReviewDetailView(
            review: review,
            confidenceText: "92% confidence"
        )
    }
}
