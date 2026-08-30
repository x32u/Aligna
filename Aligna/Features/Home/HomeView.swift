import SwiftUI

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isPresentingMeetingCapture = false
    @State private var isPresentingNotifications = false

    private let viewModel: DashboardViewModel
    private let meetingLibrary: MeetingLibrary
    private let meetingContext: MeetingCreationContext?
    private let captureDependencies: MeetingCaptureDependencies

    init(
        viewModel: DashboardViewModel = .empty(),
        meetingLibrary: MeetingLibrary? = nil,
        meetingContext: MeetingCreationContext? = nil,
        captureDependencies: MeetingCaptureDependencies? = nil
    ) {
        self.viewModel = viewModel
        self.meetingLibrary = meetingLibrary ?? MeetingLibrary(
            repository: InMemoryMeetingRepository()
        )
        self.meetingContext = meetingContext
        self.captureDependencies = captureDependencies ?? .app(
            ownerUserID: meetingContext?.organizerUserID
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AlignaSpacing.section) {
                dashboardHeader
                recordingHero
                upcomingMeetingSection
                overviewSection
                reviewSection
                recentMeetingsSection
                tasksDueSoonSection
            }
            .padding(.horizontal, AlignaSpacing.medium)
            .padding(.top, AlignaSpacing.small)
            .padding(.bottom, AlignaSpacing.extraLarge)
        }
        .scrollIndicators(.hidden)
        .background(AlignaColors.background)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Meeting.self) { meeting in
            MeetingDetailView(
                meeting: meeting,
                library: meetingLibrary,
                dependencies: captureDependencies
            )
        }
        .navigationDestination(for: MeetingReview.self) { review in
            MeetingReviewDetailView(
                review: review,
                confidenceText: viewModel.confidenceText(for: review)
            )
        }
        .sheet(isPresented: $isPresentingMeetingCapture) {
            MeetingCaptureFlowView(
                library: meetingLibrary,
                context: meetingContext,
                dependencies: captureDependencies
            )
        }
        .sheet(isPresented: $isPresentingNotifications) {
            NotificationsPlaceholderSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: AlignaSpacing.compact) {
            VStack(alignment: .leading, spacing: AlignaSpacing.extraSmall) {
                Text(viewModel.greeting)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AlignaColors.label)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Here’s what needs your attention.")
                    .font(.subheadline)
                    .foregroundStyle(AlignaColors.secondaryLabel)
            }

            Spacer(minLength: AlignaSpacing.small)

            Button {
                isPresentingNotifications = true
            } label: {
                Image(systemName: "bell")
                    .font(.headline)
                    .frame(
                        width: AlignaSize.minimumTouchTarget,
                        height: AlignaSize.minimumTouchTarget
                    )
                    .background(
                        AlignaColors.elevatedSurface,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(AlignaColors.label)
            .accessibilityLabel("Notifications")
            .accessibilityHint("Shows notification updates")

            AvatarView(
                name: viewModel.snapshot.currentUser.name,
                initials: viewModel.snapshot.currentUser.initials,
                size: AlignaSize.minimumTouchTarget
            )
        }
    }

    private var recordingHero: some View {
        AlignaCard(padding: AlignaSpacing.roomy) {
            VStack(alignment: .leading, spacing: AlignaSpacing.roomy) {
                HStack(alignment: .top, spacing: AlignaSpacing.medium) {
                    Image(systemName: "waveform")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AlignaColors.accent)
                        .frame(
                            width: AlignaSize.avatarLarge,
                            height: AlignaSize.avatarLarge
                        )
                        .background(
                            AlignaColors.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: AlignaRadius.medium)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: AlignaSpacing.extraSmall) {
                        Text("Ready to capture your next meeting?")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AlignaColors.label)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Record the conversation now. Aligna will organize the important details later.")
                            .font(.subheadline)
                            .foregroundStyle(AlignaColors.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                PrimaryActionButton(
                    title: "Start meeting",
                    systemImage: "mic.fill"
                ) {
                    isPresentingMeetingCapture = true
                }
                .accessibilityHint("Starts recording immediately")
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var upcomingMeetingSection: some View {
        if let meeting = viewModel.upcomingMeeting {
            VStack(alignment: .leading, spacing: AlignaSpacing.compact) {
                SectionHeader(
                    title: "Upcoming meeting",
                    subtitle: "Next on your schedule"
                )

                AlignaCard {
                    VStack(alignment: .leading, spacing: AlignaSpacing.medium) {
                        HStack(alignment: .top, spacing: AlignaSpacing.medium) {
                            Image(systemName: "calendar")
                                .font(.headline)
                                .foregroundStyle(AlignaColors.accent)
                                .frame(
                                    width: AlignaSize.standardIcon,
                                    height: AlignaSize.standardIcon
                                )
                                .background(
                                    AlignaColors.accent.opacity(0.11),
                                    in: RoundedRectangle(cornerRadius: AlignaRadius.small)
                                )
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: AlignaSpacing.extraSmall) {
                                Text(meeting.title)
                                    .font(.headline)
                                    .foregroundStyle(AlignaColors.label)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(meeting.projectName)
                                    .font(.subheadline)
                                    .foregroundStyle(AlignaColors.secondaryLabel)
                            }

                            Spacer(minLength: AlignaSpacing.small)
                            StatusBadge(title: "Next", tone: .accent)
                        }

                        Label(
                            meeting.scheduledAt.formatted(
                                .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()
                            ),
                            systemImage: "clock"
                        )
                        .font(.subheadline)
                        .foregroundStyle(AlignaColors.secondaryLabel)

                        HStack(spacing: AlignaSpacing.medium) {
                            participantStack(for: meeting)

                            Text(participantDescription(for: meeting))
                                .font(.caption)
                                .foregroundStyle(AlignaColors.secondaryLabel)
                                .lineLimit(1)

                            Spacer(minLength: AlignaSpacing.extraSmall)

                            NavigationLink(value: meeting) {
                                Label("View details", systemImage: "chevron.right")
                            }
                            .labelStyle(.titleAndIcon)
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .frame(minHeight: AlignaSize.minimumTouchTarget)
                            .accessibilityHint("Opens the upcoming meeting")
                        }
                    }
                }
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: AlignaSpacing.compact) {
            SectionHeader(
                title: "Overview",
                subtitle: "A quick look at your workspace"
            )

            LazyVGrid(columns: metricColumns, spacing: AlignaSpacing.compact) {
                ForEach(viewModel.metrics) { metric in
                    MetricCard(
                        symbol: metric.symbol,
                        value: metric.value.formatted(),
                        label: metric.title,
                        tint: metricTint(for: metric.kind)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if let review = viewModel.featuredReview {
            VStack(alignment: .leading, spacing: AlignaSpacing.compact) {
                SectionHeader(
                    title: "Needs your review",
                    subtitle: "AI suggestions stay private until you approve them"
                )

                NavigationLink(value: review) {
                    AlignaCard {
                        VStack(alignment: .leading, spacing: AlignaSpacing.medium) {
                            HStack(alignment: .top, spacing: AlignaSpacing.medium) {
                                Image(systemName: "sparkles")
                                    .font(.headline)
                                    .foregroundStyle(AlignaColors.warning)
                                    .frame(
                                        width: AlignaSize.standardIcon,
                                        height: AlignaSize.standardIcon
                                    )
                                    .background(
                                        AlignaColors.warning.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: AlignaRadius.small)
                                    )
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: AlignaSpacing.extraSmall) {
                                    Text(review.meetingTitle)
                                        .font(.headline)
                                        .foregroundStyle(AlignaColors.label)

                                    StatusBadge(
                                        title: review.status.title,
                                        systemImage: "person.crop.circle.badge.checkmark",
                                        tone: .warning
                                    )
                                }

                                Spacer(minLength: AlignaSpacing.small)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AlignaColors.tertiaryLabel)
                                    .accessibilityHidden(true)
                            }

                            Text(review.summary)
                                .font(.subheadline)
                                .foregroundStyle(AlignaColors.secondaryLabel)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)

                            Divider()

                            HStack(spacing: AlignaSpacing.compact) {
                                Label(
                                    "\(review.actionItemCount) action items",
                                    systemImage: "checklist"
                                )

                                Spacer()

                                if let confidence = viewModel
                                    .confidenceText(for: review) {
                                    StatusBadge(
                                        title: confidence,
                                        tone: .accent
                                    )
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(AlignaColors.secondaryLabel)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens the AI review details")
            }
        }
    }

    private var recentMeetingsSection: some View {
        VStack(alignment: .leading, spacing: AlignaSpacing.compact) {
            SectionHeader(
                title: "Recent meetings",
                subtitle: "Transcripts, summaries, and review status"
            )

            AlignaCard(padding: AlignaSpacing.zero) {
                VStack(spacing: AlignaSpacing.zero) {
                    ForEach(Array(viewModel.recentMeetings.enumerated()), id: \.element.id) { index, meeting in
                        NavigationLink(value: meeting) {
                            MeetingRow(meeting: meeting)
                                .padding(.horizontal, AlignaSpacing.medium)
                                .padding(.vertical, AlignaSpacing.small)
                        }
                        .buttonStyle(.plain)

                        if index < viewModel.recentMeetings.count - 1 {
                            Divider()
                                .padding(.leading, AlignaSpacing.medium + AlignaSize.standardIcon + AlignaSpacing.compact)
                        }
                    }
                }
            }
        }
    }

    private var tasksDueSoonSection: some View {
        VStack(alignment: .leading, spacing: AlignaSpacing.compact) {
            SectionHeader(
                title: "Tasks due soon",
                subtitle: "Approved work that needs attention"
            )

            AlignaCard(padding: AlignaSpacing.zero) {
                VStack(spacing: AlignaSpacing.zero) {
                    ForEach(Array(viewModel.tasksDueSoon.enumerated()), id: \.element.id) { index, task in
                        DashboardTaskRow(task: task)
                            .padding(.horizontal, AlignaSpacing.medium)
                            .padding(.vertical, AlignaSpacing.compact)

                        if index < viewModel.tasksDueSoon.count - 1 {
                            Divider()
                                .padding(.leading, AlignaSpacing.medium + AlignaSize.avatarSmall + AlignaSpacing.compact)
                        }
                    }
                }
            }
        }
    }

    private var metricColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }

        return [
            GridItem(
                .adaptive(minimum: 136),
                spacing: AlignaSpacing.compact,
                alignment: .top
            )
        ]
    }

    private func metricTint(for kind: DashboardMetric.Kind) -> Color {
        switch kind {
        case .meetingsThisWeek:
            AlignaColors.accent
        case .openActionItems:
            AlignaColors.success
        case .pendingAIReviews:
            AlignaColors.warning
        }
    }

    private func participantStack(for meeting: Meeting) -> some View {
        HStack(spacing: -AlignaSpacing.small) {
            ForEach(meeting.participants.prefix(3)) { participant in
                AvatarView(
                    name: participant.name,
                    initials: participant.initials,
                    size: AlignaSize.avatarSmall
                )
                .background(AlignaColors.elevatedSurface, in: Circle())
            }

            if meeting.participants.count > 3 {
                Text("+\(meeting.participants.count - 3)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AlignaColors.secondaryLabel)
                    .frame(
                        width: AlignaSize.avatarSmall,
                        height: AlignaSize.avatarSmall
                    )
                    .background(AlignaColors.surface, in: Circle())
                    .accessibilityLabel("\(meeting.participants.count - 3) more participants")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            meeting.attendeeCount == 0
                ? "No participants added"
                : "\(meeting.attendeeCount) participants"
        )
    }

    private func participantDescription(for meeting: Meeting) -> String {
        guard let first = meeting.participants.first else {
            return meeting.attendeeCount == 0
                ? "No participants added"
                : "\(meeting.attendeeCount) participants"
        }

        let additionalCount = max(meeting.attendeeCount - 1, 0)
        return additionalCount == 0
            ? first.name
            : "\(first.name) + \(additionalCount)"
    }
}

private struct DashboardTaskRow: View {
    let task: ProjectTask

    var body: some View {
        HStack(alignment: .top, spacing: AlignaSpacing.compact) {
            AvatarView(
                name: task.assignee,
                initials: task.assigneeInitials,
                size: AlignaSize.avatarSmall
            )

            VStack(alignment: .leading, spacing: AlignaSpacing.extraSmall) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AlignaColors.label)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: AlignaSpacing.small) {
                    Text(task.assignee)
                    Text("•")
                        .accessibilityHidden(true)
                    Label(
                        task.dueDateDescription(
                            style: .dateTime
                                .weekday(.abbreviated)
                                .month(.abbreviated)
                                .day()
                        ),
                        systemImage: "calendar"
                    )
                }
                .font(.caption)
                .foregroundStyle(AlignaColors.secondaryLabel)
            }

            Spacer(minLength: AlignaSpacing.small)

            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(task.isCompleted ? AlignaColors.success : AlignaColors.tertiaryLabel)
                .frame(
                    width: AlignaSize.minimumTouchTarget,
                    height: AlignaSize.minimumTouchTarget
                )
                .accessibilityLabel(task.isCompleted ? "Completed" : "Not completed")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(task.title), assigned to \(task.assignee), due \(task.dueDateDescription(style: .dateTime.year().month(.wide).day())), \(task.isCompleted ? "completed" : "not completed")"
        )
    }
}

private struct NotificationsPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EmptyStateView(
                symbol: "bell",
                title: "You’re all caught up",
                message: "Meeting reminders, review requests, and deadline updates will appear here in a later milestone."
            )
            .padding(AlignaSpacing.large)
            .background(AlignaColors.background)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview("Dashboard light") {
    NavigationStack {
        HomeView()
    }
    .preferredColorScheme(.light)
}

#Preview("Dashboard dark") {
    NavigationStack {
        HomeView()
    }
    .preferredColorScheme(.dark)
}
