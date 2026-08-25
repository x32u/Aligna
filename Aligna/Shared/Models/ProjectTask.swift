import Foundation

struct ProjectTask: Identifiable, Hashable, Sendable {
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
    let dueDate: Date
    let priority: Priority
    let isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        assignee: String,
        dueDate: Date,
        priority: Priority,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.assignee = assignee
        self.dueDate = dueDate
        self.priority = priority
        self.isCompleted = isCompleted
    }

    func isOverdue(asOf date: Date = .now) -> Bool {
        !isCompleted && dueDate < date
    }

    var assigneeInitials: String {
        assignee
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
            .joined()
    }
}
