import Foundation

nonisolated struct DashboardViewModel {
    let snapshot: DashboardSnapshot
    let now: Date
    let calendar: Calendar

    init(
        snapshot: DashboardSnapshot,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.snapshot = snapshot
        self.now = now
        self.calendar = calendar
    }

    /// Empty dashboard, for a signed-out or freshly-installed state. Shows real
    /// empty states rather than fabricated sample content.
    static func empty(
        currentUser: TeamMember = TeamMember(name: ""),
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> DashboardViewModel {
        DashboardViewModel(
            snapshot: DashboardSnapshot(
                currentUser: currentUser,
                meetings: [],
                tasks: [],
                pendingReviews: []
            ),
            now: now,
            calendar: calendar
        )
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
        return firstName.isEmpty
            ? salutation
            : "\(salutation), \(firstName)"
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

    /// Tasks with a parseable deadline inside the next week.
    ///
    /// Action items whose deadline is only relative wording ("next Friday") have
    /// no comparable date and are deliberately excluded rather than guessed into
    /// a window; they remain visible in the Tasks tab.
    var tasksDueSoon: [ProjectTask] {
        let cutoff = calendar.date(byAdding: .day, value: 7, to: now) ?? now

        return Array(
            snapshot.tasks
                .compactMap { task -> (task: ProjectTask, due: Date)? in
                    guard let due = task.dueDate else { return nil }
                    return (task, due)
                }
                .filter {
                    !$0.task.isCompleted
                        && $0.due >= now
                        && $0.due <= cutoff
                }
                .sorted { $0.due < $1.due }
                .map(\.task)
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

    func confidenceText(for review: MeetingReview) -> String? {
        review.confidence.map {
            $0.formatted(.percent.precision(.fractionLength(0)))
                + " confidence"
        }
    }
}
