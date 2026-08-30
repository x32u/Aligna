import Foundation

/// Whether speaker identification actually ran for a meeting.
///
/// A transcript can be complete while speaker attribution has failed, so this
/// state is tracked separately from `MeetingProcessingStatus`. It exists so a
/// failed diarization can never be presented as though a real speaker had been
/// identified.
nonisolated enum SpeakerAttributionState:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Sendable {
    /// Speaker work has not finished yet.
    case pending
    /// Diarization ran and every turn carries a real cluster identity.
    case attributed
    /// The recording had no separable speech, so there was nothing to attribute.
    case skipped
    /// Diarization was attempted and failed. Turn text is trustworthy; the
    /// speaker labels are not.
    case failed

    /// Only `attributed` means the speaker labels on a turn describe a speaker
    /// the app actually distinguished.
    var identifiesSpeakers: Bool { self == .attributed }

    /// Quiet, non-alarming explanation shown beside the transcript. `nil` while
    /// work is in flight or when attribution succeeded.
    var notice: String? {
        switch self {
        case .pending, .attributed:
            nil
        case .skipped:
            "Speakers weren’t identified for this recording."
        case .failed:
            "Speakers couldn’t be identified for this recording. The transcript itself is complete."
        }
    }

    /// Cluster key used when no diarization identity is available. Deliberately
    /// not `speaker-1`: a placeholder must never read as "speaker number 1 of
    /// several", which is what made a failed pipeline look like a successful
    /// single-speaker result.
    static let unattributedSpeakerKey = "unattributed"

    /// Display name paired with `unattributedSpeakerKey`.
    static let unattributedDisplayName = "Unidentified speaker"

    /// Maps the `meetings.speaker_processing_status` column onto this state.
    /// Unrecognized and in-flight values are treated as `pending` so a new
    /// server-side stage can never be mistaken for a finished attribution.
    static func fromProcessingStatus(
        _ value: String?,
        skipped: Bool
    ) -> SpeakerAttributionState {
        switch value {
        case "complete":
            skipped ? .skipped : .attributed
        case "skipped":
            .skipped
        case "failed":
            .failed
        default:
            .pending
        }
    }
}
