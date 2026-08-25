import Foundation

struct MeetingReview: Identifiable, Hashable, Sendable {
    enum Status: String, Hashable, Sendable {
        case awaitingReview

        var title: String {
            switch self {
            case .awaitingReview:
                "Awaiting review"
            }
        }
    }

    let id: UUID
    let meetingTitle: String
    let summary: String
    let actionItemCount: Int
    let confidence: Double
    let status: Status

    init(
        id: UUID = UUID(),
        meetingTitle: String,
        summary: String,
        actionItemCount: Int,
        confidence: Double,
        status: Status = .awaitingReview
    ) {
        self.id = id
        self.meetingTitle = meetingTitle
        self.summary = summary
        self.actionItemCount = actionItemCount
        self.confidence = min(max(confidence, 0), 1)
        self.status = status
    }
}
