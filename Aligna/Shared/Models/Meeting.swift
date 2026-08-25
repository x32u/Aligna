import Foundation

nonisolated struct Meeting: Identifiable, Hashable, Codable, Sendable {
    enum Status: String, Hashable, Codable, Sendable {
        case scheduled
        case processing
        case needsReview
        case complete

        var title: String {
            switch self {
            case .scheduled: "Scheduled"
            case .processing: "Processing"
            case .needsReview: "Needs review"
            case .complete: "Complete"
            }
        }
    }

    let id: UUID
    let title: String
    let projectName: String
    let scheduledAt: Date
    let durationMinutes: Int?
    let durationSeconds: TimeInterval?
    let attendeeCount: Int
    let participants: [TeamMember]
    let status: Status
    let transcript: [TranscriptSegment]
    let attributedTranscript: [AttributedTranscriptTurn]
    let transcriptDocument: TranscriptDocument?
    let audioFileName: String?
    let transcriptionLocaleIdentifier: String?
    let ownerUserID: UUID?
    let workspaceID: UUID?
    let organizerUserID: UUID?
    let participantUserIDs: [UUID]
    let syncState: MeetingSyncState
    let processingStatus: MeetingProcessingStatus
    let analysis: MeetingAnalysis?

    init(
        id: UUID = UUID(),
        title: String,
        projectName: String,
        scheduledAt: Date,
        durationMinutes: Int? = nil,
        durationSeconds: TimeInterval? = nil,
        attendeeCount: Int? = nil,
        participants: [TeamMember] = [],
        status: Status,
        transcript: [TranscriptSegment] = [],
        attributedTranscript: [AttributedTranscriptTurn] = [],
        transcriptDocument: TranscriptDocument? = nil,
        audioFileName: String? = nil,
        transcriptionLocaleIdentifier: String? = nil,
        ownerUserID: UUID? = nil,
        workspaceID: UUID? = nil,
        organizerUserID: UUID? = nil,
        participantUserIDs: [UUID] = [],
        syncState: MeetingSyncState = .local,
        processingStatus: MeetingProcessingStatus = .complete,
        analysis: MeetingAnalysis? = nil
    ) {
        self.id = id
        self.title = title
        self.projectName = projectName
        self.scheduledAt = scheduledAt
        self.durationSeconds = durationSeconds
        self.durationMinutes = durationMinutes
            ?? durationSeconds.map { max(1, Int(ceil($0 / 60))) }
        self.attendeeCount = attendeeCount ?? participants.count
        self.participants = participants
        self.status = status
        let sourceDocument = transcriptDocument
            ?? TranscriptDocument.migratingLegacy(
                meetingID: id,
                ownerUserID: ownerUserID,
                localeIdentifier: transcriptionLocaleIdentifier,
                segments: transcript,
                createdAt: scheduledAt
            )
        self.transcriptDocument = durationSeconds.flatMap {
            $0.isFinite ? sourceDocument?.normalizingTimeline(to: $0) : nil
        } ?? sourceDocument
        self.transcript = self.transcriptDocument?.effectiveSegments
            ?? transcript
        self.attributedTranscript = attributedTranscript
        self.audioFileName = audioFileName
        self.transcriptionLocaleIdentifier = transcriptionLocaleIdentifier
        self.ownerUserID = ownerUserID
        self.workspaceID = workspaceID
        self.organizerUserID = organizerUserID
        self.participantUserIDs = participantUserIDs
        self.syncState = syncState
        self.processingStatus = processingStatus
        self.analysis = analysis
    }

    func withCloudMetadata(
        ownerUserID: UUID?,
        workspaceID: UUID?,
        organizerUserID: UUID?,
        participantUserIDs: [UUID],
        syncState: MeetingSyncState
    ) -> Meeting {
        Meeting(
            id: id,
            title: title,
            projectName: projectName,
            scheduledAt: scheduledAt,
            durationMinutes: durationMinutes,
            durationSeconds: durationSeconds,
            attendeeCount: attendeeCount,
            participants: participants,
            status: status,
            transcript: transcript,
            attributedTranscript: attributedTranscript,
            transcriptDocument: transcriptDocument,
            audioFileName: audioFileName,
            transcriptionLocaleIdentifier: transcriptionLocaleIdentifier,
            ownerUserID: ownerUserID,
            workspaceID: workspaceID,
            organizerUserID: organizerUserID,
            participantUserIDs: participantUserIDs,
            syncState: syncState,
            processingStatus: processingStatus,
            analysis: analysis
        )
    }

    func withTranscriptDocument(_ document: TranscriptDocument) -> Meeting {
        Meeting(
            id: id,
            title: title,
            projectName: projectName,
            scheduledAt: scheduledAt,
            durationMinutes: durationMinutes,
            durationSeconds: durationSeconds,
            attendeeCount: attendeeCount,
            participants: participants,
            status: status,
            transcript: document.effectiveSegments,
            attributedTranscript: attributedTranscript,
            transcriptDocument: document,
            audioFileName: audioFileName,
            transcriptionLocaleIdentifier: transcriptionLocaleIdentifier,
            ownerUserID: ownerUserID,
            workspaceID: workspaceID,
            organizerUserID: organizerUserID,
            participantUserIDs: participantUserIDs,
            syncState: syncState,
            processingStatus: processingStatus,
            analysis: analysis
        )
    }

    func withProcessing(
        status: MeetingProcessingStatus,
        title updatedTitle: String? = nil,
        analysis updatedAnalysis: MeetingAnalysis? = nil,
        transcript updatedTranscript: [TranscriptSegment]? = nil,
        attributedTranscript updatedAttributedTranscript:
            [AttributedTranscriptTurn]? = nil
    ) -> Meeting {
        Meeting(
            id: id,
            title: updatedTitle ?? title,
            projectName: projectName,
            scheduledAt: scheduledAt,
            durationMinutes: durationMinutes,
            durationSeconds: durationSeconds,
            attendeeCount: attendeeCount,
            participants: participants,
            status: status == .complete ? .needsReview : .processing,
            transcript: updatedTranscript ?? transcript,
            attributedTranscript:
                updatedAttributedTranscript ?? attributedTranscript,
            transcriptDocument: updatedTranscript == nil
                ? transcriptDocument
                : nil,
            audioFileName: audioFileName,
            transcriptionLocaleIdentifier: transcriptionLocaleIdentifier,
            ownerUserID: ownerUserID,
            workspaceID: workspaceID,
            organizerUserID: organizerUserID,
            participantUserIDs: participantUserIDs,
            syncState: syncState,
            processingStatus: status,
            analysis: updatedAnalysis ?? analysis
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case projectName
        case scheduledAt
        case durationMinutes
        case durationSeconds
        case attendeeCount
        case participants
        case status
        case transcript
        case attributedTranscript
        case transcriptDocument
        case audioFileName
        case transcriptionLocaleIdentifier
        case ownerUserID
        case workspaceID
        case organizerUserID
        case participantUserIDs
        case syncState
        case processingStatus
        case analysis
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        projectName = try values.decode(String.self, forKey: .projectName)
        scheduledAt = try values.decode(Date.self, forKey: .scheduledAt)
        durationMinutes = try values.decodeIfPresent(
            Int.self,
            forKey: .durationMinutes
        )
        durationSeconds = try values.decodeIfPresent(
            TimeInterval.self,
            forKey: .durationSeconds
        )
        attendeeCount = try values.decode(
            Int.self,
            forKey: .attendeeCount
        )
        participants = try values.decode(
            [TeamMember].self,
            forKey: .participants
        )
        status = try values.decode(Status.self, forKey: .status)
        let decodedTranscript = try values.decodeIfPresent(
            [TranscriptSegment].self,
            forKey: .transcript
        ) ?? []
        attributedTranscript = try values.decodeIfPresent(
            [AttributedTranscriptTurn].self,
            forKey: .attributedTranscript
        ) ?? []
        audioFileName = try values.decodeIfPresent(
            String.self,
            forKey: .audioFileName
        )
        transcriptionLocaleIdentifier = try values.decodeIfPresent(
            String.self,
            forKey: .transcriptionLocaleIdentifier
        )
        ownerUserID = try values.decodeIfPresent(
            UUID.self,
            forKey: .ownerUserID
        )
        workspaceID = try values.decodeIfPresent(
            UUID.self,
            forKey: .workspaceID
        )
        organizerUserID = try values.decodeIfPresent(
            UUID.self,
            forKey: .organizerUserID
        )
        participantUserIDs = try values.decodeIfPresent(
            [UUID].self,
            forKey: .participantUserIDs
        ) ?? participants.compactMap(\.userID)
        syncState = try values.decodeIfPresent(
            MeetingSyncState.self,
            forKey: .syncState
        ) ?? .local
        processingStatus = try values.decodeIfPresent(
            MeetingProcessingStatus.self,
            forKey: .processingStatus
        ) ?? (status == .processing ? .queued : .complete)
        analysis = try values.decodeIfPresent(
            MeetingAnalysis.self,
            forKey: .analysis
        )
        let decodedDocument = try values.decodeIfPresent(
            TranscriptDocument.self,
            forKey: .transcriptDocument
        ) ?? TranscriptDocument.migratingLegacy(
            meetingID: id,
            ownerUserID: ownerUserID,
            localeIdentifier: transcriptionLocaleIdentifier,
            segments: decodedTranscript,
            createdAt: scheduledAt
        )
        transcriptDocument = durationSeconds.flatMap {
            $0.isFinite ? decodedDocument?.normalizingTimeline(to: $0) : nil
        } ?? decodedDocument
        transcript = transcriptDocument?.effectiveSegments
            ?? decodedTranscript
    }
}
