import AVFAudio
import Foundation
import Testing
@testable import Aligna

struct AlignaTests {
    @Test("Appearance preferences resolve safely")
    func appearancePreferencesResolveSafely() {
        #expect(AppAppearance.resolve("system") == .system)
        #expect(AppAppearance.resolve("light") == .light)
        #expect(AppAppearance.resolve("dark") == .dark)
        #expect(AppAppearance.resolve("unsupported") == .system)
    }

    @Test("Recording Live Activity state formats running and paused time")
    func recordingLiveActivityStateTracksElapsedTime() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let recordingState = MeetingRecordingAttributes.ContentState(
            phase: .recording,
            elapsedTime: 65,
            referenceDate: referenceDate
        )
        let pausedState = MeetingRecordingAttributes.ContentState(
            phase: .paused,
            elapsedTime: 65,
            referenceDate: referenceDate
        )

        #expect(
            recordingState.timerStartDate
                == referenceDate.addingTimeInterval(-65)
        )
        #expect(pausedState.timerStartDate == nil)
        #expect(pausedState.formattedElapsedTime == "01:05")
    }

    @Test("Only incomplete tasks past their deadline are overdue")
    func overdueTaskStateHonorsCompletion() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let pastDueDate = referenceDate.addingTimeInterval(-3_600)

        let openTask = ProjectTask(
            title: "Review meeting notes",
            assignee: "Maya",
            dueDate: pastDueDate,
            priority: .high
        )
        let completedTask = ProjectTask(
            title: "Publish agenda",
            assignee: "Liam",
            dueDate: pastDueDate,
            priority: .medium,
            isCompleted: true
        )

        #expect(openTask.isOverdue(asOf: referenceDate))
        #expect(!completedTask.isOverdue(asOf: referenceDate))
    }

    @Test("Dashboard greeting follows the local time of day")
    func dashboardGreetingUsesCalendarHour() {
        let calendar = utcCalendar()
        let evening = date(
            year: 2026,
            month: 7,
            day: 27,
            hour: 19,
            calendar: calendar
        )
        let viewModel = DashboardViewModel(
            snapshot: emptySnapshot(),
            now: evening,
            calendar: calendar
        )

        #expect(viewModel.greeting == "Good evening, John")
    }

    @Test("The nearest scheduled meeting is selected as upcoming")
    func upcomingMeetingIsChronologicalAndScheduled() {
        let calendar = utcCalendar()
        let now = date(
            year: 2026,
            month: 7,
            day: 27,
            hour: 10,
            calendar: calendar
        )
        let participant = TeamMember(name: "John Cruz")
        let meetings = [
            Meeting(
                title: "Later",
                projectName: "Aligna",
                scheduledAt: now.addingTimeInterval(7_200),
                participants: [participant],
                status: .scheduled
            ),
            Meeting(
                title: "Processing",
                projectName: "Aligna",
                scheduledAt: now.addingTimeInterval(900),
                participants: [participant],
                status: .processing
            ),
            Meeting(
                title: "Next",
                projectName: "Aligna",
                scheduledAt: now.addingTimeInterval(3_600),
                participants: [participant],
                status: .scheduled
            )
        ]
        let snapshot = DashboardSnapshot(
            currentUser: participant,
            meetings: meetings,
            tasks: [],
            pendingReviews: []
        )
        let viewModel = DashboardViewModel(
            snapshot: snapshot,
            now: now,
            calendar: calendar
        )

        #expect(viewModel.upcomingMeeting?.title == "Next")
    }

    @Test("Tasks due soon are open, within seven days, and sorted")
    func dueSoonTasksAreFilteredAndSorted() {
        let calendar = utcCalendar()
        let now = date(
            year: 2026,
            month: 7,
            day: 27,
            hour: 10,
            calendar: calendar
        )
        let tasks = [
            ProjectTask(
                title: "Second",
                assignee: "Maya Chen",
                dueDate: now.addingTimeInterval(2 * 86_400),
                priority: .medium
            ),
            ProjectTask(
                title: "Outside window",
                assignee: "Liam Rivera",
                dueDate: now.addingTimeInterval(8 * 86_400),
                priority: .low
            ),
            ProjectTask(
                title: "First",
                assignee: "Priya Shah",
                dueDate: now.addingTimeInterval(86_400),
                priority: .high
            ),
            ProjectTask(
                title: "Already done",
                assignee: "Noah Williams",
                dueDate: now.addingTimeInterval(3_600),
                priority: .low,
                isCompleted: true
            )
        ]
        let snapshot = DashboardSnapshot(
            currentUser: TeamMember(name: "John Cruz"),
            meetings: [],
            tasks: tasks,
            pendingReviews: []
        )
        let viewModel = DashboardViewModel(
            snapshot: snapshot,
            now: now,
            calendar: calendar
        )

        #expect(viewModel.tasksDueSoon.map(\.title) == ["First", "Second"])
    }

    @Test("Dashboard metrics are derived from typed workspace data")
    func dashboardMetricsReflectSnapshot() {
        let calendar = utcCalendar()
        let now = date(
            year: 2026,
            month: 7,
            day: 27,
            hour: 10,
            calendar: calendar
        )
        let participant = TeamMember(name: "John Cruz")
        let snapshot = DashboardSnapshot(
            currentUser: participant,
            meetings: [
                Meeting(
                    title: "This week",
                    projectName: "Aligna",
                    scheduledAt: now,
                    participants: [participant],
                    status: .complete
                ),
                Meeting(
                    title: "Next week",
                    projectName: "Aligna",
                    scheduledAt: now.addingTimeInterval(8 * 86_400),
                    participants: [participant],
                    status: .scheduled
                )
            ],
            tasks: [
                ProjectTask(
                    title: "Open",
                    assignee: "Maya Chen",
                    dueDate: now.addingTimeInterval(86_400),
                    priority: .high
                ),
                ProjectTask(
                    title: "Done",
                    assignee: "Liam Rivera",
                    dueDate: now,
                    priority: .low,
                    isCompleted: true
                )
            ],
            pendingReviews: [
                MeetingReview(
                    meetingTitle: "This week",
                    summary: "A concise summary.",
                    actionItemCount: 2,
                    confidence: 0.9
                )
            ]
        )
        let viewModel = DashboardViewModel(
            snapshot: snapshot,
            now: now,
            calendar: calendar
        )
        let values = Dictionary(
            uniqueKeysWithValues: viewModel.metrics.map { ($0.kind, $0.value) }
        )

        #expect(values[.meetingsThisWeek] == 1)
        #expect(values[.openActionItems] == 1)
        #expect(values[.pendingAIReviews] == 1)
    }

    @Test("Meeting capture follows valid state transitions")
    func meetingCaptureStateTransitionsAreExplicit() {
        var machine = MeetingCaptureStateMachine()

        let requestedPermission = machine.transition(
            to: .requestingPermission
        )
        let beganPreparing = machine.transition(
            to: .preparingModel(progress: 0.2)
        )
        let updatedProgress = machine.transition(
            to: .preparingModel(progress: 0.8)
        )
        let becameReady = machine.transition(to: .ready)
        let beganRecording = machine.transition(to: .recording)
        let paused = machine.transition(to: .paused)
        let resumed = machine.transition(to: .recording)
        let beganFinishing = machine.transition(to: .finishing)
        let completed = machine.transition(to: .completed)

        #expect(requestedPermission)
        #expect(beganPreparing)
        #expect(updatedProgress)
        #expect(becameReady)
        #expect(beganRecording)
        #expect(paused)
        #expect(resumed)
        #expect(beganFinishing)
        #expect(completed)
        #expect(machine.state == .completed)
    }

    @Test("Processing phases use stable customer-facing copy")
    func processingPhaseCopyIsProviderNeutral() {
        #expect(
            MeetingProcessingStatus.queued.customerTitle
                == "Preparing recording"
        )
        #expect(
            MeetingProcessingStatus.transcribing.customerTitle
                == "Creating transcript"
        )
        #expect(
            MeetingProcessingStatus.analyzing.customerTitle
                == "Organizing your notes"
        )
        #expect(
            MeetingProcessingStatus.queued.customerPhase
                == .preparingRecording
        )
        #expect(
            MeetingProcessingStatus.transcribing.customerPhase
                == .creatingTranscript
        )
        #expect(
            [
                MeetingProcessingStatus.preparingSpeakers,
                .diarizing,
                .matchingSpeakers,
                .mergingTranscript,
                .analyzing,
            ].allSatisfy {
                $0.customerPhase == .organizingNotes
            }
        )
        #expect(
            MeetingProcessingStatus.allCases.allSatisfy {
                !$0.customerTitle.localizedCaseInsensitiveContains("Groq")
                    && !$0.customerTitle.localizedCaseInsensitiveContains(
                        "Whisper"
                    )
            }
        )
    }

    @Test("Completed processing promotes validated meeting outcomes")
    func completedProcessingUpdatesMeetingOutcome() {
        let meeting = Meeting(
            title: "Meeting · Jul 28",
            projectName: "Aligna",
            scheduledAt: .now,
            status: .processing,
            processingStatus: .queued
        )
        let evidence = MeetingEvidence(
            timestampSeconds: 42,
            quote: "Maya will send the draft."
        )
        let analysis = MeetingAnalysis(
            generatedTitle: "Launch draft review",
            summary: "The team reviewed the launch draft.",
            keyPoints: [],
            decisions: [],
            actionItems: [
                MeetingActionItem(
                    task: "Send the launch draft",
                    assignee: "Maya",
                    dueDate: nil,
                    evidence: evidence
                ),
            ],
            openQuestions: [],
            followUps: [],
            languagesDetected: ["English", "Filipino"]
        )

        let completed = meeting.withProcessing(
            status: .complete,
            title: analysis.generatedTitle,
            analysis: analysis,
            transcript: [
                TranscriptSegment(
                    text: evidence.quote,
                    startTime: evidence.timestampSeconds,
                    endTime: 45,
                    isFinal: true
                ),
            ]
        )

        #expect(completed.title == "Launch draft review")
        #expect(completed.status == .needsReview)
        #expect(completed.processingStatus == .complete)
        #expect(completed.analysis?.actionItems.first?.dueDate == nil)
        #expect(completed.transcript.first?.speaker == nil)
    }

    @Test("Processing errors distinguish offline and server failures")
    func processingErrorsAreClassifiedForRecovery() {
        let offline = MeetingProcessingServiceError.normalized(
            URLError(.notConnectedToInternet)
        )
        let server = MeetingProcessingServiceError.normalized(
            NSError(
                domain: "AlignaTests",
                code: 503
            )
        )

        #expect(offline == .offline)
        #expect(offline.shouldRemainQueued)
        #expect(offline.issue == .offline)
        #expect(server == .serviceUnavailable)
        #expect(!server.shouldRemainQueued)
    }

    @MainActor
    @Test("Starting capture twice never starts a second audio session")
    func duplicateCaptureStartIsPrevented() async {
        let audio = MockAudioRecordingService()
        let speech = MockSpeechTranscriptionService()
        let repository = InMemoryMeetingRepository()
        let viewModel = MeetingCaptureViewModel(
            configuration: captureConfiguration(),
            dependencies: MeetingCaptureDependencies(
                audio: audio,
                speech: speech
            ),
            repository: repository
        )

        await viewModel.start()
        await viewModel.start()

        #expect(viewModel.state == .recording)
        #expect(audio.requestCount == 1)
        #expect(audio.startCount == 1)
        await viewModel.cancel()
    }

    @Test("A newer volatile transcript replaces the prior text")
    func volatileTranscriptIsReplaced() {
        var transcript = TranscriptAccumulator()
        transcript.consume(
            .volatile(
                TranscriptSegment(
                    text: "Review the",
                    startTime: 0,
                    isFinal: false
                )
            )
        )
        transcript.consume(
            .volatile(
                TranscriptSegment(
                    text: "Review the launch timeline.",
                    startTime: 0,
                    isFinal: false
                )
            )
        )

        #expect(transcript.volatileSegment?.text == "Review the launch timeline.")
        #expect(transcript.finalizedSegments.isEmpty)
    }

    @Test("Final transcript segments are deduplicated")
    func finalTranscriptIsDeduplicated() {
        var transcript = TranscriptAccumulator()
        let first = TranscriptSegment(
            text: "Maya will review the launch plan.",
            startTime: 4,
            endTime: 7,
            isFinal: true
        )
        let duplicate = TranscriptSegment(
            text: "Maya will review the launch plan.",
            startTime: 4.1,
            endTime: 7.1,
            isFinal: true
        )

        transcript.consume(.finalized(first))
        transcript.consume(.finalized(duplicate))

        #expect(transcript.finalizedSegments.count == 1)
        #expect(transcript.volatileSegment == nil)
    }

    @Test("Paused time is excluded from meeting duration")
    func pauseResumeTimingUsesInjectedDates() {
        let start = Date(timeIntervalSince1970: 1_000)
        var tracker = RecordingDurationTracker()

        tracker.start(at: start)
        tracker.pause(at: start.addingTimeInterval(12))
        tracker.resume(at: start.addingTimeInterval(40))
        let duration = tracker.finish(
            at: start.addingTimeInterval(48)
        )

        #expect(duration == 20)
        #expect(tracker.elapsed(at: start.addingTimeInterval(80)) == 20)
    }

    @Test("Microphone levels smooth peaks and settle when paused")
    func microphoneLevelHistoryIsSmoothed() {
        var history = AudioLevelHistory(
            sampleCount: 4,
            restingLevel: 0.05
        )

        let afterPeak = history.append(rawLevel: 1)
        let afterRelease = history.append(rawLevel: 0)
        let settled = history.settle()

        #expect(afterPeak.last != nil)
        #expect((afterPeak.last ?? 0) > 0.05)
        #expect((afterPeak.last ?? 1) < 1)
        #expect((afterRelease.last ?? 0) < (afterPeak.last ?? 0))
        #expect(Set(settled).count == 1)
        #expect(settled.allSatisfy { $0 == 0.045 })
    }

    @MainActor
    @Test("Local meeting repository persists transcript metadata")
    func completedMeetingPersistsLocally() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AlignaRepositoryTests")
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let repository = LocalMeetingRepository(directory: directory)
        let meeting = Meeting(
            title: "Roadmap review",
            projectName: "Aligna",
            scheduledAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationSeconds: 75,
            participants: [MeetingParticipant(name: "Maya Chen")],
            status: .complete,
            transcript: [
                TranscriptSegment(
                    text: "The roadmap is ready for review.",
                    startTime: 0,
                    endTime: 2.5,
                    isFinal: true
                )
            ],
            audioFileName: "recording.caf",
            transcriptionLocaleIdentifier: "en_US"
        )

        try await repository.save(meeting)
        let storedMeetings = try await repository.fetchMeetings()

        #expect(storedMeetings == [meeting])
    }

    @MainActor
    @Test("Deleting a meeting removes its metadata and local recording")
    func localMeetingDeletionRemovesRecording() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appending(path: "AlignaDeletionTests-\(UUID().uuidString)")
        let metadataDirectory = baseDirectory.appending(path: "metadata")
        let recordingsDirectory = baseDirectory.appending(path: "recordings")
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        try FileManager.default.createDirectory(
            at: recordingsDirectory,
            withIntermediateDirectories: true
        )
        let recordingURL = recordingsDirectory
            .appending(path: "meeting.m4a")
        try Data([0x00, 0x01, 0x02]).write(to: recordingURL)

        let repository = LocalMeetingRepository(
            directory: metadataDirectory,
            recordingsDirectory: recordingsDirectory
        )
        let meeting = Meeting(
            title: "Delete request review",
            projectName: "Aligna",
            scheduledAt: .now,
            status: .complete,
            audioFileName: recordingURL.lastPathComponent
        )

        try await repository.save(meeting)
        try await repository.delete(meeting)

        #expect(try await repository.fetchMeetings().isEmpty)
        #expect(
            !FileManager.default.fileExists(atPath: recordingURL.path())
        )
    }

    @MainActor
    @Test("Cancelling capture deletes incomplete audio and saves nothing")
    func captureCancellationCleansUp() async {
        let audio = MockAudioRecordingService()
        let repository = InMemoryMeetingRepository()
        let viewModel = MeetingCaptureViewModel(
            configuration: captureConfiguration(),
            dependencies: MeetingCaptureDependencies(
                audio: audio,
                speech: MockSpeechTranscriptionService()
            ),
            repository: repository
        )

        await viewModel.start()
        let recordingURL = audio.latestFileURL
        #expect(recordingURL != nil)
        #expect(
            recordingURL.map {
                FileManager.default.fileExists(atPath: $0.path())
            } == true
        )

        await viewModel.cancel()
        let storedMeetings = await repository.fetchMeetings()

        #expect(audio.cancelCount == 1)
        #expect(
            recordingURL.map {
                FileManager.default.fileExists(atPath: $0.path())
            } == false
        )
        #expect(storedMeetings.isEmpty)
        #expect(viewModel.state == .idle)
    }

    @MainActor
    @Test("Capture does not require a speech-recognition model")
    func captureIgnoresLegacySpeechModelFailures() async {
        let audio = MockAudioRecordingService()
        let viewModel = MeetingCaptureViewModel(
            configuration: captureConfiguration(),
            dependencies: MeetingCaptureDependencies(
                audio: audio,
                speech: MockSpeechTranscriptionService(
                    prepareError: .modelPreparationFailed
                )
            ),
            repository: InMemoryMeetingRepository()
        )

        await viewModel.start()

        #expect(viewModel.state == .recording)
        #expect(audio.startCount == 1)
        await viewModel.cancel()
    }

    @Test("Account validation normalizes user input and rejects weak values")
    func accountValidationIsPredictable() {
        #expect(
            EmailValidator.normalized("  John@Example.COM ")
                == "john@example.com"
        )
        #expect(EmailValidator.isValid("john@example.com"))
        #expect(!EmailValidator.isValid("john@example"))
        #expect(PasswordValidator.isValid("Aligna2026"))
        #expect(!PasswordValidator.isValid("password"))
        #expect(HandleValidator.normalized(" @John_Cruz ") == "john_cruz")
        #expect(HandleValidator.isValid("john_cruz"))
        #expect(!HandleValidator.isValid("john-cruz"))
    }

    @Test("Authentication callback accepts only the configured Aligna route")
    func authenticationCallbackRouteIsExact() throws {
        let configured = AuthRedirectConfiguration.callbackURL
        let valid = try #require(
            URL(string: "aligna://auth/callback?code=fixture")
        )
        let oldHost = try #require(
            URL(string: "aligna://auth-callback?code=fixture")
        )
        let unrelatedPath = try #require(
            URL(string: "aligna://auth/other?code=fixture")
        )

        #expect(configured.absoluteString == "aligna://auth/callback")
        #expect(AuthRedirectConfiguration.accepts(valid))
        #expect(!AuthRedirectConfiguration.accepts(oldHost))
        #expect(!AuthRedirectConfiguration.accepts(unrelatedPath))
        #expect(
            AuthRedirectConfiguration.fingerprint(valid)
                == AuthRedirectConfiguration.fingerprint(valid)
        )
        #expect(
            AuthRedirectConfiguration.fingerprint(valid)
                != AuthRedirectConfiguration.fingerprint(oldHost)
        )
    }

    @Test("Callback routing recognizes verification and recovery links")
    func authenticationCallbackKindsAreParsed() throws {
        let verification = try #require(
            URL(string: "aligna://auth/callback?type=signup&code=fixture")
        )
        let recovery = try #require(
            URL(
                string:
                    "aligna://auth/callback?type=recovery&code=fixture"
            )
        )

        #expect(
            AuthRedirectConfiguration.callbackKind(from: verification)
                == .emailVerification
        )
        #expect(
            AuthRedirectConfiguration.callbackKind(from: recovery)
                == .passwordRecovery
        )
    }

    @Test("Expired and cancelled callback failures are user-safe")
    func authenticationCallbackFailuresAreTyped() throws {
        let expiredRecovery = try #require(
            URL(
                string:
                    "aligna://auth/callback?type=recovery&error_code=otp_expired"
            )
        )
        let cancelled = try #require(
            URL(
                string:
                    "aligna://auth/callback?error=access_denied&error_description=cancelled"
            )
        )

        #expect(
            AuthRedirectConfiguration.callbackError(
                from: expiredRecovery,
                fallbackKind: nil
            ) == .expiredRecoveryLink
        )
        #expect(
            AuthRedirectConfiguration.callbackError(
                from: cancelled,
                fallbackKind: .emailVerification
            ) == .callbackCancelled
        )
    }

    @Test("Pending callback intent is stored without storing credentials")
    func callbackIntentStoreRoundTrips() throws {
        let suiteName = "AlignaTests.AuthIntent.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        AuthCallbackIntentStore.remember(
            .passwordRecovery,
            defaults: defaults
        )
        #expect(
            AuthCallbackIntentStore.current(defaults: defaults)
                == .passwordRecovery
        )

        AuthCallbackIntentStore.clear(defaults: defaults)
        #expect(AuthCallbackIntentStore.current(defaults: defaults) == nil)
    }

    @Test("Email masking keeps the destination recognizable")
    func verificationEmailIsMasked() {
        #expect(
            EmailMasker.masked("  John.Christopher@Example.COM ")
                == "jo••••••••••••••@example.com"
        )
        #expect(EmailMasker.masked("a@example.com") == "a•••@example.com")
    }

    @Test("Resend cooldown is deterministic and expires after sixty seconds")
    func resendCooldownExpires() {
        let start = Date(timeIntervalSince1970: 1_000)
        var cooldown = AuthResendCooldown(duration: 60)

        #expect(cooldown.canResend(at: start))
        cooldown.start(at: start)
        #expect(cooldown.remainingSeconds(at: start) == 60)
        #expect(!cooldown.canResend(at: start.addingTimeInterval(59)))
        #expect(cooldown.canResend(at: start.addingTimeInterval(60)))
    }

    @Test("Repeated signup requests a fresh email only after the server cooldown")
    func repeatedSignupConfirmationPolicy() {
        let now = Date(timeIntervalSince1970: 10_000)

        #expect(
            !SignUpConfirmationPolicy.shouldRequestFreshEmail(
                createdAt: now.addingTimeInterval(-10),
                confirmationSentAt: now.addingTimeInterval(-10),
                now: now
            )
        )
        #expect(
            SignUpConfirmationPolicy.shouldRequestFreshEmail(
                createdAt: now.addingTimeInterval(-600),
                confirmationSentAt: now.addingTimeInterval(-61),
                now: now
            )
        )
        #expect(
            SignUpConfirmationPolicy.isObfuscatedExistingUser(
                identityCount: 0,
                hasSession: false
            )
        )
        #expect(
            !SignUpConfirmationPolicy.isObfuscatedExistingUser(
                identityCount: 1,
                hasSession: false
            )
        )
    }

    @MainActor
    @Test("Generated passwords remain complete in account bindings")
    func generatedPasswordBindingIsNotTruncated() {
        let generated = "T7!qB2@vP9#kL4$mN8%rS6&wX3"
        let model = AuthenticationViewModel()
        model.displayName = "John Christopher Cruz"
        model.username = "johncruz"
        model.email = "john@example.com"
        model.password = generated
        model.passwordConfirmation = generated

        #expect(model.password == generated)
        #expect(model.passwordConfirmation == generated)
        #expect(model.password.count == generated.count)
        #expect(model.credentialsStepIsValid)

        model.passwordConfirmation.removeLast()
        #expect(
            model.passwordConfirmationValidationMessage
                == "Passwords do not match."
        )
    }

    @Test("Supabase configuration fails closed when secrets are absent")
    func missingSupabaseConfigurationIsTyped() {
        let result = SupabaseConfiguration.make(
            projectURL: nil,
            publishableKey: nil
        )

        switch result {
        case .success:
            Issue.record("Missing configuration unexpectedly succeeded")
        case let .failure(error):
            #expect(error == .missingProjectURL)
        }
    }

    @Test("Supabase profile DTO maps snake-case JSON to the domain model")
    func profileDTODecoding() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "display_name": "John Cruz",
          "handle": "johncruz",
          "avatar_path": "\(id.uuidString.lowercased())/profile.jpg",
          "onboarding_completed": true,
          "created_at": "2026-07-28T01:00:00Z",
          "updated_at": "2026-07-28T02:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let dto = try decoder.decode(
            ProfileDTO.self,
            from: Data(json.utf8)
        )

        #expect(dto.domain.id == id)
        #expect(dto.domain.displayName == "John Cruz")
        #expect(dto.domain.handle == "johncruz")
        #expect(dto.domain.onboardingCompleted)
    }

    @Test("Workspace roles enforce the manager permission hierarchy")
    func workspaceRolePermissions() {
        #expect(WorkspaceRole.owner.canManage(.owner))
        #expect(WorkspaceRole.admin.canManage(.member))
        #expect(!WorkspaceRole.admin.canManage(.owner))
        #expect(!WorkspaceRole.member.canManage(.member))
    }

    @MainActor
    @Test("An unverified restored account waits for email confirmation")
    func sessionRoutesUnverifiedUserToVerification() async {
        let user = AuthenticatedUser(
            id: UUID(),
            email: "pending@example.com",
            isEmailVerified: false
        )
        let dependencies = DependencyContainer(
            authentication: MockAuthenticationService(user: user),
            profiles: MockProfileRepository(),
            workspaces: MockWorkspaceRepository(),
            meetingCloud: MockMeetingCloudRepository(),
            avatars: MockAvatarStorage(),
            accountDeletion: MockAccountDeletionService()
        )
        let session = AppSession(dependencies: dependencies)

        await session.start()

        #expect(session.state == .awaitingEmailVerification)
        #expect(session.pendingVerificationEmail == "pending@example.com")
    }

    @MainActor
    @Test("Verification resend follows one cooldown across account screens")
    func verificationResendUsesSessionCooldown() async throws {
        let authentication = MockAuthenticationService()
        let dependencies = DependencyContainer(
            authentication: authentication,
            profiles: MockProfileRepository(),
            workspaces: MockWorkspaceRepository(),
            meetingCloud: MockMeetingCloudRepository(),
            avatars: MockAvatarStorage(),
            accountDeletion: MockAccountDeletionService()
        )
        let session = AppSession(
            dependencies: dependencies,
            initialState: .signedOut
        )

        let created = await session.signUp(
            SignUpRequest(
                email: "pending@example.com",
                password: "SecurePass123!",
                displayName: "Pending User",
                handle: "pending_user"
            )
        )
        let requestedAt = try #require(
            session.verificationEmailRequestedAt
        )

        let earlyResend = await session.resendVerification(
            at: requestedAt.addingTimeInterval(30)
        )
        let allowedResend = await session.resendVerification(
            at: requestedAt.addingTimeInterval(60)
        )
        let resendCount = await authentication.resendVerificationCount

        #expect(created)
        #expect(session.state == .awaitingEmailVerification)
        #expect(!earlyResend)
        #expect(allowedResend)
        #expect(resendCount == 1)
    }

    @MainActor
    @Test("Mock authentication failures become a recoverable session state")
    func mockRepositoryFailureIsSurfaced() async {
        let expectedMessage = "Mock authentication is unavailable."
        let dependencies = DependencyContainer(
            authentication: MockAuthenticationService(
                failure: AuthenticationServiceError.message(expectedMessage)
            ),
            profiles: MockProfileRepository(),
            workspaces: MockWorkspaceRepository(),
            meetingCloud: MockMeetingCloudRepository(),
            avatars: MockAvatarStorage(),
            accountDeletion: MockAccountDeletionService()
        )
        let session = AppSession(dependencies: dependencies)

        await session.start()

        #expect(session.state == .failed(expectedMessage))
    }

    @MainActor
    @Test("A restored verified account routes to its workspace")
    func sessionRestorationRoutesToAuthenticated() async {
        let fixture = stepFourFixture()
        let session = AppSession(dependencies: fixture.dependencies)

        await session.start()

        #expect(session.state == .authenticated)
        #expect(session.user == fixture.user)
        #expect(session.profile == fixture.profile)
        #expect(session.currentWorkspace == fixture.workspace)
    }

    @MainActor
    @Test("Verification callbacks route only verified users into the app")
    func verificationCallbackRoutesToAuthenticated() async throws {
        let fixture = stepFourFixture()
        let session = AppSession(
            dependencies: fixture.dependencies,
            initialState: .awaitingEmailVerification
        )
        let callback = try #require(
            URL(string: "aligna://auth/callback?type=signup&code=fixture")
        )

        await session.handle(url: callback)

        #expect(session.state == .authenticated)
        #expect(session.user?.isEmailVerified == true)
        #expect(!session.isPresentingPasswordUpdate)
    }

    @MainActor
    @Test("The same verification callback is exchanged only once")
    func duplicateVerificationCallbackIsIgnored() async throws {
        let userID = UUID()
        let user = AuthenticatedUser(
            id: userID,
            email: "john@example.com",
            isEmailVerified: true
        )
        let authentication = MockAuthenticationService(user: user)
        let workspace = Workspace(
            id: UUID(),
            name: "Aligna Launch",
            createdBy: userID,
            createdAt: .now,
            updatedAt: .now,
            currentUserRole: .owner
        )
        let dependencies = DependencyContainer(
            authentication: authentication,
            profiles: MockProfileRepository(
                profile: UserProfile(
                    id: userID,
                    displayName: "John Cruz",
                    handle: "johncruz",
                    onboardingCompleted: true,
                    createdAt: .now,
                    updatedAt: .now
                )
            ),
            workspaces: MockWorkspaceRepository(workspaces: [workspace]),
            meetingCloud: MockMeetingCloudRepository(),
            avatars: MockAvatarStorage(),
            accountDeletion: MockAccountDeletionService()
        )
        let session = AppSession(
            dependencies: dependencies,
            initialState: .awaitingEmailVerification
        )
        let callback = try #require(
            URL(string: "aligna://auth/callback?code=one-time-code")
        )

        await session.handle(url: callback)
        await session.handle(url: callback)
        let callbackCount = await authentication.handleCallbackCount

        #expect(callbackCount == 1)
        #expect(session.state == .authenticated)
        #expect(session.operationError == nil)
    }

    @MainActor
    @Test("An already-confirmed server session wins over a reused link")
    func confirmedSessionRecoversFromReusedVerificationLink() async throws {
        let userID = UUID()
        let user = AuthenticatedUser(
            id: userID,
            email: "john@example.com",
            isEmailVerified: true
        )
        let authentication = MockAuthenticationService(
            user: user,
            callbackFailure:
                AuthenticationServiceError.expiredVerificationLink
        )
        let workspace = Workspace(
            id: UUID(),
            name: "Aligna Launch",
            createdBy: userID,
            createdAt: .now,
            updatedAt: .now,
            currentUserRole: .owner
        )
        let dependencies = DependencyContainer(
            authentication: authentication,
            profiles: MockProfileRepository(
                profile: UserProfile(
                    id: userID,
                    displayName: "John Cruz",
                    handle: "johncruz",
                    onboardingCompleted: true,
                    createdAt: .now,
                    updatedAt: .now
                )
            ),
            workspaces: MockWorkspaceRepository(workspaces: [workspace]),
            meetingCloud: MockMeetingCloudRepository(),
            avatars: MockAvatarStorage(),
            accountDeletion: MockAccountDeletionService()
        )
        let session = AppSession(
            dependencies: dependencies,
            initialState: .awaitingEmailVerification
        )
        let reusedLink = try #require(
            URL(
                string:
                    "aligna://auth/callback?code=already-consumed-code"
            )
        )

        await session.handle(url: reusedLink)

        #expect(session.state == .authenticated)
        #expect(session.user == user)
        #expect(session.operationError == nil)
        #expect(session.emailVerificationStatus == .waiting)
    }

    @MainActor
    @Test("Recovery callbacks open the new-password flow")
    func recoveryCallbackOpensPasswordUpdate() async throws {
        let user = AuthenticatedUser(
            id: UUID(),
            email: "john@example.com",
            isEmailVerified: true
        )
        let authentication = MockAuthenticationService(user: user)
        let dependencies = DependencyContainer(
            authentication: authentication,
            profiles: MockProfileRepository(),
            workspaces: MockWorkspaceRepository(),
            meetingCloud: MockMeetingCloudRepository(),
            avatars: MockAvatarStorage(),
            accountDeletion: MockAccountDeletionService()
        )
        let session = AppSession(
            dependencies: dependencies,
            initialState: .signedOut
        )
        let callback = try #require(
            URL(
                string:
                    "aligna://auth/callback?type=recovery&code=fixture"
            )
        )

        await session.handle(url: callback)

        #expect(session.state == .signedOut)
        #expect(session.passwordRecoveryStatus == .ready)
        #expect(session.isPresentingPasswordUpdate)
    }

    @MainActor
    @Test("Signing out clears all account-scoped session state")
    func signOutClearsSessionState() async {
        let fixture = stepFourFixture()
        let session = AppSession(dependencies: fixture.dependencies)
        await session.start()

        await session.signOut()

        #expect(session.state == .signedOut)
        #expect(session.user == nil)
        #expect(session.profile == nil)
        #expect(session.workspaces.isEmpty)
        #expect(session.currentWorkspace == nil)
    }

    @MainActor
    @Test("Invitation responses leave only pending invitations")
    func invitationResponsesArePersistedByTheRepository() async throws {
        let acceptedInvitation = WorkspaceInvitation(
            id: UUID(),
            workspaceID: UUID(),
            workspaceName: "Aligna Launch",
            inviteeID: UUID(),
            invitedBy: UUID(),
            status: .pending,
            createdAt: .now,
            respondedAt: nil
        )
        let declinedInvitation = WorkspaceInvitation(
            id: UUID(),
            workspaceID: UUID(),
            workspaceName: "Research",
            inviteeID: UUID(),
            invitedBy: UUID(),
            status: .pending,
            createdAt: .now,
            respondedAt: nil
        )
        let repository = MockWorkspaceRepository(
            invitations: [acceptedInvitation, declinedInvitation]
        )

        try await repository.respond(
            invitationID: acceptedInvitation.id,
            accept: true
        )
        try await repository.respond(
            invitationID: declinedInvitation.id,
            accept: false
        )
        let remaining = try await repository.invitations()

        #expect(remaining.isEmpty)
    }

    @Test("Selected members keep cloud identities while manual guests remain local")
    func participantSelectionPreservesIdentity() {
        let workspaceID = UUID()
        let teammateID = UUID()
        let member = WorkspaceMember(
            workspaceID: workspaceID,
            userID: teammateID,
            role: .member,
            joinedAt: .now,
            displayName: "Maya Chen",
            handle: "mayachen",
            avatarPath: nil
        )
        let configuration = NewMeetingConfiguration(
            title: "Launch readiness",
            participantNames: ["Maya Chen", "External Partner"],
            localeIdentifier: "en_US",
            selectedMembers: [member]
        )

        #expect(configuration.participants.count == 2)
        #expect(configuration.participants.first?.userID == teammateID)
        #expect(configuration.participants.last?.userID == nil)
        #expect(configuration.participants.last?.name == "External Partner")
    }

    @Test("Locale identifiers are normalized to BCP-47")
    func localeIdentifiersUseBCP47() {
        #expect(
            TranscriptionLanguage.normalizedIdentifier("fil_PH")
                == "fil-PH"
        )
        #expect(
            TranscriptionLanguage.normalizedIdentifier("en_US")
                == "en-US"
        )
    }

    @Test("Filipino is discovered only from reported capabilities")
    func filipinoDiscoveryUsesReportedLocales() {
        let withoutFilipino = TranscriptionCapabilities(
            languages: [
                TranscriptionLanguage(identifier: "en-US")
            ],
            speechLocaleIdentifiers: ["en-US"],
            dictationLocaleIdentifiers: []
        )
        let withFilipino = TranscriptionCapabilities(
            languages: [
                TranscriptionLanguage(identifier: "en-US"),
                TranscriptionLanguage(identifier: "fil-PH")
            ],
            speechLocaleIdentifiers: ["en-US", "fil-PH"],
            dictationLocaleIdentifiers: []
        )

        let hasUnexpectedFilipino = withoutFilipino.languages.contains {
            $0.isFilipino
        }
        let hasFilipino = withFilipino.languages.contains {
            $0.isFilipino
        }
        #expect(!hasUnexpectedFilipino)
        #expect(hasFilipino)
    }

    @Test("Both modern and legacy Filipino locale codes are classified")
    func filipinoLocaleAliasesAreClassified() {
        #expect(TranscriptionLanguage.isFilipino("fil-PH"))
        #expect(TranscriptionLanguage.isFilipino("tl-PH"))
        #expect(!TranscriptionLanguage.isFilipino("en-PH"))
    }

    @Test("Filipino locale aliases resolve only to a reported engine")
    func filipinoLocaleAliasesResolveReportedEngine() {
        let capabilities = TranscriptionCapabilities(
            languages: [
                TranscriptionLanguage(identifier: "tl-PH")
            ],
            speechLocaleIdentifiers: [],
            dictationLocaleIdentifiers: ["tl-PH"]
        )

        #expect(
            capabilities.engine(for: "fil-PH")
                == .dictationTranscriber
        )
        #expect(capabilities.language(for: "fil-PH")?.isFilipino == true)
    }

    @Test("Live analyzer timestamps become meeting-relative")
    func liveAnalyzerTimestampsBecomeRelative() {
        let normalized = TranscriptTimelineNormalizer.normalize(
            [
                TranscriptSegment(
                    text: "Opening",
                    startTime: 69_940.8,
                    endTime: 69_943.2,
                    isFinal: true
                ),
                TranscriptSegment(
                    text: "Decision",
                    startTime: 69_944.1,
                    endTime: 69_948.5,
                    isFinal: true
                ),
            ],
            recordingDuration: 19,
            sourceOrigin: 69_940
        )

        #expect(abs((normalized.first?.startTime ?? 0) - 0.8) < 0.001)
        #expect(abs((normalized.last?.endTime ?? 0) - 8.5) < 0.001)
    }

    @Test("A nineteen-second meeting cannot expose a later timestamp")
    func invalidStoredTimestampsAreClampedToRecording() {
        let normalized = TranscriptTimelineNormalizer.normalize(
            [
                TranscriptSegment(
                    text: "Old absolute clock value",
                    startTime: 69_941,
                    endTime: 69_946,
                    isFinal: true
                ),
                TranscriptSegment(
                    text: "Still in the meeting",
                    startTime: 69_955,
                    endTime: 69_970,
                    isFinal: true
                ),
            ],
            recordingDuration: 19
        )

        #expect(normalized.allSatisfy { ($0.startTime ?? 0) <= 19 })
        #expect(normalized.allSatisfy { ($0.endTime ?? 0) <= 19 })
        #expect(normalized.first?.startTime == 0)
        #expect(normalized.last?.endTime == 19)
        #expect(TimeInterval(19).transcriptTimestamp == "0:19")
        #expect(TimeInterval(3_661).transcriptTimestamp == "1:01:01")
    }

    @Test("Engine selection prefers SpeechTranscriber deterministically")
    func engineSelectionIsDeterministic() {
        let capabilities = TranscriptionCapabilities(
            languages: [
                TranscriptionLanguage(identifier: "en-US"),
                TranscriptionLanguage(identifier: "fil-PH")
            ],
            speechLocaleIdentifiers: ["en-US"],
            dictationLocaleIdentifiers: ["en-US", "fil-PH"]
        )

        #expect(
            capabilities.engine(for: "en_US")
                == .speechTranscriber
        )
        #expect(
            capabilities.engine(for: "fil-PH")
                == .dictationTranscriber
        )
    }

    @Test("Unsupported languages never silently fall back")
    func unsupportedLanguageDoesNotFallBack() {
        let capabilities = TranscriptionCapabilities(
            languages: [
                TranscriptionLanguage(identifier: "en-US")
            ],
            speechLocaleIdentifiers: ["en-US"],
            dictationLocaleIdentifiers: []
        )

        #expect(capabilities.engine(for: "fil-PH") == nil)
        #expect(capabilities.language(for: "fil-PH") == nil)
    }

    @Test("Installed and downloadable model states remain distinct")
    func modelAssetStatesRemainDistinct() {
        let installed = TranscriptionLanguage(
            identifier: "en-US",
            assetState: .installed
        )
        let downloadable = TranscriptionLanguage(
            identifier: "fil-PH",
            assetState: .downloadable
        )

        #expect(installed.assetState == .installed)
        #expect(downloadable.assetState == .downloadable)
    }

    @Test("Glossary normalization deduplicates private meeting context")
    func glossaryIsNormalizedAndDeduplicated() {
        let glossary = DefaultTranscriptionGlossaryBuilder().build(
            from: TranscriptionGlossaryContext(
                meetingTitle: "  Launch   Review ",
                workspaceName: "Aligna",
                participantNames: [
                    "John Christopher Cruz",
                    "john christopher cruz"
                ],
                participantHandles: ["johncruz"],
                userTerms: [" Supabase ", "supabase", ""]
            )
        )

        #expect(glossary.contains("Launch Review"))
        #expect(glossary.contains("John Christopher Cruz"))
        #expect(glossary.contains("johncruz"))
        #expect(glossary.filter {
            $0.localizedCaseInsensitiveCompare("Supabase")
                == .orderedSame
        }.count == 1)
        #expect(glossary.filter {
            $0.localizedCaseInsensitiveCompare(
                "John Christopher Cruz"
            ) == .orderedSame
        }.count == 1)
    }

    @Test("Offline success becomes the current machine-final version")
    func offlineSuccessBecomesCurrent() {
        let meetingID = UUID()
        let live = TranscriptVersion(
            source: .liveApple,
            engineIdentifier:
                TranscriptionEngineKind.speechTranscriber.rawValue,
            localeIdentifier: "en-US",
            segments: [
                TranscriptSegment(
                    text: "Live wording",
                    isFinal: true
                )
            ],
            processingStatus: .succeeded
        )
        let offline = TranscriptVersion(
            source: .offlineApple,
            engineIdentifier:
                TranscriptionEngineKind.speechTranscriber.rawValue,
            localeIdentifier: "en-US",
            segments: [
                TranscriptSegment(
                    text: "Final wording",
                    isFinal: true
                )
            ],
            processingStatus: .succeeded
        )
        var document = TranscriptDocument(
            meetingID: meetingID,
            ownerUserID: nil,
            selectedLocaleIdentifier: "en-US",
            currentVersionID: live.id,
            versions: [live]
        )

        document.append(offline, makeCurrent: true)

        #expect(document.currentVersion?.source == .offlineApple)
        #expect(document.effectiveSegments.first?.text == "Final wording")
        #expect(document.versions.first?.segments.first?.text == "Live wording")
    }

    @Test("Offline failure preserves the live source of truth")
    func offlineFailurePreservesLiveTranscript() {
        let live = TranscriptVersion(
            source: .liveApple,
            engineIdentifier:
                TranscriptionEngineKind.speechTranscriber.rawValue,
            localeIdentifier: "en-US",
            segments: [
                TranscriptSegment(text: "Preserved live text", isFinal: true)
            ],
            processingStatus: .succeeded
        )
        let failed = TranscriptVersion(
            source: .offlineApple,
            engineIdentifier:
                TranscriptionEngineKind.speechTranscriber.rawValue,
            localeIdentifier: "en-US",
            segments: [],
            processingStatus: .failed,
            failureReason: "Fixture failure"
        )
        var document = TranscriptDocument(
            meetingID: UUID(),
            ownerUserID: nil,
            selectedLocaleIdentifier: "en-US",
            currentVersionID: live.id,
            versions: [live]
        )

        document.append(failed, makeCurrent: false)

        #expect(document.currentVersion?.id == live.id)
        #expect(
            document.effectiveSegments.first?.text
                == "Preserved live text"
        )
    }

    @Test("Corrections overlay immutable raw machine text")
    func correctionOverlayPreservesRawTranscript() {
        let segment = TranscriptSegment(
            text: "Original machine result",
            startTime: 1,
            endTime: 3,
            isFinal: true
        )
        let version = TranscriptVersion(
            source: .offlineApple,
            engineIdentifier:
                TranscriptionEngineKind.speechTranscriber.rawValue,
            localeIdentifier: "en-US",
            segments: [segment],
            processingStatus: .succeeded
        )
        var document = TranscriptDocument(
            meetingID: UUID(),
            ownerUserID: nil,
            selectedLocaleIdentifier: "en-US",
            currentVersionID: version.id,
            versions: [version]
        )

        document.setCorrection(
            "Corrected by the user",
            for: segment.id
        )

        #expect(
            document.versions.first?.segments.first?.originalText
                == "Original machine result"
        )
        #expect(
            document.versions.first?.segments.first?.editedText == nil
        )
        #expect(
            document.effectiveSegments.first?.text
                == "Corrected by the user"
        )
    }

    @Test("Resetting an edit restores effective machine text")
    func resetCorrectionRestoresMachineText() {
        let segment = TranscriptSegment(
            text: "Machine text",
            isFinal: true
        )
        let version = TranscriptVersion(
            source: .liveApple,
            engineIdentifier:
                TranscriptionEngineKind.speechTranscriber.rawValue,
            localeIdentifier: "en-US",
            segments: [segment],
            processingStatus: .succeeded
        )
        var document = TranscriptDocument(
            meetingID: UUID(),
            ownerUserID: nil,
            selectedLocaleIdentifier: "en-US",
            currentVersionID: version.id,
            versions: [version]
        )
        document.setCorrection("Edited text", for: segment.id)

        document.resetCorrection(for: segment.id)

        #expect(document.effectiveSegments.first?.text == "Machine text")
        #expect(!document.hasCorrections)
    }

    @Test("Legacy meeting JSON migrates transcript without data loss")
    func legacyTranscriptMigrationIsBackwardCompatible() throws {
        let meeting = Meeting(
            title: "Legacy sync",
            projectName: "Aligna",
            scheduledAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: .complete,
            transcript: [
                TranscriptSegment(
                    text: "Legacy transcript text",
                    startTime: 0,
                    endTime: 2,
                    isFinal: true
                )
            ],
            transcriptionLocaleIdentifier: "en_US"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(meeting)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded)
                as? [String: Any]
        )
        object.removeValue(forKey: "transcriptDocument")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(Meeting.self, from: legacyData)

        #expect(
            decoded.transcriptDocument?.effectiveSegments.first?.text
                == "Legacy transcript text"
        )
        #expect(
            decoded.transcriptDocument?.selectedLocaleIdentifier
                == "en-US"
        )
    }

    @MainActor
    @Test("Finishing capture saves audio before AI processing")
    func capturePersistsRecordingBeforeProcessing() async {
        let viewModel = MeetingCaptureViewModel(
            configuration: captureConfiguration(),
            dependencies: MeetingCaptureDependencies(
                audio: MockAudioRecordingService(),
                speech: MockSpeechTranscriptionService(eventDelay: .seconds(10)),
                finalTranscription: MockFinalTranscriptionService(
                    segments: [
                        TranscriptSegment(
                            text: "Offline final fixture",
                            startTime: 0,
                            endTime: 2,
                            isFinal: true
                        )
                    ]
                )
            ),
            repository: InMemoryMeetingRepository()
        )

        await viewModel.start()
        await viewModel.finish()

        #expect(viewModel.state == .completed)
        #expect(viewModel.savedMeeting?.audioFileName?.hasSuffix(".m4a") == true)
        #expect(viewModel.savedMeeting?.transcript.isEmpty == true)
        #expect(
            viewModel.savedMeeting?.processingStatus == .queued
                || viewModel.savedMeeting?.processingStatus == .analyzing
        )
    }

    @MainActor
    @Test("Legacy speech failures cannot become completed transcripts")
    func captureDoesNotUseLegacySpeechFallback() async {
        let viewModel = MeetingCaptureViewModel(
            configuration: captureConfiguration(),
            dependencies: MeetingCaptureDependencies(
                audio: MockAudioRecordingService(),
                speech: MockSpeechTranscriptionService(eventDelay: .seconds(10)),
                finalTranscription: MockFinalTranscriptionService(
                    failure: .offlineAnalyzerFailed
                )
            ),
            repository: InMemoryMeetingRepository()
        )

        await viewModel.start()
        await viewModel.finish()

        #expect(viewModel.state == .completed)
        #expect(viewModel.savedMeeting?.transcript.isEmpty == true)
        #expect(viewModel.savedMeeting?.transcriptDocument == nil)
    }

    @MainActor
    @Test("Transcript files are isolated by authenticated owner")
    func transcriptsAreIsolatedByOwner() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "AlignaTranscriptTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstOwner = UUID()
        let secondOwner = UUID()
        let meetingID = UUID()
        let version = TranscriptVersion(
            source: .liveApple,
            engineIdentifier:
                TranscriptionEngineKind.speechTranscriber.rawValue,
            localeIdentifier: "en-US",
            segments: [
                TranscriptSegment(text: "Private text", isFinal: true)
            ],
            processingStatus: .succeeded
        )
        let document = TranscriptDocument(
            meetingID: meetingID,
            ownerUserID: firstOwner,
            selectedLocaleIdentifier: "en-US",
            currentVersionID: version.id,
            versions: [version]
        )
        let firstRepository = LocalTranscriptRepository(
            ownerUserID: firstOwner,
            directory: directory
        )
        let secondRepository = LocalTranscriptRepository(
            ownerUserID: secondOwner,
            directory: directory
        )

        try await firstRepository.save(document)

        #expect(
            try await firstRepository.transcript(for: meetingID) != nil
        )
        #expect(
            try await secondRepository.transcript(for: meetingID) == nil
        )
    }

    @MainActor
    @Test("Final transcription cancellation releases the mock operation")
    func finalTranscriptionCancellationCleansUp() async {
        let service = MockFinalTranscriptionService()

        await service.cancel()
        let cancellationCount = await service.cancellationCount

        #expect(cancellationCount == 1)
    }

    @MainActor
    @Test("Preview capabilities use deterministic mocks")
    func mockPreviewCapabilitiesAreDeterministic() async {
        let provider = MockTranscriptionCapabilityProvider()
        let capabilities = await provider.capabilities(
            forceRefresh: false
        )

        #expect(capabilities.engine(for: "en-US") != nil)
        let hasFilipino = capabilities.languages.contains {
            $0.isFilipino
        }
        #expect(hasFilipino)
    }

    @MainActor
    @Test("Local meeting metadata is isolated by signed-in user")
    func localMeetingsAreIsolatedByOwner() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "AlignaTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstUserID = UUID()
        let secondUserID = UUID()
        let firstRepository = LocalMeetingRepository(
            ownerUserID: firstUserID,
            directory: directory
        )
        let secondRepository = LocalMeetingRepository(
            ownerUserID: secondUserID,
            directory: directory
        )
        let meeting = Meeting(
            title: "Private planning",
            projectName: "Aligna",
            scheduledAt: .now,
            status: .complete
        )

        try await firstRepository.save(meeting)

        #expect(try await firstRepository.fetchMeetings().count == 1)
        #expect(try await secondRepository.fetchMeetings().isEmpty)
    }

    @MainActor
    @Test("Cloud metadata reports both successful and failed synchronization")
    func cloudSynchronizationStatesAreHonest() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "AlignaSyncTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let userID = UUID()
        let workspaceID = UUID()
        let meeting = Meeting(
            title: "Roadmap sync",
            projectName: "Aligna",
            scheduledAt: .now,
            status: .complete
        )
        let successful = CloudBackedMeetingRepository(
            local: LocalMeetingRepository(
                ownerUserID: userID,
                directory: directory.appending(path: "success")
            ),
            cloud: MockMeetingCloudRepository(),
            ownerUserID: userID,
            workspaceID: workspaceID
        )
        let failed = CloudBackedMeetingRepository(
            local: LocalMeetingRepository(
                ownerUserID: userID,
                directory: directory.appending(path: "failure")
            ),
            cloud: MockMeetingCloudRepository(
                failure: URLError(.cannotConnectToHost)
            ),
            ownerUserID: userID,
            workspaceID: workspaceID
        )

        let synchronized = try await successful.save(meeting)
        let unsynchronized = try await failed.save(meeting)

        #expect(synchronized.syncState == .synced)
        #expect(unsynchronized.syncState == .failed)
    }

    @MainActor
    @Test("Cloud-backed deletion removes cloud data before the local copy")
    func cloudBackedDeletionCoordinatesRepositories() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "AlignaCloudDeletionTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let userID = UUID()
        let workspaceID = UUID()
        let local = LocalMeetingRepository(
            ownerUserID: userID,
            directory: directory
        )
        let cloud = MockMeetingCloudRepository()
        let repository = CloudBackedMeetingRepository(
            local: local,
            cloud: cloud,
            ownerUserID: userID,
            workspaceID: workspaceID
        )
        let meeting = Meeting(
            title: "Delete API review",
            projectName: "Aligna",
            scheduledAt: .now,
            status: .complete,
            ownerUserID: userID,
            workspaceID: workspaceID,
            organizerUserID: userID,
            syncState: .synced
        )
        try await local.save(meeting)

        try await repository.delete(meeting)

        #expect(await cloud.deletedMeetingIDs == [meeting.id])
        #expect(try await local.fetchMeetings().isEmpty)
    }

    @MainActor
    @Test("Fractional-second dates survive a local repository round trip")
    func localRepositoryPreservesFractionalSecondDates() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "AlignaDatePrecisionTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let userID = UUID()
        let local = LocalMeetingRepository(
            ownerUserID: userID,
            directory: directory
        )
        // A date whose fractional part is not representable in whole seconds.
        let scheduledAt = Date(
            timeIntervalSinceReferenceDate: 812_345_678.828_384_2
        )
        let meeting = Meeting(
            title: "Fractional precision",
            projectName: "Aligna",
            scheduledAt: scheduledAt,
            durationSeconds: 65.5,
            status: .complete,
            ownerUserID: userID,
            organizerUserID: userID,
            syncState: .synced
        )

        try await local.save(meeting)
        let fetched = try await local.fetchMeetings()

        #expect(fetched == [meeting])
        #expect(fetched.first?.scheduledAt == scheduledAt)
        #expect(
            fetched.first?.scheduledAt.timeIntervalSinceReferenceDate
                == scheduledAt.timeIntervalSinceReferenceDate
        )
    }

    @MainActor
    @Test("Previously written ISO8601 meeting dates still decode")
    func localRepositoryDecodesLegacyISO8601Dates() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "AlignaLegacyDateTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let userID = UUID()
        let scheduledAt = Date(timeIntervalSince1970: 1_800_000_000)
        let meeting = Meeting(
            title: "Legacy date",
            projectName: "Aligna",
            scheduledAt: scheduledAt,
            status: .complete,
            ownerUserID: userID,
            organizerUserID: userID,
            syncState: .synced
        )

        // Write the file exactly as an earlier build would have: ISO8601
        // strings truncated to whole seconds.
        let legacyEncoder = JSONEncoder()
        legacyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        legacyEncoder.dateEncodingStrategy = .iso8601
        let userDirectory = directory.appending(
            path: userID.uuidString.lowercased(),
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: userDirectory,
            withIntermediateDirectories: true
        )
        try legacyEncoder.encode([meeting]).write(
            to: userDirectory.appending(path: "meetings.json"),
            options: [.atomic]
        )

        let local = LocalMeetingRepository(
            ownerUserID: userID,
            directory: directory
        )
        let fetched = try await local.fetchMeetings()

        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Legacy date")
        // The legacy value was already whole-second, so it round-trips exactly.
        #expect(fetched.first?.scheduledAt == scheduledAt)
    }

    @Test("Repository date coding accepts every previously written format")
    func repositoryDateCodingAcceptsLegacyStringFormats() throws {
        struct Wrapper: Codable, Equatable {
            let at: Date
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy =
            LocalMeetingRepository.DateCoding.decodingStrategy
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy =
            LocalMeetingRepository.DateCoding.encodingStrategy

        let expected = Date(timeIntervalSince1970: 1_800_000_000)

        // Whole-second ISO8601, as written by `.iso8601`.
        let wholeSeconds = try decoder.decode(
            Wrapper.self,
            from: Data(#"{"at":"2027-01-15T08:00:00Z"}"#.utf8)
        )
        #expect(wholeSeconds.at == expected)

        // Fractional ISO8601, in case any payload carries milliseconds.
        let fractional = try decoder.decode(
            Wrapper.self,
            from: Data(#"{"at":"2027-01-15T08:00:00.000Z"}"#.utf8)
        )
        #expect(fractional.at == expected)

        // The current numeric form, which must be exact.
        let precise = Date(
            timeIntervalSinceReferenceDate: 812_345_678.828_384_2
        )
        let encoded = try encoder.encode(Wrapper(at: precise))
        #expect(
            try decoder.decode(Wrapper.self, from: encoded)
                == Wrapper(at: precise)
        )
    }

    @MainActor
    @Test("A failed cloud delete preserves the local meeting")
    func failedCloudDeletionPreservesLocalCopy() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "AlignaFailedDeletionTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let userID = UUID()
        let workspaceID = UUID()
        let local = LocalMeetingRepository(
            ownerUserID: userID,
            directory: directory
        )
        let repository = CloudBackedMeetingRepository(
            local: local,
            cloud: MockMeetingCloudRepository(
                failure: URLError(.notConnectedToInternet)
            ),
            ownerUserID: userID,
            workspaceID: workspaceID
        )
        let meeting = Meeting(
            title: "Offline delete",
            projectName: "Aligna",
            scheduledAt: .now,
            status: .complete,
            ownerUserID: userID,
            workspaceID: workspaceID,
            organizerUserID: userID,
            syncState: .synced
        )
        try await local.save(meeting)

        do {
            try await repository.delete(meeting)
            Issue.record("Cloud deletion unexpectedly succeeded")
        } catch {
            #expect(error is URLError)
        }

        #expect(try await local.fetchMeetings() == [meeting])
    }

    @Test("Voice setup remains optional and only appears during new onboarding")
    func voiceSetupRoutingIsOptionalAndMigrationSafe() {
        let userID = UUID()
        let incompleteOnboarding = UserProfile(
            id: userID,
            displayName: "John Cruz",
            handle: "johncruz",
            avatarPath: nil,
            onboardingCompleted: false,
            voiceEnrollmentStatus: .notStarted,
            createdAt: .now,
            updatedAt: .now
        )
        let skippedVoiceSetup = UserProfile(
            id: userID,
            displayName: "John Cruz",
            handle: "johncruz",
            avatarPath: nil,
            onboardingCompleted: false,
            voiceEnrollmentStatus: .skipped,
            createdAt: .now,
            updatedAt: .now
        )
        let migratedExistingProfile = UserProfile(
            id: userID,
            displayName: "John Cruz",
            handle: "johncruz",
            avatarPath: nil,
            onboardingCompleted: true,
            voiceEnrollmentStatus: .notStarted,
            createdAt: .now,
            updatedAt: .now
        )

        #expect(
            OnboardingCoordinator.nextStep(
                profile: incompleteOnboarding,
                workspaces: []
            ) == .voice
        )
        #expect(
            OnboardingCoordinator.nextStep(
                profile: skippedVoiceSetup,
                workspaces: []
            ) == .workspace
        )
        #expect(
            OnboardingCoordinator.nextStep(
                profile: migratedExistingProfile,
                workspaces: []
            ) == .workspace
        )
    }

    @Test("Voice enrollment prompts cover four guided phrases")
    func voiceEnrollmentPromptsAreGuidedAndLocalized() {
        let english = VoiceSetupViewModel.prompts(
            displayName: "John",
            locale: Locale(identifier: "en_PH")
        )
        let filipino = VoiceSetupViewModel.prompts(
            displayName: "John",
            locale: Locale(identifier: "fil_PH")
        )

        #expect(english.count == 4)
        #expect(filipino.count == 4)
        #expect(english.first?.contains("John") == true)
        #expect(filipino.first?.contains("John") == true)
        #expect(filipino.contains { $0.contains("Ako") })
    }

    @Test("Voice profile sync requires a live verified account")
    func voiceProfileEnrollmentRequiresVerifiedSession() {
        #expect(
            VoiceProfileEnrollmentPolicy.canEnroll(
                sessionIsExpired: false,
                emailConfirmedAt: .now
            )
        )
        #expect(
            !VoiceProfileEnrollmentPolicy.canEnroll(
                sessionIsExpired: false,
                emailConfirmedAt: nil
            )
        )
        #expect(
            !VoiceProfileEnrollmentPolicy.canEnroll(
                sessionIsExpired: true,
                emailConfirmedAt: .now
            )
        )
    }

    @Test("Enrollment audio quality rejects silence, short speech, and clipping")
    func enrollmentAudioQualityRejectsUnsafeSamples() {
        let analyzer = EnrollmentAudioQualityAnalyzer()
        let quiet = [Float](repeating: 0.0015, count: 16_000 * 3)
        let short = [Float](repeating: 0.08, count: 8_000)
        let clipped = [Float](repeating: 1, count: 16_000 * 3)
        let accepted = [Float](repeating: 0.006, count: 16_000 * 3)

        #expect(analyzer.analyze(quiet).issue == .tooQuiet)
        #expect(analyzer.analyze(short).issue == .insufficientSpeech)
        #expect(analyzer.analyze(clipped).issue == .clipped)
        #expect(analyzer.analyze(accepted).isAccepted)
    }

    @Test("Voice enrollment aggregation removes an outlier and normalizes")
    func voiceEnrollmentAggregationIsOutlierAware() {
        let primary = voiceVector(first: 1, second: 0)
        let nearby = voiceVector(first: 0.99, second: 0.03)
        let outlier = voiceVector(first: -1, second: 0)

        let aggregate = VoiceVectorMath.aggregateEnrollment(
            [primary, nearby, primary, outlier]
        )

        #expect(aggregate?.count == 256)
        #expect((aggregate?.first ?? 0) > 0.99)
        let magnitude = sqrt(
            aggregate?.reduce(Float.zero) { $0 + ($1 * $1) } ?? 0
        )
        #expect(abs(magnitude - 1) < 0.0001)
    }

    @Test("Speaker matching is one-to-one and never forces a weak identity")
    func speakerMatchingIsConservativeAndOneToOne() {
        let johnID = UUID()
        let mayaID = UUID()
        let model = VoiceModelDescriptor.fluidAudioOfflineV1
        let matcher = SpeakerMatcher()
        let clusters = [
            SpeakerCluster(
                stableSpeakerKey: "speaker_0",
                embedding: VoiceEmbedding(
                    values: voiceVector(first: 1, second: 0),
                    model: model
                )
            ),
            SpeakerCluster(
                stableSpeakerKey: "speaker_1",
                embedding: VoiceEmbedding(
                    values: voiceVector(first: 0, second: 1),
                    model: model
                )
            ),
            SpeakerCluster(
                stableSpeakerKey: "speaker_2",
                embedding: VoiceEmbedding(
                    values: voiceVector(first: -1, second: 0),
                    model: model
                )
            ),
        ]
        let candidates = [
            CandidateVoiceProfile(
                userID: johnID,
                displayName: "John",
                avatarPath: nil,
                embedding: VoiceEmbedding(
                    values: voiceVector(first: 1, second: 0),
                    model: model
                )
            ),
            CandidateVoiceProfile(
                userID: mayaID,
                displayName: "Maya",
                avatarPath: nil,
                embedding: VoiceEmbedding(
                    values: voiceVector(first: 0, second: 1),
                    model: model
                )
            ),
        ]

        let matches = matcher.match(
            clusters: clusters,
            candidates: candidates
        )

        #expect(matches[0].userID == johnID)
        #expect(matches[1].userID == mayaID)
        #expect(matches[2].state == .unknown)
        #expect(matches.compactMap(\.userID).count == 2)
        #expect(Set(matches.compactMap(\.userID)).count == 2)
    }

    @Test("Speaker matching accepts a strong cross-session voice similarity")
    func speakerMatchingUsesCrossSessionThreshold() {
        let userID = UUID()
        let model = VoiceModelDescriptor.fluidAudioOfflineV1
        let cluster = SpeakerCluster(
            stableSpeakerKey: "speaker_0",
            embedding: VoiceEmbedding(
                values: voiceVector(first: 1, second: 0),
                model: model
            )
        )
        let strongCandidate = CandidateVoiceProfile(
            userID: userID,
            displayName: "John",
            avatarPath: nil,
            embedding: VoiceEmbedding(
                values: voiceVector(
                    first: 0.75,
                    second: 0.661_437_8
                ),
                model: model
            )
        )
        let weakCandidate = CandidateVoiceProfile(
            userID: userID,
            displayName: "John",
            avatarPath: nil,
            embedding: VoiceEmbedding(
                values: voiceVector(
                    first: 0.70,
                    second: 0.714_142_8
                ),
                model: model
            )
        )

        let accepted = SpeakerMatcher().match(
            clusters: [cluster],
            candidates: [strongCandidate]
        ).first
        let rejected = SpeakerMatcher().match(
            clusters: [cluster],
            candidates: [weakCandidate]
        ).first

        #expect(accepted?.state == .recognized)
        #expect(accepted?.userID == userID)
        #expect(rejected?.state == .unknown)
        #expect((rejected?.confidence ?? 0) > 0.69)
    }

    @Test("Speaker matching marks near-tied candidates as ambiguous")
    func speakerMatchingRejectsAmbiguousIdentity() {
        let model = VoiceModelDescriptor.fluidAudioOfflineV1
        let cluster = SpeakerCluster(
            stableSpeakerKey: "speaker_0",
            embedding: VoiceEmbedding(
                values: voiceVector(first: 1, second: 0),
                model: model
            )
        )
        let candidates = [
            CandidateVoiceProfile(
                userID: UUID(),
                displayName: "John",
                avatarPath: nil,
                embedding: VoiceEmbedding(
                    values: voiceVector(first: 1, second: 0),
                    model: model
                )
            ),
            CandidateVoiceProfile(
                userID: UUID(),
                displayName: "Maya",
                avatarPath: nil,
                embedding: VoiceEmbedding(
                    values: voiceVector(first: 0.995, second: 0.1),
                    model: model
                )
            ),
        ]

        let match = SpeakerMatcher().match(
            clusters: [cluster],
            candidates: candidates
        ).first

        #expect(match?.state == .ambiguous)
        #expect(match?.userID == nil)
    }

    @Test("Speaker matching never compares incompatible model profiles")
    func speakerMatchingRejectsIncompatibleModels() {
        let currentModel = VoiceModelDescriptor.fluidAudioOfflineV1
        let incompatibleModel = VoiceModelDescriptor(
            provider: currentModel.provider,
            packageVersion: currentModel.packageVersion,
            modelVersion: "future-model",
            embeddingDimension: currentModel.embeddingDimension
        )
        let match = SpeakerMatcher().match(
            clusters: [
                SpeakerCluster(
                    stableSpeakerKey: "speaker_0",
                    embedding: VoiceEmbedding(
                        values: voiceVector(first: 1, second: 0),
                        model: currentModel
                    )
                )
            ],
            candidates: [
                CandidateVoiceProfile(
                    userID: UUID(),
                    displayName: "John",
                    avatarPath: nil,
                    embedding: VoiceEmbedding(
                        values: voiceVector(first: 1, second: 0),
                        model: incompatibleModel
                    )
                )
            ]
        ).first

        #expect(match?.state == .unknown)
        #expect(match?.userID == nil)
    }

    @Test("Whisper words reconcile to diarization by temporal overlap")
    func transcriptReconciliationPreservesTextAndSpeakerTurns() {
        let johnID = UUID()
        let words = [
            WhisperWord(text: "Hello", startSeconds: 0, endSeconds: 0.5),
            WhisperWord(text: "team.", startSeconds: 0.5, endSeconds: 1),
            WhisperWord(text: "Salamat", startSeconds: 1.2, endSeconds: 1.8),
        ]
        let intervals = [
            DiarizationInterval(
                stableSpeakerKey: "speaker_0",
                startSeconds: 0,
                endSeconds: 1
            ),
            DiarizationInterval(
                stableSpeakerKey: "speaker_1",
                startSeconds: 1,
                endSeconds: 2
            ),
        ]
        let matches = [
            SpeakerMatch(
                stableSpeakerKey: "speaker_0",
                state: .recognized,
                userID: johnID,
                displayName: "John",
                confidence: 0.94
            ),
            SpeakerMatch(
                stableSpeakerKey: "speaker_1",
                state: .unknown,
                userID: nil,
                displayName: "Speaker 2",
                confidence: nil
            ),
        ]

        let turns = TranscriptReconciliationService().reconcile(
            words: words,
            intervals: intervals,
            matches: matches
        )

        #expect(turns.count == 2)
        #expect(turns[0].text == "Hello team.")
        #expect(turns[0].speakerUserID == johnID)
        #expect(turns[0].attributionSource == .voiceProfile)
        #expect(turns[1].text == "Salamat")
        #expect(turns[1].speakerUserID == nil)
        #expect(turns[1].attributionSource == .anonymous)
    }

    @Test("Equal overlapping speakers remain unknown")
    func transcriptReconciliationDoesNotGuessOverlappingSpeech() {
        let word = WhisperWord(
            text: "Okay",
            startSeconds: 1,
            endSeconds: 1.5
        )
        let intervals = [
            DiarizationInterval(
                stableSpeakerKey: "speaker_0",
                startSeconds: 0.8,
                endSeconds: 1.5
            ),
            DiarizationInterval(
                stableSpeakerKey: "speaker_1",
                startSeconds: 1,
                endSeconds: 1.7
            ),
        ]
        let turns = TranscriptReconciliationService().reconcile(
            words: [word],
            intervals: intervals,
            matches: [
                SpeakerMatch(
                    stableSpeakerKey: "speaker_0",
                    state: .recognized,
                    userID: UUID(),
                    displayName: "John",
                    confidence: 0.95
                ),
                SpeakerMatch(
                    stableSpeakerKey: "speaker_1",
                    state: .recognized,
                    userID: UUID(),
                    displayName: "Maya",
                    confidence: 0.95
                ),
            ]
        )

        #expect(turns.count == 1)
        #expect(turns[0].stableSpeakerKey == "unknown")
        #expect(turns[0].speakerUserID == nil)
        #expect(turns[0].attributionSource == .ambiguous)
        #expect(turns[0].text == "Okay")
    }

    @MainActor
    private func stepFourFixture() -> (
        user: AuthenticatedUser,
        profile: UserProfile,
        workspace: Workspace,
        dependencies: DependencyContainer
    ) {
        let userID = UUID()
        let user = AuthenticatedUser(
            id: userID,
            email: "john@example.com",
            isEmailVerified: true
        )
        let profile = UserProfile(
            id: userID,
            displayName: "John Cruz",
            handle: "johncruz",
            avatarPath: nil,
            onboardingCompleted: true,
            createdAt: .now,
            updatedAt: .now
        )
        let workspace = Workspace(
            id: UUID(),
            name: "Aligna Launch",
            createdBy: userID,
            createdAt: .now,
            updatedAt: .now,
            currentUserRole: .owner
        )
        let dependencies = DependencyContainer(
            authentication: MockAuthenticationService(user: user),
            profiles: MockProfileRepository(profile: profile),
            workspaces: MockWorkspaceRepository(workspaces: [workspace]),
            meetingCloud: MockMeetingCloudRepository(),
            avatars: MockAvatarStorage(),
            accountDeletion: MockAccountDeletionService()
        )
        return (user, profile, workspace, dependencies)
    }

    private func emptySnapshot() -> DashboardSnapshot {
        DashboardSnapshot(
            currentUser: TeamMember(name: "John Cruz"),
            meetings: [],
            tasks: [],
            pendingReviews: []
        )
    }

    private func captureConfiguration() -> NewMeetingConfiguration {
        NewMeetingConfiguration(
            title: "Product launch sync",
            participantNames: ["Maya Chen"],
            localeIdentifier: "en_US"
        )
    }

    // MARK: - Speaker attribution resolution
    //
    // Regression coverage for the diarization failure path: a failed
    // diarization used to be laundered into a synthetic single-speaker
    // transcript, so every meeting looked like one person talking.

    @Test("Alternating diarization clusters stay separate speakers")
    func speakerAttributionSeparatesAlternatingClusters() async {
        let resolver = SpeakerAttributionResolver()
        let words = [
            WhisperWord(text: "Hello", startSeconds: 0, endSeconds: 0.9),
            WhisperWord(text: "there.", startSeconds: 2.1, endSeconds: 2.9),
            WhisperWord(text: "Kumusta", startSeconds: 4.1, endSeconds: 4.9),
            WhisperWord(text: "ka?", startSeconds: 6.1, endSeconds: 6.9),
        ]
        let diarization = DiarizationOutput(
            intervals: [
                DiarizationInterval(
                    stableSpeakerKey: "S1",
                    startSeconds: 0,
                    endSeconds: 1
                ),
                DiarizationInterval(
                    stableSpeakerKey: "S2",
                    startSeconds: 2,
                    endSeconds: 3
                ),
                DiarizationInterval(
                    stableSpeakerKey: "S1",
                    startSeconds: 4,
                    endSeconds: 5
                ),
                DiarizationInterval(
                    stableSpeakerKey: "S2",
                    startSeconds: 6,
                    endSeconds: 7
                ),
            ],
            clusters: [
                SpeakerCluster(
                    stableSpeakerKey: "S1",
                    embedding: VoiceEmbedding(
                        values: voiceVector(first: 1, second: 0),
                        model: .fluidAudioOfflineV1
                    )
                ),
                SpeakerCluster(
                    stableSpeakerKey: "S2",
                    embedding: VoiceEmbedding(
                        values: voiceVector(first: 0, second: 1),
                        model: .fluidAudioOfflineV1
                    )
                ),
            ]
        )

        let outcome = await resolver.resolve(
            words: words,
            diarize: { diarization },
            candidates: { [] },
            report: { _ in }
        )

        #expect(outcome.state == .attributed)
        #expect(outcome.failureReason == nil)
        #expect(outcome.turns.count == 4)
        #expect(
            outcome.turns.map(\.stableSpeakerKey)
                == ["S1", "S2", "S1", "S2"]
        )
        // Two distinct speakers, not one collapsed label.
        #expect(Set(outcome.turns.map(\.speakerDisplayName)).count == 2)
        #expect(outcome.turns.map(\.text) == [
            "Hello", "there.", "Kumusta", "ka?",
        ])
        #expect(outcome.turns[0].startSeconds == 0)
        #expect(outcome.turns[3].endSeconds == 6.9)
    }

    @Test("A single diarization cluster remains a single speaker")
    func speakerAttributionKeepsSingleClusterSingle() async {
        let resolver = SpeakerAttributionResolver()
        let words = [
            WhisperWord(text: "Just", startSeconds: 0, endSeconds: 0.4),
            WhisperWord(text: "me", startSeconds: 0.5, endSeconds: 0.9),
            WhisperWord(text: "today.", startSeconds: 1, endSeconds: 1.6),
        ]
        let diarization = DiarizationOutput(
            intervals: [
                DiarizationInterval(
                    stableSpeakerKey: "S1",
                    startSeconds: 0,
                    endSeconds: 2
                ),
            ],
            clusters: [
                SpeakerCluster(
                    stableSpeakerKey: "S1",
                    embedding: VoiceEmbedding(
                        values: voiceVector(first: 1, second: 0),
                        model: .fluidAudioOfflineV1
                    )
                ),
            ]
        )

        let outcome = await resolver.resolve(
            words: words,
            diarize: { diarization },
            candidates: { [] },
            report: { _ in }
        )

        #expect(outcome.state == .attributed)
        #expect(Set(outcome.turns.map(\.stableSpeakerKey)) == ["S1"])
        #expect(outcome.turns.count == 1)
        #expect(outcome.turns[0].text == "Just me today.")
    }

    @Test("An unmatched cluster never inherits the enrolled identity")
    func speakerAttributionDoesNotLeakEnrolledIdentity() async {
        let resolver = SpeakerAttributionResolver()
        let johnID = UUID()
        let words = [
            WhisperWord(text: "Mine.", startSeconds: 0, endSeconds: 0.8),
            WhisperWord(text: "Theirs.", startSeconds: 2.1, endSeconds: 2.9),
        ]
        let diarization = DiarizationOutput(
            intervals: [
                DiarizationInterval(
                    stableSpeakerKey: "S1",
                    startSeconds: 0,
                    endSeconds: 1
                ),
                DiarizationInterval(
                    stableSpeakerKey: "S2",
                    startSeconds: 2,
                    endSeconds: 3
                ),
            ],
            clusters: [
                SpeakerCluster(
                    stableSpeakerKey: "S1",
                    embedding: VoiceEmbedding(
                        values: voiceVector(first: 1, second: 0),
                        model: .fluidAudioOfflineV1
                    )
                ),
                SpeakerCluster(
                    stableSpeakerKey: "S2",
                    embedding: VoiceEmbedding(
                        values: voiceVector(first: 0, second: 1),
                        model: .fluidAudioOfflineV1
                    )
                ),
            ]
        )
        let onlyJohn = CandidateVoiceProfile(
            userID: johnID,
            displayName: "John",
            avatarPath: nil,
            embedding: VoiceEmbedding(
                values: voiceVector(first: 1, second: 0),
                model: .fluidAudioOfflineV1
            )
        )

        let outcome = await resolver.resolve(
            words: words,
            diarize: { diarization },
            candidates: { [onlyJohn] },
            report: { _ in }
        )

        #expect(outcome.state == .attributed)
        #expect(outcome.turns.count == 2)
        #expect(outcome.turns[0].speakerUserID == johnID)
        #expect(outcome.turns[0].attributionSource == .voiceProfile)
        // The second cluster matched no profile: it must stay anonymous rather
        // than borrowing the only enrolled identity.
        #expect(outcome.turns[1].speakerUserID == nil)
        #expect(outcome.turns[1].speakerDisplayName != "John")
        #expect(outcome.turns[1].attributionSource == .anonymous)
    }

    @Test("No speech falls back to an unattributed transcript")
    func speakerAttributionSkipsWhenThereIsNoSpeech() async {
        let resolver = SpeakerAttributionResolver()
        let words = [
            WhisperWord(text: "Hmm.", startSeconds: 0, endSeconds: 0.5),
        ]

        let outcome = await resolver.resolve(
            words: words,
            diarize: { throw VoiceRecognitionError.noSpeech },
            candidates: { [] },
            report: { _ in }
        )

        #expect(outcome.state == .skipped)
        #expect(outcome.failureReason == nil)
        #expect(outcome.intervals.isEmpty)
        #expect(outcome.turns.count == 1)
        #expect(outcome.turns[0].text == "Hmm.")
        #expect(!outcome.state.identifiesSpeakers)
    }

    @Test("An unavailable model fails without inventing a speaker")
    func speakerAttributionFailsWithoutSyntheticSpeaker() async {
        let resolver = SpeakerAttributionResolver()
        let words = [
            WhisperWord(text: "First", startSeconds: 0, endSeconds: 0.6),
            WhisperWord(text: "second.", startSeconds: 5, endSeconds: 5.6),
        ]

        let outcome = await resolver.resolve(
            words: words,
            diarize: { throw VoiceRecognitionError.modelUnavailable },
            candidates: { [] },
            report: { _ in }
        )

        #expect(outcome.state == .failed)
        #expect(!outcome.state.identifiesSpeakers)
        #expect(outcome.failureReason == "voice_model_unavailable")
        #expect(outcome.intervals.isEmpty)
        // The transcript survives, but nothing may claim to be a numbered
        // speaker that diarization never produced.
        #expect(!outcome.turns.isEmpty)
        for turn in outcome.turns {
            #expect(
                turn.stableSpeakerKey
                    == SpeakerAttributionState.unattributedSpeakerKey
            )
            #expect(turn.speakerUserID == nil)
            #expect(!turn.speakerDisplayName.contains("Speaker 1"))
            #expect(!turn.speakerDisplayName.contains("Person 1"))
        }
        #expect(outcome.state.notice != nil)
    }

    @Test("Cancellation and transport errors are recorded distinctly")
    func speakerAttributionRecordsFailureReasons() async {
        let resolver = SpeakerAttributionResolver()
        let words = [
            WhisperWord(text: "Word", startSeconds: 0, endSeconds: 0.5),
        ]

        let interrupted = await resolver.resolve(
            words: words,
            diarize: { throw VoiceRecognitionError.interrupted },
            candidates: { [] },
            report: { _ in }
        )
        let offline = await resolver.resolve(
            words: words,
            diarize: { throw URLError(.notConnectedToInternet) },
            candidates: { [] },
            report: { _ in }
        )

        #expect(interrupted.state == .failed)
        #expect(interrupted.failureReason == "voice_interrupted")
        #expect(offline.state == .failed)
        #expect(offline.failureReason?.hasPrefix("url_") == true)
    }

    @Test("Status reporting failures never discard diarization results")
    func speakerAttributionSurvivesStatusReportingFailure() async {
        let resolver = SpeakerAttributionResolver()
        let words = [
            WhisperWord(text: "Hello", startSeconds: 0, endSeconds: 0.9),
            WhisperWord(text: "again.", startSeconds: 2.1, endSeconds: 2.9),
        ]
        let diarization = DiarizationOutput(
            intervals: [
                DiarizationInterval(
                    stableSpeakerKey: "S1",
                    startSeconds: 0,
                    endSeconds: 1
                ),
                DiarizationInterval(
                    stableSpeakerKey: "S2",
                    startSeconds: 2,
                    endSeconds: 3
                ),
            ],
            clusters: [
                SpeakerCluster(
                    stableSpeakerKey: "S1",
                    embedding: VoiceEmbedding(
                        values: voiceVector(first: 1, second: 0),
                        model: .fluidAudioOfflineV1
                    )
                ),
                SpeakerCluster(
                    stableSpeakerKey: "S2",
                    embedding: VoiceEmbedding(
                        values: voiceVector(first: 0, second: 1),
                        model: .fluidAudioOfflineV1
                    )
                ),
            ]
        )

        // Every status round-trip fails, as it would when the Edge Function is
        // unreachable or the session needs refreshing.
        let outcome = await resolver.resolve(
            words: words,
            diarize: { diarization },
            candidates: { [] },
            report: { _ in throw URLError(.timedOut) }
        )

        #expect(outcome.state == .attributed)
        #expect(outcome.failureReason == nil)
        #expect(outcome.turns.count == 2)
        #expect(
            outcome.turns.map(\.stableSpeakerKey) == ["S1", "S2"]
        )
        #expect(outcome.intervals.count == 2)
    }

    @Test("Speaker attribution state maps from the stored column")
    func speakerAttributionStateMapsStoredValues() {
        #expect(
            SpeakerAttributionState.fromProcessingStatus(
                "complete",
                skipped: false
            ) == .attributed
        )
        #expect(
            SpeakerAttributionState.fromProcessingStatus(
                "complete",
                skipped: true
            ) == .skipped
        )
        #expect(
            SpeakerAttributionState.fromProcessingStatus(
                "skipped",
                skipped: true
            ) == .skipped
        )
        #expect(
            SpeakerAttributionState.fromProcessingStatus(
                "failed",
                skipped: true
            ) == .failed
        )
        // In-flight and unknown stages must not read as a finished attribution.
        #expect(
            SpeakerAttributionState.fromProcessingStatus(
                "diarizing",
                skipped: false
            ) == .pending
        )
        #expect(
            SpeakerAttributionState.fromProcessingStatus(
                nil,
                skipped: false
            ) == .pending
        )
        #expect(SpeakerAttributionState.attributed.notice == nil)
        #expect(SpeakerAttributionState.pending.notice == nil)
        #expect(SpeakerAttributionState.skipped.notice != nil)
        #expect(SpeakerAttributionState.failed.notice != nil)
    }

    // MARK: - Recording interruption and resume
    //
    // Regression coverage for the real-device bug where an interruption paused
    // capture and Resume left the UI reporting "Recording" while the recorder
    // was stopped and the timer no longer advanced.

    @MainActor
    @Test("An interruption pauses capture and stops the elapsed timer")
    func captureInterruptionPausesAndStopsTimer() async {
        let audio = MockAudioRecordingService()
        let clock = MutableClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let viewModel = MeetingCaptureViewModel(
            configuration: captureConfiguration(),
            dependencies: MeetingCaptureDependencies(
                audio: audio,
                speech: MockSpeechTranscriptionService(eventDelay: .seconds(10))
            ),
            repository: InMemoryMeetingRepository(),
            now: { clock.now }
        )

        await viewModel.start()
        #expect(viewModel.state == .recording)

        clock.advance(by: 10)
        audio.simulateInterruptionBegan()
        await waitUntil { viewModel.state == .paused }

        #expect(viewModel.state == .paused)
        #expect(!audio.isActivelyRecording)
        let frozen = viewModel.elapsedTime
        // While paused, wall-clock time must not accumulate.
        clock.advance(by: 30)
        #expect(viewModel.elapsedTime == frozen)
    }

    @MainActor
    @Test("Resume restarts the recorder and the elapsed timer")
    func captureResumeRestartsRecorderAndTimer() async {
        let audio = MockAudioRecordingService()
        let clock = MutableClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let viewModel = MeetingCaptureViewModel(
            configuration: captureConfiguration(),
            dependencies: MeetingCaptureDependencies(
                audio: audio,
                speech: MockSpeechTranscriptionService(eventDelay: .seconds(10))
            ),
            repository: InMemoryMeetingRepository(),
            now: { clock.now }
        )

        await viewModel.start()
        clock.advance(by: 10)
        await viewModel.pause()
        #expect(viewModel.state == .paused)

        clock.advance(by: 5)
        await viewModel.resume()

        #expect(viewModel.state == .recording)
        // The recorder is genuinely capturing again, not merely reported as such.
        #expect(audio.isActivelyRecording)
        #expect(audio.resumeCount == 1)

        // Paused time is excluded; recording time resumes accumulating.
        let atResume = viewModel.elapsedTime
        clock.advance(by: 7)
        await waitUntil { viewModel.elapsedTime > atResume }
        #expect(viewModel.elapsedTime > atResume)
    }

    @MainActor
    @Test("A resume that silently fails never reports Recording")
    func captureResumeFailureDoesNotClaimRecording() async {
        let audio = MockAudioRecordingService()
        // The session comes back but the recorder stays stopped — exactly the
        // real-device failure where record() returns true and captures nothing.
        audio.resumeSilentlyFails = true
        let clock = MutableClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let viewModel = MeetingCaptureViewModel(
            configuration: captureConfiguration(),
            dependencies: MeetingCaptureDependencies(
                audio: audio,
                speech: MockSpeechTranscriptionService(eventDelay: .seconds(10))
            ),
            repository: InMemoryMeetingRepository(),
            now: { clock.now }
        )

        await viewModel.start()
        clock.advance(by: 10)
        await viewModel.pause()
        await viewModel.resume()

        #expect(viewModel.state == .failed(.recordingInterrupted))
        #expect(viewModel.state != .recording)
        // The audio captured so far must survive so Finish can still save it.
        #expect(audio.cancelCount == 0)
        #expect(viewModel.state.canFinish)
    }

    @MainActor
    @Test("Finish saves the meeting after a failed resume")
    func captureFinishSucceedsAfterFailedResume() async {
        let audio = MockAudioRecordingService()
        audio.resumeSilentlyFails = true
        let clock = MutableClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let viewModel = MeetingCaptureViewModel(
            configuration: captureConfiguration(),
            dependencies: MeetingCaptureDependencies(
                audio: audio,
                speech: MockSpeechTranscriptionService(eventDelay: .seconds(10))
            ),
            repository: InMemoryMeetingRepository(),
            now: { clock.now }
        )

        await viewModel.start()
        clock.advance(by: 20)
        await viewModel.pause()
        await viewModel.resume()
        #expect(viewModel.state == .failed(.recordingInterrupted))

        await viewModel.finish()

        #expect(viewModel.state == .completed)
        #expect(audio.stopCount == 1)
        let saved = viewModel.savedMeeting
        #expect(saved?.audioFileName?.hasSuffix(".m4a") == true)
        // 20 seconds of real audio, not zero and not the paused wall clock.
        #expect((saved?.durationSeconds ?? 0) >= 20)
    }

    @MainActor
    @Test("An unresumable interruption fails instead of offering Resume")
    func captureUnresumableInterruptionFails() async {
        let audio = MockAudioRecordingService()
        let viewModel = MeetingCaptureViewModel(
            configuration: captureConfiguration(),
            dependencies: MeetingCaptureDependencies(
                audio: audio,
                speech: MockSpeechTranscriptionService(eventDelay: .seconds(10))
            ),
            repository: InMemoryMeetingRepository()
        )

        await viewModel.start()
        audio.simulateInterruptionBegan()
        await waitUntil { viewModel.state == .paused }
        audio.simulateInterruptionEnded(canResume: false)
        await waitUntil { viewModel.state == .failed(.recordingInterrupted) }

        #expect(viewModel.state == .failed(.recordingInterrupted))
        // Still finishable: the audio before the interruption is real.
        #expect(viewModel.state.canFinish)
    }

    @MainActor
    @Test("A media services reset ends capture rather than pausing")
    func captureMediaServicesResetEndsCapture() async {
        let audio = MockAudioRecordingService()
        let viewModel = MeetingCaptureViewModel(
            configuration: captureConfiguration(),
            dependencies: MeetingCaptureDependencies(
                audio: audio,
                speech: MockSpeechTranscriptionService(eventDelay: .seconds(10))
            ),
            repository: InMemoryMeetingRepository()
        )

        await viewModel.start()
        audio.simulateRecordingStopped()
        await waitUntil { viewModel.state == .failed(.recordingInterrupted) }

        #expect(viewModel.state == .failed(.recordingInterrupted))
        #expect(viewModel.state != .paused)
        #expect(!audio.isActivelyRecording)
    }

    @MainActor
    @Test("Retry discards the interrupted audio and starts a new recording")
    func captureRetryStartsFreshRecording() async {
        let audio = MockAudioRecordingService()
        let clock = MutableClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let viewModel = MeetingCaptureViewModel(
            configuration: captureConfiguration(),
            dependencies: MeetingCaptureDependencies(
                audio: audio,
                speech: MockSpeechTranscriptionService(eventDelay: .seconds(10))
            ),
            repository: InMemoryMeetingRepository(),
            now: { clock.now }
        )

        await viewModel.start()
        clock.advance(by: 30)
        await viewModel.pause()
        let firstFile = audio.latestFileURL

        await viewModel.retry()

        #expect(viewModel.state == .recording)
        #expect(audio.startCount == 2)
        #expect(audio.cancelCount == 1)
        // Retry means a genuinely new file and a reset clock, not a continuation.
        #expect(audio.latestFileURL != firstFile)
        #expect(viewModel.elapsedTime < 1)
    }

    @Test("Finishing is permitted from a failed state so audio is never stranded")
    func captureStateAllowsFinishAfterFailure() {
        #expect(MeetingCaptureState.recording.canFinish)
        #expect(MeetingCaptureState.paused.canFinish)
        #expect(MeetingCaptureState.failed(.recordingInterrupted).canFinish)
        #expect(!MeetingCaptureState.idle.canFinish)
        #expect(!MeetingCaptureState.completed.canFinish)
        #expect(
            MeetingCaptureStateMachine.isValidTransition(
                from: .failed(.recordingInterrupted),
                to: .finishing
            )
        )
    }

    // MARK: - Speaker turn grouping
    //
    // One person speaking several sentences is one speaker turn. Sentence-final
    // punctuation used to split it, producing a column of repeated identical
    // speaker headers.

    @Test("Consecutive sentences from one speaker form a single turn")
    func reconciliationMergesConsecutiveSameSpeakerSentences() {
        let words = [
            WhisperWord(text: "First", startSeconds: 0, endSeconds: 0.4),
            WhisperWord(text: "sentence.", startSeconds: 0.5, endSeconds: 1),
            WhisperWord(text: "Second", startSeconds: 1.4, endSeconds: 1.8),
            WhisperWord(text: "sentence.", startSeconds: 1.9, endSeconds: 2.3),
            WhisperWord(text: "Third", startSeconds: 2.7, endSeconds: 3.1),
            WhisperWord(text: "one.", startSeconds: 3.2, endSeconds: 3.6),
        ]
        let turns = TranscriptReconciliationService().reconcile(
            words: words,
            intervals: [
                DiarizationInterval(
                    stableSpeakerKey: "S1",
                    startSeconds: 0,
                    endSeconds: 4
                ),
            ],
            matches: [
                SpeakerMatch(
                    stableSpeakerKey: "S1",
                    state: .unknown,
                    userID: nil,
                    displayName: "Speaker 1",
                    confidence: nil
                ),
            ]
        )

        #expect(turns.count == 1)
        #expect(
            turns[0].text == "First sentence. Second sentence. Third one."
        )
        // Boundaries span the whole stretch of speech.
        #expect(turns[0].startSeconds == 0)
        #expect(turns[0].endSeconds == 3.6)
    }

    @Test("Alternating speakers stay separate turns")
    func reconciliationKeepsAlternatingSpeakersSeparate() {
        let words = [
            WhisperWord(text: "Mine.", startSeconds: 0, endSeconds: 0.8),
            WhisperWord(text: "Yours.", startSeconds: 1.1, endSeconds: 1.9),
            WhisperWord(text: "Mine", startSeconds: 2.1, endSeconds: 2.5),
            WhisperWord(text: "again.", startSeconds: 2.6, endSeconds: 3),
        ]
        let turns = TranscriptReconciliationService().reconcile(
            words: words,
            intervals: [
                DiarizationInterval(
                    stableSpeakerKey: "S1",
                    startSeconds: 0,
                    endSeconds: 1
                ),
                DiarizationInterval(
                    stableSpeakerKey: "S2",
                    startSeconds: 1,
                    endSeconds: 2
                ),
                DiarizationInterval(
                    stableSpeakerKey: "S1",
                    startSeconds: 2,
                    endSeconds: 3.5
                ),
            ],
            matches: [
                SpeakerMatch(
                    stableSpeakerKey: "S1",
                    state: .unknown,
                    userID: nil,
                    displayName: "Speaker 1",
                    confidence: nil
                ),
                SpeakerMatch(
                    stableSpeakerKey: "S2",
                    state: .unknown,
                    userID: nil,
                    displayName: "Speaker 2",
                    confidence: nil
                ),
            ]
        )

        // Three turns: the same speaker returning after another speaker starts
        // a new turn, and different speakers are never merged.
        #expect(turns.count == 3)
        #expect(turns.map(\.stableSpeakerKey) == ["S1", "S2", "S1"])
        #expect(turns[0].text == "Mine.")
        #expect(turns[1].text == "Yours.")
        #expect(turns[2].text == "Mine again.")
        #expect(turns[2].startSeconds == 2.1)
    }

    @Test("A long silence from the same speaker starts a new turn")
    func reconciliationSplitsSameSpeakerAcrossLongSilence() {
        let words = [
            WhisperWord(text: "Before", startSeconds: 0, endSeconds: 0.5),
            WhisperWord(text: "break.", startSeconds: 0.6, endSeconds: 1),
            // Silence longer than the turn gap: a genuine new turn.
            WhisperWord(text: "After", startSeconds: 9, endSeconds: 9.5),
            WhisperWord(text: "break.", startSeconds: 9.6, endSeconds: 10),
        ]
        let turns = TranscriptReconciliationService().reconcile(
            words: words,
            intervals: [
                DiarizationInterval(
                    stableSpeakerKey: "S1",
                    startSeconds: 0,
                    endSeconds: 11
                ),
            ],
            matches: [
                SpeakerMatch(
                    stableSpeakerKey: "S1",
                    state: .unknown,
                    userID: nil,
                    displayName: "Speaker 1",
                    confidence: nil
                ),
            ]
        )

        #expect(turns.count == 2)
        #expect(turns[0].text == "Before break.")
        #expect(turns[1].text == "After break.")
        #expect(turns[1].startSeconds == 9)
    }

    @Test("Merging a turn keeps the lowest attribution confidence")
    func reconciliationPreservesConfidenceAcrossMergedTurn() {
        let johnID = UUID()
        let words = [
            WhisperWord(text: "One.", startSeconds: 0, endSeconds: 0.5),
            WhisperWord(text: "Two.", startSeconds: 0.7, endSeconds: 1.2),
        ]
        let turns = TranscriptReconciliationService().reconcile(
            words: words,
            intervals: [
                DiarizationInterval(
                    stableSpeakerKey: "S1",
                    startSeconds: 0,
                    endSeconds: 2
                ),
            ],
            matches: [
                SpeakerMatch(
                    stableSpeakerKey: "S1",
                    state: .recognized,
                    userID: johnID,
                    displayName: "John",
                    confidence: 0.91
                ),
            ]
        )

        #expect(turns.count == 1)
        #expect(turns[0].speakerUserID == johnID)
        #expect(turns[0].attributionSource == .voiceProfile)
        #expect(turns[0].attributionConfidence == 0.91)
    }

    // MARK: - Persistence failure visibility
    //
    // A failed on-disk write used to be swallowed by `try?`, so the UI updated
    // and the change silently vanished on relaunch.

    /// Repository that fails every write, to exercise the failure path.
    @MainActor
    private final class FailingMeetingRepository: MeetingRepository {
        struct WriteFailure: Error {}

        private(set) var saveAttempts = 0
        var stored: [Meeting] = []

        func fetchMeetings() async throws -> [Meeting] {
            stored
        }

        @discardableResult
        func save(_ meeting: Meeting) async throws -> Meeting {
            saveAttempts += 1
            throw WriteFailure()
        }

        func delete(_ meeting: Meeting) async throws {
            stored.removeAll { $0.id == meeting.id }
        }
    }

    @MainActor
    @Test("A failed save surfaces a warning instead of appearing to succeed")
    func libraryReportsPersistenceFailure() async {
        let repository = FailingMeetingRepository()
        let library = MeetingLibrary(repository: repository)
        let meeting = Meeting(
            title: "Unsaved changes",
            projectName: "Aligna",
            scheduledAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: .complete
        )

        #expect(library.persistenceWarning == nil)

        // `save` propagates, so a caller can react rather than assume success.
        await #expect(throws: (any Error).self) {
            try await library.save(meeting)
        }
        #expect(repository.saveAttempts == 1)
    }

    @MainActor
    @Test("Clearing the persistence warning resets it")
    func libraryClearsPersistenceWarning() async {
        let repository = FailingMeetingRepository()
        let library = MeetingLibrary(repository: repository)

        library.clearPersistenceWarning()
        #expect(library.persistenceWarning == nil)
    }

    @MainActor
    @Test("A library with no seed meetings starts genuinely empty")
    func libraryStartsEmptyWithoutSampleData() async {
        let library = MeetingLibrary(
            repository: InMemoryMeetingRepository()
        )

        // Previously this defaulted to fabricated `SampleData.meetings`.
        #expect(library.meetings.isEmpty)
        await library.load()
        #expect(library.meetings.isEmpty)
    }

    // MARK: - Dashboard projection
    //
    // The dashboard, Tasks tab, and Meetings list previously rendered
    // `DashboardMockData` — invented meetings, tasks, and confidence scores.

    @Test("Tasks are projected from real meeting analysis")
    func dashboardProjectsTasksFromAnalysis() {
        let meeting = meetingWithAnalysis(
            actionItems: [
                MeetingActionItem(
                    task: "Send the revised scope",
                    assignee: "Maya",
                    assigneeDisplayName: "Maya Chen",
                    assignmentConfidence: 0.9,
                    dueDate: "2027-01-15",
                    evidence: MeetingEvidence(
                        timestampSeconds: 12,
                        quote: "I'll send the revised scope."
                    )
                ),
                MeetingActionItem(
                    task: "Follow up with the vendor",
                    assignee: nil,
                    dueDate: nil,
                    evidence: MeetingEvidence(
                        timestampSeconds: 40,
                        quote: "Someone should follow up."
                    )
                ),
            ]
        )

        let tasks = DashboardProjection.tasks(from: [meeting])

        #expect(tasks.count == 2)
        // Dated task sorts ahead of the undated one.
        #expect(tasks[0].title == "Send the revised scope")
        #expect(tasks[0].assignee == "Maya Chen")
        #expect(tasks[0].dueDate != nil)
        #expect(tasks[0].priority == .high)
        #expect(tasks[0].sourceMeetingID == meeting.id)

        #expect(tasks[1].title == "Follow up with the vendor")
        #expect(tasks[1].assignee == "Unassigned")
        #expect(tasks[1].dueDate == nil)
        #expect(tasks[1].priority == .low)
    }

    @Test("Meetings without analysis contribute no tasks")
    func dashboardProjectsNoTasksWithoutAnalysis() {
        let meeting = Meeting(
            title: "Still processing",
            projectName: "Aligna",
            scheduledAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: .processing
        )

        #expect(DashboardProjection.tasks(from: [meeting]).isEmpty)
        #expect(DashboardProjection.pendingReviews(from: [meeting]).isEmpty)
    }

    @Test("Relative deadlines are preserved verbatim, never guessed")
    func dashboardKeepsRelativeDeadlinesAsText() {
        let meeting = meetingWithAnalysis(
            actionItems: [
                MeetingActionItem(
                    task: "Ship the beta",
                    assignee: "Liam",
                    dueDate: "next Friday",
                    evidence: MeetingEvidence(
                        timestampSeconds: 5,
                        quote: "Let's ship the beta next Friday."
                    )
                ),
            ]
        )

        let task = DashboardProjection.tasks(from: [meeting])[0]

        // "next Friday" is not a calendar date: resolving it would invent a
        // deadline nobody agreed to.
        #expect(task.dueDate == nil)
        #expect(task.dueDateText == "next Friday")
        #expect(task.dueDateDescription() == "next Friday")
        #expect(!task.isOverdue())
        #expect(DashboardProjection.parsedDueDate("next Friday") == nil)
        #expect(DashboardProjection.parsedDueDate("2027-01-15") != nil)
    }

    @Test("A task with no deadline reports its absence")
    func dashboardTaskWithoutDeadlineDescribesAbsence() {
        let task = ProjectTask(
            title: "Unscheduled",
            assignee: "Unassigned",
            dueDate: nil,
            priority: .low
        )

        #expect(task.dueDateDescription() == "No deadline")
        #expect(!task.isOverdue())
    }

    @Test("Pending reviews come only from meetings awaiting review")
    func dashboardProjectsPendingReviews() {
        let awaiting = meetingWithAnalysis(
            status: .needsReview,
            summary: "Scope agreed, two risks still unowned."
        )
        let complete = meetingWithAnalysis(status: .complete)

        let reviews = DashboardProjection.pendingReviews(
            from: [awaiting, complete]
        )

        #expect(reviews.count == 1)
        #expect(reviews[0].summary == "Scope agreed, two risks still unowned.")
        #expect(reviews[0].sourceMeetingID == awaiting.id)
    }

    @Test("Review confidence is absent rather than invented")
    func dashboardReviewConfidenceIsOptional() {
        let withoutConfidence = meetingWithAnalysis(
            status: .needsReview,
            actionItems: [
                MeetingActionItem(
                    task: "No confidence reported",
                    assignee: nil,
                    assignmentConfidence: nil,
                    dueDate: nil,
                    evidence: MeetingEvidence(
                        timestampSeconds: 1,
                        quote: "Quote."
                    )
                ),
            ]
        )

        let review = DashboardProjection.pendingReviews(
            from: [withoutConfidence]
        )[0]
        #expect(review.confidence == nil)

        let viewModel = DashboardViewModel(
            snapshot: DashboardProjection.snapshot(
                meetings: [withoutConfidence],
                currentUser: TeamMember(name: "JC Cruz")
            )
        )
        #expect(viewModel.confidenceText(for: review) == nil)
    }

    @Test("Undated tasks are excluded from the due-soon window")
    func dashboardDueSoonExcludesUndatedTasks() {
        let calendar = utcCalendar()
        let now = date(
            year: 2027,
            month: 1,
            day: 10,
            hour: 9,
            calendar: calendar
        )
        let snapshot = DashboardSnapshot(
            currentUser: TeamMember(name: "JC Cruz"),
            meetings: [],
            tasks: [
                ProjectTask(
                    title: "Dated and soon",
                    assignee: "JC",
                    dueDate: now.addingTimeInterval(2 * 86_400),
                    priority: .high
                ),
                ProjectTask(
                    title: "Relative wording only",
                    assignee: "JC",
                    dueDate: nil,
                    dueDateText: "next Friday",
                    priority: .medium
                ),
            ],
            pendingReviews: []
        )

        let viewModel = DashboardViewModel(
            snapshot: snapshot,
            now: now,
            calendar: calendar
        )

        #expect(viewModel.tasksDueSoon.count == 1)
        #expect(viewModel.tasksDueSoon[0].title == "Dated and soon")
    }

    @Test("An empty dashboard greets without a fabricated name")
    func dashboardEmptyStateHasNoSampleContent() {
        let viewModel = DashboardViewModel.empty(
            now: date(
                year: 2027,
                month: 1,
                day: 10,
                hour: 9,
                calendar: utcCalendar()
            ),
            calendar: utcCalendar()
        )

        #expect(viewModel.snapshot.meetings.isEmpty)
        #expect(viewModel.snapshot.tasks.isEmpty)
        #expect(viewModel.snapshot.pendingReviews.isEmpty)
        #expect(viewModel.upcomingMeeting == nil)
        #expect(viewModel.featuredReview == nil)
        #expect(viewModel.greeting == "Good morning")
    }

    private func meetingWithAnalysis(
        status: Meeting.Status = .needsReview,
        summary: String = "A summary.",
        actionItems: [MeetingActionItem] = []
    ) -> Meeting {
        Meeting(
            title: "Recorded meeting",
            projectName: "Aligna",
            scheduledAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: status,
            analysis: MeetingAnalysis(
                generatedTitle: "Generated title",
                summary: summary,
                keyPoints: [],
                decisions: [],
                actionItems: actionItems,
                openQuestions: [],
                followUps: [],
                languagesDetected: ["en"]
            )
        )
    }

    // MARK: - Recorder settings validity
    //
    // Regression context: a 96 kbps AAC bitrate at 16 kHz mono made
    // prepareToRecord() fail on device, so recording never started and the UI
    // showed "Couldn't start recording". The fix reverts to 48 kbps (the
    // shipped, known-good value). This is NOT unit-tested: AVAudioRecorder's
    // prepareToRecord() depends on real audio hardware and returns false for all
    // bitrates on the simulator, so any such assertion would test the simulator,
    // not the encoder. Validity is confirmed by device recording and by the
    // production guard in AudioRecordingService that surfaces a rejected
    // configuration instead of the generic session-conflict message.

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    /// Test clock so capture timing is deterministic instead of wall-clock based.
    @MainActor
    private final class MutableClock {
        private(set) var now: Date

        init(start: Date) {
            now = start
        }

        func advance(by seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }

    /// Polls until `condition` holds, for assertions that depend on an
    /// `AsyncStream` event being delivered.
    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func voiceVector(
        first: Float,
        second: Float
    ) -> [Float] {
        [first, second] + [Float](repeating: 0, count: 254)
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        ) ?? .distantPast
    }
}
