import Foundation

nonisolated enum TranscriptionEngineKind: String, Hashable, Codable, Sendable {
    case speechTranscriber = "apple-speech-transcriber"
    case dictationTranscriber = "apple-dictation-transcriber"

    var displayName: String {
        switch self {
        case .speechTranscriber: "Apple SpeechTranscriber"
        case .dictationTranscriber: "Apple DictationTranscriber"
        }
    }
}

nonisolated enum TranscriptionAssetState: String, Hashable, Codable, Sendable {
    case installed
    case downloadable
    case downloading
    case unsupported
}

nonisolated struct TranscriptionCapabilities: Hashable, Sendable {
    let languages: [TranscriptionLanguage]
    let speechLocaleIdentifiers: Set<String>
    let dictationLocaleIdentifiers: Set<String>

    init(
        languages: [TranscriptionLanguage],
        speechLocaleIdentifiers: Set<String>,
        dictationLocaleIdentifiers: Set<String>
    ) {
        self.languages = languages
        self.speechLocaleIdentifiers = Set(
            speechLocaleIdentifiers.map {
                TranscriptionLanguage.normalizedIdentifier($0)
            }
        )
        self.dictationLocaleIdentifiers = Set(
            dictationLocaleIdentifiers.map {
                TranscriptionLanguage.normalizedIdentifier($0)
            }
        )
    }

    func engine(for localeIdentifier: String) -> TranscriptionEngineKind? {
        let normalized = TranscriptionLanguage.normalizedIdentifier(
            localeIdentifier
        )
        if speechLocaleIdentifiers.contains(where: {
            TranscriptionLanguage.identifiersAreEquivalent($0, normalized)
        }) {
            return .speechTranscriber
        }
        if dictationLocaleIdentifiers.contains(where: {
            TranscriptionLanguage.identifiersAreEquivalent($0, normalized)
        }) {
            return .dictationTranscriber
        }
        return nil
    }

    func language(for localeIdentifier: String) -> TranscriptionLanguage? {
        let normalized = TranscriptionLanguage.normalizedIdentifier(
            localeIdentifier
        )
        return languages.first {
            TranscriptionLanguage.identifiersAreEquivalent(
                $0.identifier,
                normalized
            )
        }
    }
}
