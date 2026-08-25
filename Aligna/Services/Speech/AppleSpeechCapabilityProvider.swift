import Foundation
import Speech

protocol TranscriptionCapabilityProviding: Sendable {
    func capabilities(forceRefresh: Bool) async -> TranscriptionCapabilities
}

actor AppleSpeechCapabilityProvider: TranscriptionCapabilityProviding {
    private var cached: TranscriptionCapabilities?

    func capabilities(
        forceRefresh: Bool = false
    ) async -> TranscriptionCapabilities {
        if !forceRefresh, let cached {
            return cached
        }

        let speechSupported = await SpeechTranscriber.supportedLocales
        let speechInstalled = await SpeechTranscriber.installedLocales
        let dictationSupported = await DictationTranscriber.supportedLocales
        let dictationInstalled = await DictationTranscriber.installedLocales

        let speechIDs = normalizedIdentifiers(speechSupported)
        let dictationIDs = normalizedIdentifiers(dictationSupported)
        let speechInstalledIDs = normalizedIdentifiers(speechInstalled)
        let dictationInstalledIDs = normalizedIdentifiers(
            dictationInstalled
        )
        let supported = Dictionary(
            (speechSupported + dictationSupported).map {
                (
                    TranscriptionLanguage.normalizedIdentifier(
                        $0.identifier
                    ),
                    $0
                )
            },
            uniquingKeysWith: { first, _ in first }
        )

        let deviceIdentifier = TranscriptionLanguage.normalizedIdentifier(
            Locale.current.identifier
        )
        let languages = supported
            .map { identifier, locale in
                TranscriptionLanguage(
                    identifier: identifier,
                    displayName: Locale.current.localizedString(
                        forIdentifier: locale.identifier
                    ),
                    isDeviceLanguage:
                        TranscriptionLanguage.identifiersAreEquivalent(
                            identifier,
                            deviceIdentifier
                        ),
                    assetState: (
                        containsEquivalent(identifier, in: speechIDs)
                            ? containsEquivalent(
                                identifier,
                                in: speechInstalledIDs
                            )
                            : containsEquivalent(
                                identifier,
                                in: dictationInstalledIDs
                            )
                    )
                        ? .installed
                        : .downloadable
                )
            }
            .sorted(by: Self.languageOrder)

        let value = TranscriptionCapabilities(
            languages: languages,
            speechLocaleIdentifiers: speechIDs,
            dictationLocaleIdentifiers: dictationIDs
        )
        cached = value
        return value
    }

    private func normalizedIdentifiers(
        _ locales: [Locale]
    ) -> Set<String> {
        Set(locales.map {
            TranscriptionLanguage.normalizedIdentifier($0.identifier)
        })
    }

    private func containsEquivalent(
        _ identifier: String,
        in identifiers: Set<String>
    ) -> Bool {
        identifiers.contains {
            TranscriptionLanguage.identifiersAreEquivalent(
                $0,
                identifier
            )
        }
    }

    nonisolated private static func languageOrder(
        _ lhs: TranscriptionLanguage,
        _ rhs: TranscriptionLanguage
    ) -> Bool {
        func priority(_ value: TranscriptionLanguage) -> Int {
            if value.isDeviceLanguage { return 0 }
            if value.isFilipino { return 1 }
            if value.languageCode == "en" { return 2 }
            return 3
        }
        let lhsPriority = priority(lhs)
        let rhsPriority = priority(rhs)
        return lhsPriority == rhsPriority
            ? lhs.displayName.localizedCaseInsensitiveCompare(
                rhs.displayName
            ) == .orderedAscending
            : lhsPriority < rhsPriority
    }
}

actor MockTranscriptionCapabilityProvider:
    TranscriptionCapabilityProviding {
    private var value: TranscriptionCapabilities

    init(
        capabilities: TranscriptionCapabilities =
            .mock
    ) {
        value = capabilities
    }

    func capabilities(
        forceRefresh: Bool = false
    ) -> TranscriptionCapabilities {
        value
    }
}

extension TranscriptionCapabilities {
    nonisolated static let mock = TranscriptionCapabilities(
        languages: [
            TranscriptionLanguage(
                identifier: "en-US",
                isDeviceLanguage: true,
                assetState: .installed
            ),
            TranscriptionLanguage(
                identifier: "fil-PH",
                assetState: .downloadable
            )
        ],
        speechLocaleIdentifiers: ["en-US", "fil-PH"],
        dictationLocaleIdentifiers: ["en-US", "fil-PH"]
    )
}
