import Foundation

nonisolated enum TranscriptTimelineNormalizer {
    static func normalize(
        _ segments: [TranscriptSegment],
        recordingDuration: TimeInterval?,
        sourceOrigin: TimeInterval? = nil
    ) -> [TranscriptSegment] {
        guard !segments.isEmpty else { return [] }

        let duration = recordingDuration.flatMap {
            $0.isFinite ? max(0, $0) : nil
        }
        let finiteTimes: [TimeInterval] = segments.flatMap { segment in
            [segment.startTime, segment.endTime].compactMap {
                (value: TimeInterval?) -> TimeInterval? in
                guard let value, value.isFinite else { return nil }
                return value
            }
        }
        let inferredOrigin: TimeInterval
        if let sourceOrigin, sourceOrigin.isFinite {
            inferredOrigin = sourceOrigin
        } else if
            let duration,
            let earliest = finiteTimes.min(),
            let latest = finiteTimes.max(),
            earliest > duration + 1,
            latest > duration + 1
        {
            // Older builds persisted SpeechAnalyzer's absolute audio clock.
            inferredOrigin = earliest
        } else {
            inferredOrigin = 0
        }

        var previousStart: TimeInterval = 0
        return segments.map { segment in
            let rawStart = finite(segment.startTime) ?? previousStart
            let rawEnd = finite(segment.endTime) ?? rawStart
            let relativeStart = rawStart - inferredOrigin
            let relativeEnd = rawEnd - inferredOrigin
            let start = clamp(
                max(previousStart, relativeStart),
                upperBound: duration
            )
            let end = clamp(
                max(start, relativeEnd),
                upperBound: duration
            )
            previousStart = start

            return TranscriptSegment(
                id: segment.id,
                originalText: segment.originalText,
                editedText: segment.editedText,
                startTime: start,
                endTime: end,
                confidence: segment.confidence,
                speakerUserID: segment.speakerUserID,
                speakerLabel: segment.speakerLabel,
                isFinal: segment.isFinal
            )
        }
    }

    private static func finite(
        _ value: TimeInterval?
    ) -> TimeInterval? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func clamp(
        _ value: TimeInterval,
        upperBound: TimeInterval?
    ) -> TimeInterval {
        let nonnegative = max(0, value.isFinite ? value : 0)
        guard let upperBound else { return nonnegative }
        return min(nonnegative, upperBound)
    }
}

nonisolated extension TranscriptVersion {
    func normalizingTimeline(
        to recordingDuration: TimeInterval
    ) -> TranscriptVersion {
        TranscriptVersion(
            id: id,
            source: source,
            engineIdentifier: engineIdentifier,
            localeIdentifier: localeIdentifier,
            createdAt: createdAt,
            segments: TranscriptTimelineNormalizer.normalize(
                segments,
                recordingDuration: recordingDuration
            ),
            processingStatus: processingStatus,
            failureReason: failureReason
        )
    }
}

nonisolated extension TranscriptDocument {
    func normalizingTimeline(
        to recordingDuration: TimeInterval
    ) -> TranscriptDocument {
        TranscriptDocument(
            meetingID: meetingID,
            ownerUserID: ownerUserID,
            selectedLocaleIdentifier: selectedLocaleIdentifier,
            currentVersionID: currentVersionID,
            versions: versions.map {
                $0.normalizingTimeline(to: recordingDuration)
            },
            corrections: corrections,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

nonisolated extension TimeInterval {
    var transcriptTimestamp: String {
        let totalSeconds = max(0, Int(rounded(.down)))
        if totalSeconds < 3_600 {
            return String(
                format: "%d:%02d",
                totalSeconds / 60,
                totalSeconds % 60
            )
        }
        return String(
            format: "%d:%02d:%02d",
            totalSeconds / 3_600,
            (totalSeconds % 3_600) / 60,
            totalSeconds % 60
        )
    }
}
