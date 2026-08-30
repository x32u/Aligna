import Foundation

nonisolated struct TranscriptReconciliationService:
    TranscriptReconciling,
    Sendable {
    let maximumTurnGap: TimeInterval

    init(maximumTurnGap: TimeInterval = 2.5) {
        self.maximumTurnGap = maximumTurnGap
    }

    func reconcile(
        words: [WhisperWord],
        intervals: [DiarizationInterval],
        matches: [SpeakerMatch]
    ) -> [AttributedTranscriptTurn] {
        let matchesByKey = Dictionary(
            uniqueKeysWithValues: matches.map {
                ($0.stableSpeakerKey, $0)
            }
        )
        // Records whether each match reaching the transcript carries a real
        // identity or falls back to an anonymous label.
        for match in matches {
            SpeakerAttributionDiagnostics.logTranscriptIdentityResolution(
                speakerKey: match.stableSpeakerKey,
                state: match.state.rawValue,
                labelSource: match.state == .recognized
                    ? "identity"
                    : "fallback",
                hasUserID: match.userID != nil
            )
        }
        let attributed = words
            .sorted { $0.startSeconds < $1.startSeconds }
            .map { word in
                attribute(
                    word,
                    intervals: intervals,
                    matchesByKey: matchesByKey
                )
            }
        return group(attributed)
    }

    private func attribute(
        _ word: WhisperWord,
        intervals: [DiarizationInterval],
        matchesByKey: [String: SpeakerMatch]
    ) -> AttributedWord {
        let overlaps = intervals.compactMap { interval -> (
            interval: DiarizationInterval,
            overlap: TimeInterval
        )? in
            let overlap = max(
                0,
                min(word.endSeconds, interval.endSeconds)
                    - max(word.startSeconds, interval.startSeconds)
            )
            return overlap > 0 ? (interval, overlap) : nil
        }
        .sorted { $0.overlap > $1.overlap }

        let selectedKey: String?
        if let first = overlaps.first {
            if overlaps.count > 1,
               abs(first.overlap - overlaps[1].overlap) < 0.015,
               first.interval.stableSpeakerKey
                    != overlaps[1].interval.stableSpeakerKey {
                selectedKey = nil
            } else {
                selectedKey = first.interval.stableSpeakerKey
            }
        } else {
            let midpoint = (word.startSeconds + word.endSeconds) / 2
            selectedKey = intervals.first {
                midpoint >= $0.startSeconds && midpoint <= $0.endSeconds
            }?.stableSpeakerKey
        }

        guard let selectedKey,
              let match = matchesByKey[selectedKey]
        else {
            return AttributedWord(
                word: word,
                stableSpeakerKey: "unknown",
                userID: nil,
                displayName: "Unknown speaker",
                confidence: nil,
                source: .ambiguous
            )
        }

        return AttributedWord(
            word: word,
            stableSpeakerKey: selectedKey,
            userID: match.userID,
            displayName: match.displayName,
            confidence: match.confidence,
            source: match.state == .recognized
                ? .voiceProfile
                : (match.state == .ambiguous ? .ambiguous : .anonymous)
        )
    }

    /// Groups attributed words into speaker turns.
    ///
    /// A turn continues while the speaker is unchanged and the silence before
    /// the next word stays within `maximumTurnGap`. Sentence-final punctuation
    /// deliberately does NOT end a turn: one person saying three sentences is
    /// one speaker turn, not three, and treating `.`/`!`/`?` as a boundary is
    /// what produced repeated identical speaker headers.
    private func group(
        _ words: [AttributedWord]
    ) -> [AttributedTranscriptTurn] {
        var turns: [AttributedTranscriptTurn] = []

        for item in words {
            if let previous = turns.last,
               previous.stableSpeakerKey == item.stableSpeakerKey,
               item.word.startSeconds - previous.endSeconds <= maximumTurnGap {
                turns[turns.count - 1] = AttributedTranscriptTurn(
                    id: previous.id,
                    stableSpeakerKey: previous.stableSpeakerKey,
                    speakerUserID: previous.speakerUserID,
                    speakerDisplayName: previous.speakerDisplayName,
                    startSeconds: previous.startSeconds,
                    endSeconds: max(
                        previous.endSeconds,
                        item.word.endSeconds
                    ),
                    text: joined(previous.text, item.word.text),
                    attributionConfidence: minimumConfidence(
                        previous.attributionConfidence,
                        item.confidence
                    ),
                    attributionSource: previous.attributionSource
                )
            } else {
                turns.append(
                    AttributedTranscriptTurn(
                        stableSpeakerKey: item.stableSpeakerKey,
                        speakerUserID: item.userID,
                        speakerDisplayName: item.displayName,
                        startSeconds: item.word.startSeconds,
                        endSeconds: item.word.endSeconds,
                        text: item.word.text,
                        attributionConfidence: item.confidence,
                        attributionSource: item.source
                    )
                )
            }
        }

        return turns.filter {
            !$0.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        }
    }

    private func joined(_ existing: String, _ word: String) -> String {
        let punctuation = CharacterSet(
            charactersIn: ".,!?;:%)]}’”"
        )
        if let first = word.unicodeScalars.first,
           punctuation.contains(first) {
            return existing + word
        }
        return existing + " " + word
    }

    private func minimumConfidence(
        _ lhs: Float?,
        _ rhs: Float?
    ) -> Float? {
        switch (lhs, rhs) {
        case let (left?, right?):
            min(left, right)
        case let (left?, nil):
            left
        case let (nil, right?):
            right
        case (nil, nil):
            nil
        }
    }
}

nonisolated private struct AttributedWord: Sendable {
    let word: WhisperWord
    let stableSpeakerKey: String
    let userID: UUID?
    let displayName: String
    let confidence: Float?
    let source: SpeakerAttributionSource
}
