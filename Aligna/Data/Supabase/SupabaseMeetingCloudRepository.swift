import Foundation
import Supabase

actor SupabaseMeetingCloudRepository: MeetingCloudRepository {
    private let client: SupabaseClient

    init(provider: SupabaseClientProvider) {
        client = provider.client
    }

    func synchronize(
        _ meeting: Meeting,
        workspaceID: UUID,
        organizerID: UUID,
        participantUserIDs: [UUID]
    ) async throws {
        let startedAt = meeting.scheduledAt
        let endedAt = meeting.durationSeconds.map {
            startedAt.addingTimeInterval($0)
        }
        let cloudMeeting = MeetingCloudDTO(
            id: meeting.id,
            workspaceID: workspaceID,
            organizerID: organizerID,
            title: meeting.title,
            scheduledAt: nil,
            startedAt: startedAt,
            endedAt: endedAt,
            status: "completed",
            processingStatus: meeting.processingStatus.rawValue
        )

        try await client
            .from("meetings")
            .upsert(cloudMeeting)
            .execute()

        let participants = Set(participantUserIDs)
            .subtracting([organizerID])
            .map {
                MeetingParticipantCloudDTO(
                    meetingID: meeting.id,
                    userID: $0,
                    role: "participant",
                    responseStatus: "invited",
                    invitedBy: organizerID
                )
            }
        guard !participants.isEmpty else { return }

        try await client
            .from("meeting_participants")
            .upsert(participants)
            .execute()
    }

    func delete(meetingID: UUID) async throws {
        let rows: [MeetingDeletionCloudDTO] = try await client
            .from("meetings")
            .select("audio_chunks")
            .eq("id", value: meetingID.uuidString.lowercased())
            .limit(1)
            .execute()
            .value

        let paths = safeTemporaryAudioPaths(
            rows.first?.audioChunks.map(\.path) ?? [],
            meetingID: meetingID
        )
        if !paths.isEmpty {
            let bucket = client.storage.from("meeting-processing-audio")
            for start in stride(from: 0, to: paths.count, by: 100) {
                let end = min(start + 100, paths.count)
                try await bucket.remove(paths: Array(paths[start..<end]))
            }
        }

        try await client
            .from("meetings")
            .delete(returning: .minimal)
            .eq("id", value: meetingID.uuidString.lowercased())
            .execute()
    }

    private func safeTemporaryAudioPaths(
        _ paths: [String],
        meetingID: UUID
    ) -> [String] {
        let expectedMeetingFolder = meetingID.uuidString.lowercased()
        return Array(Set(paths.compactMap { path in
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count == 3,
                  UUID(uuidString: String(components[0])) != nil,
                  components[1].lowercased() == expectedMeetingFolder,
                  !components[2].isEmpty,
                  components[2].lowercased().hasSuffix(".m4a"),
                  !components.contains(where: { $0 == "." || $0 == ".." })
            else {
                return nil
            }
            return path
        })).sorted()
    }
}
