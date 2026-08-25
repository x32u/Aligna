import Foundation

actor CloudBackedMeetingRepository:
    MeetingRepository,
    LegacyMeetingMigrating {
    private let local: LocalMeetingRepository
    private let cloud: any MeetingCloudRepository
    private let ownerUserID: UUID
    private let workspaceID: UUID

    init(
        local: LocalMeetingRepository,
        cloud: any MeetingCloudRepository,
        ownerUserID: UUID,
        workspaceID: UUID
    ) {
        self.local = local
        self.cloud = cloud
        self.ownerUserID = ownerUserID
        self.workspaceID = workspaceID
    }

    func fetchMeetings() async throws -> [Meeting] {
        try await local.fetchMeetings()
    }

    @discardableResult
    func save(_ meeting: Meeting) async throws -> Meeting {
        let participantIDs = meeting.participants.compactMap(\.userID)
        let syncing = meeting.withCloudMetadata(
            ownerUserID: ownerUserID,
            workspaceID: workspaceID,
            organizerUserID: ownerUserID,
            participantUserIDs: participantIDs,
            syncState: .syncing
        )
        try await local.save(syncing)

        let finalMeeting: Meeting
        do {
            try await cloud.synchronize(
                syncing,
                workspaceID: workspaceID,
                organizerID: ownerUserID,
                participantUserIDs: participantIDs
            )
            finalMeeting = syncing.withCloudMetadata(
                ownerUserID: ownerUserID,
                workspaceID: workspaceID,
                organizerUserID: ownerUserID,
                participantUserIDs: participantIDs,
                syncState: .synced
            )
        } catch {
            finalMeeting = syncing.withCloudMetadata(
                ownerUserID: ownerUserID,
                workspaceID: workspaceID,
                organizerUserID: ownerUserID,
                participantUserIDs: participantIDs,
                syncState: .failed
            )
        }

        try await local.save(finalMeeting)
        return finalMeeting
    }

    func delete(_ meeting: Meeting) async throws {
        if let meetingOwnerID = meeting.ownerUserID,
           meetingOwnerID != ownerUserID {
            throw LocalMeetingRepositoryError.ownerMismatch
        }

        try await cloud.delete(meetingID: meeting.id)
        try await local.delete(meeting)
    }

    func legacyMeetingCount() async throws -> Int {
        try await local.legacyMeetingCount()
    }

    func claimLegacyMeetings() async throws -> Int {
        try await local.claimLegacyMeetings()
    }
}
