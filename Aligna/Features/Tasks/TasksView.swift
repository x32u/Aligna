import SwiftUI

struct TasksView: View {
    @State private var selectedFilter: TaskFilter = .open

    /// Tasks are derived from completed meeting analysis, not stored separately.
    /// Passing the library keeps the tab live as meetings finish processing.
    private let library: MeetingLibrary?
    private let providedTasks: [ProjectTask]?

    init(library: MeetingLibrary) {
        self.library = library
        providedTasks = nil
    }

    /// Explicit task list, for previews and tests.
    init(tasks: [ProjectTask]) {
        library = nil
        providedTasks = tasks
    }

    private var tasks: [ProjectTask] {
        if let providedTasks { return providedTasks }
        guard let library else { return [] }
        return DashboardProjection.tasks(from: library.meetings)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Task filter", selection: $selectedFilter) {
                ForEach(TaskFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AlignaSpacing.medium)
            .padding(.vertical, AlignaSpacing.small)

            if filteredTasks.isEmpty {
                EmptyStateView(
                    symbol: selectedFilter == .completed ? "checkmark.circle" : "checklist",
                    title: selectedFilter == .completed ? "Nothing completed yet" : "You are all caught up",
                    message: "Tasks approved from meeting suggestions will appear here."
                )
                .padding(AlignaSpacing.large)
                .frame(maxHeight: .infinity)
            } else {
                List(filteredTasks) { task in
                    TaskRow(task: task)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AlignaColors.background)
        .navigationTitle("Tasks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {}) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter tasks")
            }
        }
    }

    private var filteredTasks: [ProjectTask] {
        switch selectedFilter {
        case .all:
            tasks
        case .open:
            tasks.filter { !$0.isCompleted }
        case .completed:
            tasks.filter(\.isCompleted)
        }
    }
}

private enum TaskFilter: String, CaseIterable, Identifiable {
    case all
    case open
    case completed

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .open: "Open"
        case .completed: "Done"
        }
    }
}

private struct TaskRow: View {
    let task: ProjectTask

    var body: some View {
        HStack(alignment: .top, spacing: AlignaSpacing.medium) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(task.isCompleted ? AlignaColors.success : AlignaColors.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AlignaSpacing.small) {
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.isCompleted)

                Label(task.assignee, systemImage: "person")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Label(
                        task.dueDateDescription(
                            style: .dateTime.month(.abbreviated).day()
                        ),
                        systemImage: "calendar"
                    )
                    .font(.caption)
                    .foregroundStyle(task.isOverdue() ? AlignaColors.danger : .secondary)

                    Spacer()
                    StatusPill(title: task.priority.title, tone: priorityTone)
                }
            }
        }
        .padding(.vertical, AlignaSpacing.extraSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var priorityTone: StatusPill.Tone {
        switch task.priority {
        case .low: .neutral
        case .medium: .accent
        case .high: .danger
        }
    }

    private var accessibilityDescription: String {
        let completion = task.isCompleted ? "Completed" : "Open"
        let due = task.dueDateDescription(
            style: .dateTime.year().month(.wide).day()
        )
        return "\(task.title), \(completion), assigned to \(task.assignee), due \(due), \(task.priority.title) priority"
    }
}

#Preview {
    NavigationStack {
        TasksView(tasks: [])
    }
}
