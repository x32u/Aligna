import Foundation

nonisolated struct TranscriptionLanguage: Identifiable, Hashable, Codable, Sendable {
    let identifier: String
    let displayName: String
    let isDeviceLanguage: Bool
    let assetState: TranscriptionAssetState

    var id: String { identifier }

    var languageCode: String? {
        Self.canonicalLanguageCode(for: identifier)
    }

    var isFilipino: Bool {
        Self.isFilipino(identifier)
    }

    init(
        identifier: String,
        displayName: String? = nil,
        isDeviceLanguage: Bool = false,
        assetState: TranscriptionAssetState = .downloadable
    ) {
        let normalized = Self.normalizedIdentifier(identifier)
        self.identifier = normalized
        self.displayName = displayName
            ?? Locale.current.localizedString(forIdentifier: normalized)
            ?? normalized
        self.isDeviceLanguage = isDeviceLanguage
        self.assetState = assetState
    }

    static func normalizedIdentifier(_ identifier: String) -> String {
        Locale(identifier: identifier).identifier(.bcp47)
    }

    static func isFilipino(_ identifier: String) -> Bool {
        let rawCode = identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first?
            .lowercased()
        return rawCode == "fil"
            || rawCode == "tl"
            || canonicalLanguageCode(for: identifier) == "fil"
    }

    static func identifiersAreEquivalent(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        let lhsLocale = Locale(identifier: lhs)
        let rhsLocale = Locale(identifier: rhs)
        guard canonicalLanguageCode(for: lhs)
            == canonicalLanguageCode(for: rhs)
        else {
            return false
        }
        let lhsRegion = lhsLocale.region?.identifier
        let rhsRegion = rhsLocale.region?.identifier
        return lhsRegion == nil || rhsRegion == nil || lhsRegion == rhsRegion
    }

    private static func canonicalLanguageCode(
        for identifier: String
    ) -> String? {
        let rawCode = identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first?
            .lowercased()
        if rawCode == "fil" || rawCode == "tl" {
            return "fil"
        }
        return Locale(identifier: identifier)
            .language.languageCode?.identifier
    }
}
