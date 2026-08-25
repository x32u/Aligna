import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: RootTab = .home
    @State private var meetingLibrary: MeetingLibrary

    private let session: AppSession?
    private let meetingContext: MeetingCreationContext?
    private let dashboardViewModel: DashboardViewModel
    private let captureDependencies: MeetingCaptureDependencies

    init(session: AppSession? = nil) {
        self.session = session

        let repository: any MeetingRepository
        if let session,
           let user = session.user,
           let workspace = session.currentWorkspace {
            let local = LocalMeetingRepository(ownerUserID: user.id)
            repository = CloudBackedMeetingRepository(
                local: local,
                cloud: session.dependencies.meetingCloud,
                ownerUserID: user.id,
                workspaceID: workspace.id
            )
            meetingContext = MeetingCreationContext(
                workspace: workspace,
                organizerUserID: user.id,
                workspaceRepository: session.dependencies.workspaces
            )
            captureDependencies = .app(
                ownerUserID: user.id,
                processing: session.dependencies.meetingProcessing,
                currentUser: session.profile.map {
                    TeamMember(
                        name: $0.displayName,
                        userID: $0.id,
                        handle: $0.handle
                    )
                }
            )
        } else {
            repository = LocalMeetingRepository()
            meetingContext = nil
            captureDependencies = .preview()
        }
        _meetingLibrary = State(
            initialValue: MeetingLibrary(
                repository: repository,
                seedMeetings: session == nil ? nil : []
            )
        )

        let mock = DashboardMockData.make()
        if let profile = session?.profile {
            dashboardViewModel = DashboardViewModel(
                snapshot: DashboardSnapshot(
                    currentUser: TeamMember(
                        name: profile.displayName,
                        userID: profile.id,
                        handle: profile.handle
                    ),
                    meetings: mock.meetings,
                    tasks: mock.tasks,
                    pendingReviews: mock.pendingReviews
                )
            )
        } else {
            dashboardViewModel = DashboardViewModel(snapshot: mock)
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(
                    viewModel: dashboardViewModel,
                    meetingLibrary: meetingLibrary,
                    meetingContext: meetingContext,
                    captureDependencies: captureDependencies
                )
            }
            .tabItem {
                Label(RootTab.home.title, systemImage: RootTab.home.symbol)
            }
            .tag(RootTab.home)

            NavigationStack {
                MeetingsView(
                    library: meetingLibrary,
                    meetingContext: meetingContext,
                    captureDependencies: captureDependencies
                )
            }
            .tabItem {
                Label(RootTab.meetings.title, systemImage: RootTab.meetings.symbol)
            }
            .tag(RootTab.meetings)

            NavigationStack {
                TasksView()
            }
            .tabItem {
                Label(RootTab.tasks.title, systemImage: RootTab.tasks.symbol)
            }
            .tag(RootTab.tasks)

            NavigationStack {
                SettingsView(
                    session: session,
                    meetingLibrary: meetingLibrary
                )
            }
            .tabItem {
                Label(RootTab.settings.title, systemImage: RootTab.settings.symbol)
            }
            .tag(RootTab.settings)
        }
        .tint(AlignaColors.accent)
        .task {
            await meetingLibrary.load()
            meetingLibrary.resumePendingProcessing(
                using: captureDependencies.processing
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            meetingLibrary.resumePendingProcessing(
                using: captureDependencies.processing
            )
        }
    }
}

private enum RootTab: Hashable {
    case home
    case meetings
    case tasks
    case settings

    var title: String {
        switch self {
        case .home: "Home"
        case .meetings: "Meetings"
        case .tasks: "Tasks"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .meetings: "waveform"
        case .tasks: "checklist"
        case .settings: "gearshape.fill"
        }
    }
}

#Preview {
    RootTabView()
}
