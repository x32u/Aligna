import Foundation
import Network
import Observation
import OSLog

/// Diagnostics for local meeting persistence.
///
/// Records only the pipeline stage and a coarse error identity — never meeting
/// titles, transcripts, or identifiers.
nonisolated enum MeetingLibraryDiagnostics {
    private static let logger = Logger(
        subsystem: "dev.notjc.Aligna",
        category: "MeetingPersistence"
    )

    static func logPersistenceFailure(stage: String, error: Error) {
        logger.error(
            """
            Meeting persistence failed. \
            stage=\(stage, privacy: .public) \
            type=\(String(reflecting: type(of: error)), privacy: .public)
            """
        )
    }
}

@MainActor
@Observable
final class MeetingLibrary {
    private(set) var meetings: [Meeting]
    private(set) var loadError: MeetingCaptureError?
    private(set) var processingIssues: [UUID: MeetingProcessingIssue] = [:]
    /// Set when a processing update could not be written to disk. The in-memory
    /// list still reflects the update, but it will not survive a relaunch — so
    /// the UI must be able to say so rather than appear to have saved.
    private(set) var persistenceWarning: String?

    let repository: any MeetingRepository
    private let seedMeetings: [Meeting]
    private var hasLoaded = false
    private var processingTasks: [UUID: Task<Void, Never>] = [:]
    private var processingService: (any MeetingProcessingServicing)?
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(
        label: "dev.notjc.Aligna.meeting-processing-network"
    )
    private var isMonitoringNetwork = false

    init(
        repository: any MeetingRepository,
        seedMeetings: [Meeting] = []
    ) {
        self.repository = repository
        self.seedMeetings = seedMeetings
        meetings = seedMeetings
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        do {
            let savedMeetings = try await repository.fetchMeetings()
            merge(savedMeetings)
        } catch {
            loadError = .persistenceFailed
        }
    }

    func includeSavedMeeting(_ meeting: Meeting) {
        merge([meeting])
    }

    func resumePendingProcessing(
        using service: any MeetingProcessingServicing
    ) {
        processingService = service
        startNetworkMonitoringIfNeeded()

        for meeting in meetings where meeting.processingStatus.isProcessing {
            beginProcessing(
                meeting,
                using: service,
                uploadIfNeeded: meeting.processingStatus == .queued
            )
        }
    }

    func retryProcessing(
        _ meeting: Meeting,
        using service: any MeetingProcessingServicing
    ) {
        beginProcessing(meeting, using: service, uploadIfNeeded: true)
    }

    func processingIssue(for meetingID: UUID) -> MeetingProcessingIssue? {
        processingIssues[meetingID]
    }

    @discardableResult
    func save(_ meeting: Meeting) async throws -> Meeting {
        let persisted = try await repository.save(meeting)
        merge([persisted])
        return persisted
    }

    func delete(_ meeting: Meeting) async throws {
        let processingTask = processingTasks.removeValue(forKey: meeting.id)
        processingTask?.cancel()
        await processingTask?.value

        do {
            try await repository.delete(meeting)
        } catch {
            if meeting.processingStatus.isProcessing,
               let processingService {
                beginProcessing(
                    meeting,
                    using: processingService,
                    uploadIfNeeded: meeting.processingStatus == .queued
                )
            }
            throw error
        }

        meetings.removeAll { $0.id == meeting.id }
        processingIssues[meeting.id] = nil
    }

    func legacyMeetingCount() async -> Int {
        guard let migrator = repository as? any LegacyMeetingMigrating
        else {
            return 0
        }
        return (try? await migrator.legacyMeetingCount()) ?? 0
    }

    func claimLegacyMeetings() async throws -> Int {
        guard let migrator = repository as? any LegacyMeetingMigrating
        else {
            return 0
        }
        let count = try await migrator.claimLegacyMeetings()
        let savedMeetings = try await repository.fetchMeetings()
        merge(savedMeetings)
        return count
    }

