import Foundation

actor MockVoiceEngine: VoiceProcessing {
    var prepared = false
    var embeddings: [VoiceEmbedding]
    var diarization: DiarizationOutput
    var failure: Error?

    init(
        embeddings: [VoiceEmbedding] = [],
        diarization: DiarizationOutput = DiarizationOutput(
            intervals: [],
            clusters: []
        ),
        failure: Error? = nil
    ) {
        self.embeddings = embeddings
        self.diarization = diarization
        self.failure = failure
    }

    func prepareModels() throws {
        if let failure { throw failure }
        prepared = true
    }

    func embedding(from _: [Float]) throws -> VoiceEmbedding {
        if let failure { throw failure }
        guard !embeddings.isEmpty else {
            throw VoiceRecognitionError.noSpeech
        }
        return embeddings.removeFirst()
    }

    func diarize(audioURL _: URL) throws -> DiarizationOutput {
        if let failure { throw failure }
        return diarization
    }
}

actor MockVoiceProfileService: VoiceProfileServicing {
    private(set) var status: VoiceEnrollmentStatus
    private(set) var enrolledEmbedding: VoiceEmbedding?
    private(set) var deletionCount = 0
    var storedCandidates: [CandidateVoiceProfile]
    var failure: Error?

    init(
        status: VoiceEnrollmentStatus = .notStarted,
        candidates: [CandidateVoiceProfile] = [],
        failure: Error? = nil
    ) {
        self.status = status
        storedCandidates = candidates
        self.failure = failure
    }

    func enroll(
        embedding: VoiceEmbedding,
        consentedAt _: Date
    ) throws {
        if let failure { throw failure }
        enrolledEmbedding = embedding
        status = .enrolled
    }

    func candidates(meetingID _: UUID) throws
        -> [CandidateVoiceProfile] {
        if let failure { throw failure }
        return storedCandidates
    }

    func updateStatus(_ status: VoiceEnrollmentStatus) throws {
        if let failure { throw failure }
        self.status = status
    }

    func deleteProfile() throws {
        if let failure { throw failure }
        enrolledEmbedding = nil
        status = .notStarted
        deletionCount += 1
    }
}
