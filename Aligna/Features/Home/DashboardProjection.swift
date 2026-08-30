import Foundation

/// Projects real, persisted meetings into the dashboard's view model shape.
///
/// The dashboard and Tasks tab previously rendered `DashboardMockData` — invented
/// meetings, tasks, and reviews. Everything here is derived from data the
/// processing pipeline actually produced: `Meeting.analysis` carries the summary,
/// decisions, and action items, so tasks and pending reviews are projections of
/// real analysis rather than fixtures.
nonisolated enum DashboardProjection {
    /// Builds a snapshot from persisted meetings.
    ///
    /// - Parameters:
    ///   - meetings: Every meeting known locally.
    ///   - currentUser: The signed-in user, used for the greeting.
    static func snapshot(
        meetings: [Meeting],
        currentUser: TeamMember
    ) -> DashboardSnapshot {
        DashboardSnapshot(
            currentUser: currentUser,
            meetings: meetings,
            tasks: tasks(from: meetings),
            pendingReviews: pendingReviews(from: meetings)
        )
    }

    /// Action items extracted from completed analysis become tasks.
    ///
    /// The analyzer deliberately keeps `dueDate` in the transcript's own wording
    /// ("next Friday"), so it is carried through as text and only surfaced as a
    /// real `Date` when it parses unambiguously. A task with no parseable date is
    /// valid — inventing one would be fabricating meeting content.
    static func tasks(from meetings: [Meeting]) -> [ProjectTask] {
        meetings
            .compactMap { meeting -> [ProjectTask]? in
                guard let analysis = meeting.analysis else { return nil }
                return analysis.actionItems.map { item in
                    ProjectTask(
                        id: item.id,
                        title: item.task,
                        assignee: item.assigneeDisplayName
                            ?? item.assignee
                            ?? "Unassigned",
                        dueDate: parsedDueDate(item.dueDate),
                        dueDateText: item.dueDate,
                        priority: priority(for: item),
                        isCompleted: false,
                        sourceMeetingID: meeting.id,
                        sourceMeetingTitle: analysis.generatedTitle
                    )
                }
            }
            .flatMap { $0 }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (left?, right?):
                    left < right
                case (nil, _?):
                    false
                case (_?, nil):
                    true
                case (nil, nil):
                    lhs.title < rhs.title
                }
            }
    }

    /// Meetings whose analysis has landed but the user has not reviewed yet.
    static func pendingReviews(from meetings: [Meeting]) -> [MeetingReview] {
        meetings
            .filter { $0.status == .needsReview }
            .compactMap { meeting in
                guard let analysis = meeting.analysis else { return nil }
                return MeetingReview(
                    meetingTitle: analysis.generatedTitle,
                    summary: analysis.summary,
                    actionItemCount: analysis.actionItems.count,
                    // Confidence is the mean assignment confidence the analyzer
                    // reported. Absent confidence is reported as absent rather
                    // than as a fabricated score.
                    confidence: averageConfidence(analysis.actionItems),
                    sourceMeetingID: meeting.id
                )
            }
            .sorted { $0.meetingTitle < $1.meetingTitle }
    }

    /// An action item with an explicit deadline is treated as higher priority
    /// than one without. The analyzer does not emit a priority field, so this is
    /// a presentation-level ordering hint, not invented meeting content.
    private static func priority(
        for item: MeetingActionItem
    ) -> ProjectTask.Priority {
        if item.dueDate != nil {
            return .high
        }
        if item.assigneeUserID != nil || item.assignee != nil {
            return .medium
        }
        return .low
    }

    private static func averageConfidence(
        _ items: [MeetingActionItem]
    ) -> Double? {
        let scores = items.compactMap(\.assignmentConfidence).map(Double.init)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    /// Parses only unambiguous ISO-8601-style dates. Relative wording such as
    /// "next Friday" stays text: guessing a calendar date from it would put a
    /// deadline in the UI that nobody agreed to.
    static func parsedDueDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = try? Date(
            trimmed,
            strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        ) {
            return date
        }
        if let date = try? Date(
            trimmed,
            strategy: Date.ISO8601FormatStyle.iso8601Date(timeZone: .current)
        ) {
            return date
        }
        return nil
    }
}