    private func merge(_ newMeetings: [Meeting]) {
        let allMeetings = meetings + newMeetings
        meetings = Dictionary(grouping: allMeetings, by: \.id)
            .compactMap { $0.value.last }
            .sorted { $0.scheduledAt > $1.scheduledAt }
    }

    private func beginProcessing(
        _ meeting: Meeting,
        using service: any MeetingProcessingServicing,
        uploadIfNeeded: Bool
    ) {
        guard processingTasks[meeting.id] == nil else { return }
        guard let audioFileName = meeting.audioFileName,
              let audioURL = MeetingFileLocations.recordingURL(
                  fileName: audioFileName
              )
        else {
            processingIssues[meeting.id] = .recordingUnavailable
            persistProcessingFailure(for: meeting)
            return
        }

        processingIssues[meeting.id] = nil
        processingTasks[meeting.id] = Task { [weak self] in
            guard let self else { return }
            if uploadIfNeeded {
                do {
                    try await service.enqueue(
                        meeting: meeting,
                        audioURL: audioURL
                    )
                } catch {
                    guard !Task.isCancelled else {
                        self.processingTasks[meeting.id] = nil
                        return
                    }
                    let failure = MeetingProcessingServiceError.normalized(
                        error
                    )
                    self.processingIssues[meeting.id] = failure.issue
                    if failure.shouldRemainQueued {
                        let queued = meeting.withProcessing(status: .queued)
                        self.merge([
                            await self.persist(
                                queued,
                                stage: "requeue_after_upload_failure"
                            ),
                        ])
                    } else {
                        self.persistProcessingFailure(for: meeting)
                    }
                    self.processingTasks[meeting.id] = nil
                    return
                }
            } else {
                await service.resume(
                    meeting: meeting,
                    audioURL: audioURL
                )
            }

            self.processingIssues[meeting.id] = nil
            let stream = await service.updates(meetingID: meeting.id)
            for await snapshot in stream {
                let updated = meeting.withProcessing(
                    status: snapshot.status,
                    title: snapshot.title,
                    analysis: snapshot.analysis,
                    transcript: snapshot.transcript,
                    attributedTranscript: snapshot.attributedTranscript,
                    speakerAttribution: snapshot.speakerAttribution
                )
                self.merge([
                    await self.persist(
                        updated,
                        stage: "processing_snapshot"
                    ),
                ])
                if !snapshot.status.isProcessing {
                    if snapshot.status == .complete {
                        self.processingIssues[meeting.id] = nil
                    }
                    break
                }
            }
            self.processingTasks[meeting.id] = nil
        }
    }

    /// Writes a meeting to the repository, surfacing a failure instead of
    /// discarding it.
    ///
    /// The previous `try?` made a failed write indistinguishable from a
    /// successful one: the UI updated either way and the meeting silently
    /// reverted on relaunch. The in-memory value is still returned so processing
    /// continues, but `persistenceWarning` records that it is unsaved.
    private func persist(
        _ meeting: Meeting,
        stage: String
    ) async -> Meeting {
        do {
            let saved = try await repository.save(meeting)
            return saved
        } catch {
            MeetingLibraryDiagnostics.logPersistenceFailure(
                stage: stage,
                error: error
            )
            persistenceWarning =
                "Aligna couldn’t save the latest changes to this iPhone. Your recording is safe, but reopening the app may show older details."
            return meeting
        }
    }

    func clearPersistenceWarning() {
        persistenceWarning = nil
    }

    private func persistProcessingFailure(for meeting: Meeting) {
        let failed = meeting.withProcessing(status: .failed)
        merge([failed])
        Task { [weak self] in
            guard let self else { return }
            merge([
                await persist(failed, stage: "processing_failure"),
            ])
        }
    }

    private func startNetworkMonitoringIfNeeded() {
        guard !isMonitoringNetwork else { return }
        isMonitoringNetwork = true
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self, let processingService else { return }
                for meeting in meetings
                where meeting.processingStatus == .queued {
                    beginProcessing(
                        meeting,
                        using: processingService,
                        uploadIfNeeded: true
                    )
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
}
