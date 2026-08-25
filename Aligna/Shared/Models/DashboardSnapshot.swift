import Foundation

struct DashboardSnapshot: Sendable {
    let currentUser: TeamMember
    let meetings: [Meeting]
    let tasks: [ProjectTask]
    let pendingReviews: [MeetingReview]
}

struct DashboardMetric: Identifiable, Equatable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case meetingsThisWeek
        case openActionItems
        case pendingAIReviews
    }

    let kind: Kind
    let value: Int

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .meetingsThisWeek:
            "Meetings this week"
        case .openActionItems:
            "Open action items"
        case .pendingAIReviews:
            "Pending AI reviews"
        }
    }

    var symbol: String {
        switch kind {
        case .meetingsThisWeek:
            "calendar"
        case .openActionItems:
            "checklist"
        case .pendingAIReviews:
            "sparkles"
        }
    }
}
