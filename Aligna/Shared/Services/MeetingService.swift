import Foundation

protocol MeetingServing: Sendable {
    func fetchMeetings() async throws -> [Meeting]
}

struct MockMeetingService: MeetingServing {
    func fetchMeetings() async throws -> [Meeting] {
        SampleData.meetings
    }
}
