import Foundation
import Network
import Observation

@MainActor
@Observable
final class MeetingLibrary {
    private(set) var meetings: [Meeting]
    private(set) var loadError: MeetingCaptureError?
    private(set) var processingIssues: [UUID: MeetingProcessingIssue] = [:]

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
        seedMeetings: [Meeting]? = nil
    ) {
        self.repository = repository
        let initialMeetings = seedMeetings ?? SampleData.meetings
        self.seedMeetings = initialMeetings
        self.meetings = initialMeetings
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
                        let persisted =
                            (try? await self.repository.save(queued))
                            ?? queued
                        self.merge([persisted])
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
                    attributedTranscript: snapshot.attributedTranscript
                )
                let persisted = (try? await self.repository.save(updated))
                    ?? updated
                self.merge([persisted])
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

    private func persistProcessingFailure(for meeting: Meeting) {
        let failed = meeting.withProcessing(status: .failed)
        merge([failed])
        Task { [weak self] in
            guard let self else { return }
            let persisted = (try? await repository.save(failed)) ?? failed
            merge([persisted])
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
