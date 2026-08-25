import Foundation

protocol MeetingRepository: Sendable {
    func fetchMeetings() async throws -> [Meeting]
    @discardableResult
    func save(_ meeting: Meeting) async throws -> Meeting
    func delete(_ meeting: Meeting) async throws
}

protocol LegacyMeetingMigrating: Sendable {
    func legacyMeetingCount() async throws -> Int
    func claimLegacyMeetings() async throws -> Int
}

actor InMemoryMeetingRepository: MeetingRepository {
    private var meetings: [Meeting]

    init(meetings: [Meeting] = []) {
        self.meetings = meetings
    }

    func fetchMeetings() -> [Meeting] {
        meetings.sorted { $0.scheduledAt > $1.scheduledAt }
    }

    @discardableResult
    func save(_ meeting: Meeting) -> Meeting {
        meetings.removeAll { $0.id == meeting.id }
        meetings.append(meeting)
        return meeting
    }

    func delete(_ meeting: Meeting) {
        meetings.removeAll { $0.id == meeting.id }
    }
}
