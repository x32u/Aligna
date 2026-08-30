import Foundation

nonisolated struct MeetingReview: Identifiable, Hashable, Sendable {
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
    /// Mean assignment confidence the analyzer reported, when it reported any.
    /// `nil` means unknown — distinct from a low score, and never fabricated.
    let confidence: Double?
    let status: Status
    /// The meeting this review summarizes, so the UI can open it.
    let sourceMeetingID: UUID?

    init(
        id: UUID = UUID(),
        meetingTitle: String,
        summary: String,
        actionItemCount: Int,
        confidence: Double?,
        status: Status = .awaitingReview,
        sourceMeetingID: UUID? = nil
    ) {
        self.id = id
        self.meetingTitle = meetingTitle
        self.summary = summary
        self.actionItemCount = actionItemCount
        self.confidence = confidence.map { min(max($0, 0), 1) }
        self.status = status
        self.sourceMeetingID = sourceMeetingID
    }
}
