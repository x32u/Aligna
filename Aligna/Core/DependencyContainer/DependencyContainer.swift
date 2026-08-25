import Foundation

nonisolated struct DependencyContainer: Sendable {
    let authentication: any AuthenticationServicing
    let profiles: any ProfileRepository
    let workspaces: any WorkspaceRepository
    let meetingCloud: any MeetingCloudRepository
    let meetingProcessing: any MeetingProcessingServicing
    let voiceEngine: any VoiceProcessing
    let voiceProfiles: any VoiceProfileServicing
    let avatars: any AvatarStorage
    let accountDeletion: any AccountDeletionServicing

    init(
        authentication: any AuthenticationServicing,
        profiles: any ProfileRepository,
        workspaces: any WorkspaceRepository,
        meetingCloud: any MeetingCloudRepository,
        meetingProcessing: any MeetingProcessingServicing =
            MockMeetingProcessingService(),
        voiceEngine: any VoiceProcessing = MockVoiceEngine(),
        voiceProfiles: any VoiceProfileServicing =
            MockVoiceProfileService(),
        avatars: any AvatarStorage,
        accountDeletion: any AccountDeletionServicing
    ) {
        self.authentication = authentication
        self.profiles = profiles
        self.workspaces = workspaces
        self.meetingCloud = meetingCloud
        self.meetingProcessing = meetingProcessing
        self.voiceEngine = voiceEngine
        self.voiceProfiles = voiceProfiles
        self.avatars = avatars
        self.accountDeletion = accountDeletion
    }

    @MainActor
    static func live(
        configuration: SupabaseConfiguration
    ) -> DependencyContainer {
        let provider = SupabaseClientProvider(configuration: configuration)
        let voiceEngine = FluidAudioVoiceEngine()
        let voiceProfiles = SupabaseVoiceProfileService(provider: provider)
        return DependencyContainer(
            authentication: SupabaseAuthenticationService(provider: provider),
            profiles: SupabaseProfileRepository(provider: provider),
            workspaces: SupabaseWorkspaceRepository(provider: provider),
            meetingCloud: SupabaseMeetingCloudRepository(provider: provider),
            meetingProcessing: SupabaseMeetingProcessingService(
                provider: provider,
                voiceEngine: voiceEngine,
                voiceProfiles: voiceProfiles
            ),
            voiceEngine: voiceEngine,
            voiceProfiles: voiceProfiles,
            avatars: SupabaseAvatarStorage(provider: provider),
            accountDeletion: SupabaseAccountDeletionService(
                provider: provider
            )
        )
    }

    @MainActor
    static func preview(
        user: AuthenticatedUser? = PreviewCloudData.user,
        profile: UserProfile? = PreviewCloudData.profile,
        workspaces: [Workspace] = [PreviewCloudData.workspace]
    ) -> DependencyContainer {
        let members = [
            PreviewCloudData.workspace.id: PreviewCloudData.members
        ]
        return DependencyContainer(
            authentication: MockAuthenticationService(user: user),
            profiles: MockProfileRepository(profile: profile),
            workspaces: MockWorkspaceRepository(
                workspaces: workspaces,
                members: members,
                lookup: PreviewCloudData.lookup
            ),
            meetingCloud: MockMeetingCloudRepository(),
            meetingProcessing: MockMeetingProcessingService(),
            voiceEngine: MockVoiceEngine(),
            voiceProfiles: MockVoiceProfileService(
                status: profile?.voiceEnrollmentStatus ?? .notStarted
            ),
            avatars: MockAvatarStorage(),
            accountDeletion: MockAccountDeletionService()
        )
    }
}

nonisolated enum PreviewCloudData {
    static let userID = UUID(
        uuidString: "A1100000-0000-0000-0000-000000000001"
    ) ?? UUID()
    static let teammateID = UUID(
        uuidString: "A1100000-0000-0000-0000-000000000002"
    ) ?? UUID()
    static let workspaceID = UUID(
        uuidString: "A2200000-0000-0000-0000-000000000001"
    ) ?? UUID()

    static let user = AuthenticatedUser(
        id: userID,
        email: "john@example.com",
        isEmailVerified: true
    )
    static let profile = UserProfile(
        id: userID,
        displayName: "John Cruz",
        handle: "johncruz",
        avatarPath: nil,
        onboardingCompleted: true,
        createdAt: .now,
        updatedAt: .now
    )
    static let workspace = Workspace(
        id: workspaceID,
        name: "Aligna Mobile Launch",
        createdBy: userID,
        createdAt: .now,
        updatedAt: .now,
        currentUserRole: .owner
    )
    static let members = [
        WorkspaceMember(
            workspaceID: workspaceID,
            userID: userID,
            role: .owner,
            joinedAt: .now,
            displayName: "John Cruz",
            handle: "johncruz",
            avatarPath: nil
        ),
        WorkspaceMember(
            workspaceID: workspaceID,
            userID: teammateID,
            role: .member,
            joinedAt: .now,
            displayName: "Maya Chen",
            handle: "mayachen",
            avatarPath: nil
        ),
    ]
    static let lookup = ProfileLookupResult(
        id: teammateID,
        handle: "mayachen",
        displayName: "Maya Chen",
        avatarPath: nil
    )
}
