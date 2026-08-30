import Foundation

nonisolated struct ProjectTask: Identifiable, Hashable, Sendable {
    enum Priority: String, Hashable, Sendable {
        case low
        case medium
        case high

        var title: String {
            rawValue.capitalized
        }
    }

    let id: UUID
    let title: String
    let assignee: String
    /// Parsed deadline, when the analyzer produced an unambiguous date.
    /// `nil` means no machine-readable deadline — see `dueDateText`.
    let dueDate: Date?
    /// The deadline exactly as it appeared in the meeting ("next Friday"), kept
    /// verbatim so the UI can show what was actually said rather than a guess.
    let dueDateText: String?
    let priority: Priority
    let isCompleted: Bool
    /// The meeting this task came from, so the UI can link back to its evidence.
    let sourceMeetingID: UUID?
    let sourceMeetingTitle: String?

    init(
        id: UUID = UUID(),
        title: String,
        assignee: String,
        dueDate: Date?,
        dueDateText: String? = nil,
        priority: Priority,
        isCompleted: Bool = false,
        sourceMeetingID: UUID? = nil,
        sourceMeetingTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.assignee = assignee
        self.dueDate = dueDate
        self.dueDateText = dueDateText
        self.priority = priority
        self.isCompleted = isCompleted
        self.sourceMeetingID = sourceMeetingID
        self.sourceMeetingTitle = sourceMeetingTitle
    }

    func isOverdue(asOf date: Date = .now) -> Bool {
        guard let dueDate else { return false }
        return !isCompleted && dueDate < date
    }

    /// What to show for the deadline: the parsed date when available, otherwise
    /// the meeting's own wording, otherwise an explicit absence.
    func dueDateDescription(
        style: Date.FormatStyle = .dateTime.month(.abbreviated).day()
    ) -> String {
        if let dueDate {
            return dueDate.formatted(style)
        }
        if let dueDateText, !dueDateText.isEmpty {
            return dueDateText
        }
        return "No deadline"
    }

    var assigneeInitials: String {
        assignee
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
            .joined()
    }
}
