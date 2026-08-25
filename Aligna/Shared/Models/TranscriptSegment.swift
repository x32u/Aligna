import Foundation

nonisolated struct TranscriptSegment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    let originalText: String
    let editedText: String?
    let confidence: Double?
    let speakerUserID: UUID?
    let speakerLabel: String?
    let isFinal: Bool

    var text: String {
        editedText ?? originalText
    }

    var speaker: String? {
        speakerLabel
    }

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil,
        isFinal: Bool,
        speaker: String? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.originalText = text
        self.editedText = nil
        self.confidence = confidence
        self.speakerUserID = nil
        self.speakerLabel = speaker
        self.isFinal = isFinal
    }

    init(
        id: UUID = UUID(),
        originalText: String,
        editedText: String? = nil,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil,
        confidence: Double? = nil,
        speakerUserID: UUID? = nil,
        speakerLabel: String? = nil,
        isFinal: Bool
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.originalText = originalText
        self.editedText = editedText
        self.confidence = confidence
        self.speakerUserID = speakerUserID
        self.speakerLabel = speakerLabel
        self.isFinal = isFinal
    }

    func applyingCorrection(_ correction: String?) -> TranscriptSegment {
        TranscriptSegment(
            id: id,
            originalText: originalText,
            editedText: correction,
            startTime: startTime,
            endTime: endTime,
            confidence: confidence,
            speakerUserID: speakerUserID,
            speakerLabel: speakerLabel,
            isFinal: isFinal
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case originalText
        case editedText
        case startTime
        case endTime
        case confidence
        case speaker
        case speakerUserID
        case speakerLabel
        case isFinal
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startTime = try values.decodeIfPresent(
            TimeInterval.self,
            forKey: .startTime
        )
        endTime = try values.decodeIfPresent(
            TimeInterval.self,
            forKey: .endTime
        )
        originalText = try values.decodeIfPresent(
            String.self,
            forKey: .originalText
        ) ?? values.decode(String.self, forKey: .text)
        editedText = try values.decodeIfPresent(
            String.self,
            forKey: .editedText
        )
        confidence = try values.decodeIfPresent(
            Double.self,
            forKey: .confidence
        )
        speakerUserID = try values.decodeIfPresent(
            UUID.self,
            forKey: .speakerUserID
        )
        speakerLabel = try values.decodeIfPresent(
            String.self,
            forKey: .speakerLabel
        ) ?? values.decodeIfPresent(String.self, forKey: .speaker)
        isFinal = try values.decode(Bool.self, forKey: .isFinal)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(originalText, forKey: .originalText)
        try values.encodeIfPresent(editedText, forKey: .editedText)
        try values.encodeIfPresent(startTime, forKey: .startTime)
        try values.encodeIfPresent(endTime, forKey: .endTime)
        try values.encodeIfPresent(confidence, forKey: .confidence)
        try values.encodeIfPresent(speakerUserID, forKey: .speakerUserID)
        try values.encodeIfPresent(speakerLabel, forKey: .speakerLabel)
        try values.encode(isFinal, forKey: .isFinal)
    }
}
