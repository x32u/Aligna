import Foundation

struct DashboardViewModel {
    let snapshot: DashboardSnapshot
    let now: Date
    let calendar: Calendar

    init(
        snapshot: DashboardSnapshot? = nil,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.snapshot = snapshot ?? DashboardMockData.make(
            referenceDate: now,
            calendar: calendar
        )
        self.now = now
        self.calendar = calendar
    }

    var greeting: String {
        let hour = calendar.component(.hour, from: now)
        let salutation: String

        switch hour {
        case 5..<12:
            salutation = "Good morning"
        case 12..<17:
            salutation = "Good afternoon"
        default:
            salutation = "Good evening"
        }

        let firstName = snapshot.currentUser.name.split(separator: " ").first.map(String.init)
            ?? snapshot.currentUser.name
        return "\(salutation), \(firstName)"
    }

    var upcomingMeeting: Meeting? {
        snapshot.meetings
            .filter { $0.scheduledAt >= now && $0.status == .scheduled }
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .first
    }

    var recentMeetings: [Meeting] {
        Array(
            snapshot.meetings
                .filter { $0.scheduledAt < now && $0.status != .scheduled }
                .sorted { $0.scheduledAt > $1.scheduledAt }
                .prefix(3)
        )
    }

    var tasksDueSoon: [ProjectTask] {
        let cutoff = calendar.date(byAdding: .day, value: 7, to: now) ?? now

        return Array(
            snapshot.tasks
                .filter {
                    !$0.isCompleted
                        && $0.dueDate >= now
                        && $0.dueDate <= cutoff
                }
                .sorted { $0.dueDate < $1.dueDate }
                .prefix(4)
        )
    }

    var featuredReview: MeetingReview? {
        snapshot.pendingReviews.first
    }

    var metrics: [DashboardMetric] {
        [
            DashboardMetric(
                kind: .meetingsThisWeek,
                value: snapshot.meetings.filter {
                    calendar.isDate($0.scheduledAt, equalTo: now, toGranularity: .weekOfYear)
                }.count
            ),
            DashboardMetric(
                kind: .openActionItems,
                value: snapshot.tasks.filter { !$0.isCompleted }.count
            ),
            DashboardMetric(
                kind: .pendingAIReviews,
                value: snapshot.pendingReviews.count
            )
        ]
    }

    func confidenceText(for review: MeetingReview) -> String {
        review.confidence.formatted(.percent.precision(.fractionLength(0))) + " confidence"
    }
}
