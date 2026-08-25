import Foundation

nonisolated protocol VoiceModelPreparing: Sendable {
    func prepareModels() async throws
}

nonisolated protocol VoiceEmbeddingExtracting: Sendable {
    func embedding(from samples: [Float]) async throws -> VoiceEmbedding
}

nonisolated protocol SpeakerDiarizing: Sendable {
    func diarize(audioURL: URL) async throws -> DiarizationOutput
}

nonisolated protocol VoiceProcessing:
    VoiceModelPreparing,
    VoiceEmbeddingExtracting,
    SpeakerDiarizing {}

nonisolated protocol VoiceProfileServicing: Sendable {
    func enroll(
        embedding: VoiceEmbedding,
        consentedAt: Date
    ) async throws
    func candidates(meetingID: UUID) async throws
        -> [CandidateVoiceProfile]
    func updateStatus(_ status: VoiceEnrollmentStatus) async throws
    func deleteProfile() async throws
}

nonisolated protocol SpeakerMatching: Sendable {
    func match(
        clusters: [SpeakerCluster],
        candidates: [CandidateVoiceProfile]
    ) -> [SpeakerMatch]
}

nonisolated protocol TranscriptReconciling: Sendable {
    func reconcile(
        words: [WhisperWord],
        intervals: [DiarizationInterval],
        matches: [SpeakerMatch]
    ) -> [AttributedTranscriptTurn]
}
