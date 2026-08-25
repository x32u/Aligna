import Foundation

nonisolated struct TeamMember: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let userID: UUID?
    let handle: String?
    let responseStatus: ParticipantResponseStatus?

    init(
        id: UUID = UUID(),
        name: String,
        userID: UUID? = nil,
        handle: String? = nil,
        responseStatus: ParticipantResponseStatus? = nil
    ) {
        self.id = userID ?? id
        self.name = name
        self.userID = userID
        self.handle = handle
        self.responseStatus = responseStatus
    }

    var initials: String {
        name
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
            .joined()
    }
}
