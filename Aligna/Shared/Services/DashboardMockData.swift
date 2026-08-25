import Foundation

enum DashboardMockData {
    static func make(
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> DashboardSnapshot {
        let john = TeamMember(name: "John Cruz")
        let maya = TeamMember(name: "Maya Chen")
        let liam = TeamMember(name: "Liam Rivera")
        let priya = TeamMember(name: "Priya Shah")
        let noah = TeamMember(name: "Noah Williams")
        let elena = TeamMember(name: "Elena Garcia")

        let meetings = [
            Meeting(
                title: "Product & Design Weekly",
                projectName: "Aligna Mobile Launch",
                scheduledAt: date(from: referenceDate, dayOffset: 1, hour: 10, calendar: calendar),
                durationMinutes: 45,
                participants: [john, maya, liam, priya],
                status: .scheduled
            ),
            Meeting(
                title: "Launch Readiness Review",
                projectName: "Aligna Mobile Launch",
                scheduledAt: date(from: referenceDate, dayOffset: 0, hour: 14, calendar: calendar),
                durationMinutes: 38,
                participants: [john, maya, noah, elena],
                status: .needsReview
            ),
            Meeting(
                title: "Customer Discovery Debrief",
                projectName: "Research Sprint",
                scheduledAt: date(from: referenceDate, dayOffset: -1, hour: 16, calendar: calendar),
                durationMinutes: 51,
                participants: [john, priya, elena],
                status: .complete
            ),
            Meeting(
                title: "Engineering Stand-up",
                projectName: "Aligna Mobile Launch",
                scheduledAt: date(from: referenceDate, dayOffset: -2, hour: 9, calendar: calendar),
                durationMinutes: 24,
                participants: [john, liam, noah],
                status: .processing
            ),
            Meeting(
                title: "Q3 Roadmap Alignment",
                projectName: "Product Strategy",
                scheduledAt: date(from: referenceDate, dayOffset: -3, hour: 11, calendar: calendar),
                durationMinutes: 63,
                participants: [john, maya, liam, priya, noah],
                status: .complete
            ),
            Meeting(
                title: "Content Workflow Review",
                projectName: "Team Operations",
                scheduledAt: date(from: referenceDate, dayOffset: -5, hour: 13, calendar: calendar),
                durationMinutes: 36,
                participants: [john, maya, elena],
                status: .needsReview
            )
        ]

        let tasks = [
            ProjectTask(
                title: "Finalize onboarding consent copy",
                assignee: maya.name,
                dueDate: date(from: referenceDate, dayOffset: 1, hour: 17, calendar: calendar),
                priority: .high
            ),
            ProjectTask(
                title: "Share recording retention policy",
                assignee: liam.name,
                dueDate: date(from: referenceDate, dayOffset: 2, hour: 12, calendar: calendar),
                priority: .medium
            ),
            ProjectTask(
                title: "Prepare App Store preview notes",
                assignee: priya.name,
                dueDate: date(from: referenceDate, dayOffset: 3, hour: 15, calendar: calendar),
                priority: .medium
            ),
            ProjectTask(
                title: "Validate accessibility labels",
                assignee: noah.name,
                dueDate: date(from: referenceDate, dayOffset: 5, hour: 17, calendar: calendar),
                priority: .high
            ),
            ProjectTask(
                title: "Confirm beta feedback owners",
                assignee: elena.name,
                dueDate: date(from: referenceDate, dayOffset: 8, hour: 11, calendar: calendar),
                priority: .low
            ),
            ProjectTask(
                title: "Update launch risk register",
                assignee: john.name,
                dueDate: date(from: referenceDate, dayOffset: 10, hour: 16, calendar: calendar),
                priority: .medium
            ),
            ProjectTask(
                title: "Schedule stakeholder demo",
                assignee: maya.name,
                dueDate: date(from: referenceDate, dayOffset: 12, hour: 14, calendar: calendar),
                priority: .low
            ),
            ProjectTask(
                title: "Publish sprint recap",
                assignee: liam.name,
                dueDate: date(from: referenceDate, dayOffset: -1, hour: 17, calendar: calendar),
                priority: .low,
                isCompleted: true
            )
        ]

        let reviews = [
            MeetingReview(
                meetingTitle: "Launch Readiness Review",
                summary: "The team aligned on beta scope, clarified the consent flow, and identified two launch risks that need owners.",
                actionItemCount: 5,
                confidence: 0.92
            ),
            MeetingReview(
                meetingTitle: "Content Workflow Review",
                summary: "The content team proposed a simpler approval path and flagged two handoff delays.",
                actionItemCount: 3,
                confidence: 0.87
            )
        ]

        return DashboardSnapshot(
            currentUser: john,
            meetings: meetings,
            tasks: tasks,
            pendingReviews: reviews
        )
    }

    private static func date(
        from referenceDate: Date,
        dayOffset: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        let shiftedDate = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: referenceDate
        ) ?? referenceDate

        return calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: shiftedDate
        ) ?? shiftedDate
    }
}
