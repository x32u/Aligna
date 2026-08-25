import Foundation

nonisolated struct TranscriptionGlossaryContext: Hashable, Sendable {
    let meetingTitle: String
    let workspaceName: String?
    let projectNames: [String]
    let participantNames: [String]
    let participantHandles: [String]
    let userTerms: [String]

    init(
        meetingTitle: String,
        workspaceName: String? = nil,
        projectNames: [String] = [],
        participantNames: [String] = [],
        participantHandles: [String] = [],
        userTerms: [String] = []
    ) {
        self.meetingTitle = meetingTitle
        self.workspaceName = workspaceName
        self.projectNames = projectNames
        self.participantNames = participantNames
        self.participantHandles = participantHandles
        self.userTerms = userTerms
    }
}

protocol TranscriptionGlossaryBuilding: Sendable {
    func build(from context: TranscriptionGlossaryContext) -> [String]
}

nonisolated struct DefaultTranscriptionGlossaryBuilder:
    TranscriptionGlossaryBuilding {
    private let maximumTerms: Int
    private let maximumCharactersPerTerm: Int

    init(
        maximumTerms: Int = 100,
        maximumCharactersPerTerm: Int = 64
    ) {
        self.maximumTerms = maximumTerms
        self.maximumCharactersPerTerm = maximumCharactersPerTerm
    }

    func build(from context: TranscriptionGlossaryContext) -> [String] {
        let candidates =
            [context.meetingTitle]
            + [context.workspaceName].compactMap { $0 }
            + context.projectNames
            + context.participantNames
            + context.participantHandles
            + context.userTerms
            + [
                "Aligna",
                "Supabase",
                "SwiftUI",
                "SpeechAnalyzer"
            ]

        var seen = Set<String>()
        var result: [String] = []
        for candidate in candidates {
            let value = candidate
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  value.count <= maximumCharactersPerTerm
            else {
                continue
            }
            let key = value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard seen.insert(key).inserted else { continue }
            result.append(value)
            if result.count == maximumTerms {
                break
            }
        }
        return result
    }
}
