import Foundation
import Supabase

actor SupabaseVoiceProfileService: VoiceProfileServicing {
    private let client: SupabaseClient
    private let localStore: any LocalVoiceProfileStoring

    init(
        provider: SupabaseClientProvider,
        localStore: (any LocalVoiceProfileStoring)? = nil
    ) {
        client = provider.client
        self.localStore = localStore ?? LocalVoiceProfileStore()
    }

    func enroll(
        embedding: VoiceEmbedding,
        consentedAt: Date
    ) async throws {
        guard embedding.isFinite,
              let normalized = VoiceVectorMath.normalized(embedding.values),
              normalized.count == embedding.model.embeddingDimension
        else {
            VoiceEnrollmentDiagnostics.logRejection(
                reason: .embeddingInvalid,
                stage: "enroll_precondition"
            )
            throw VoiceRecognitionError.invalidEmbedding
        }
        let userID: UUID
        do {
            userID = try await requireVerifiedUser()
        } catch {
            VoiceEnrollmentDiagnostics.logCaughtError(
                stage: "enroll_require_verified_user",
                error: error
            )
            VoiceEnrollmentDiagnostics.logStorageResult(
                succeeded: false,
                reason: VoiceEnrollmentReason.from(error),
                category: "authentication",
                httpStatus: nil,
                associatedWithExpectedUser: "unknown"
            )
            throw error
        }

        VoiceEnrollmentDiagnostics.logStorageAttempt(
            embeddingDimension: normalized.count,
            modelVersion: embedding.model.modelVersion
        )

        do {
            try await localStore.save(embedding, userID: userID)
        } catch {
            VoiceEnrollmentDiagnostics.logCaughtError(
                stage: "enroll_local_store",
                error: error
            )
            VoiceEnrollmentDiagnostics.logStorageResult(
                succeeded: false,
                reason: .storageFailed,
                category: "local_store",
                httpStatus: nil,
                associatedWithExpectedUser:
                    VoiceEnrollmentDiagnostics.userAssociation(
                        expected: userID,
                        associated: userID
                    )
            )
            throw error
        }

        do {
            let _: VoiceProfileMutationResponse = try await client.functions
                .invoke(
                    "voice-profiles",
                    options: FunctionInvokeOptions(
                        body: VoiceProfileRequest(
                            action: "enroll",
                            meetingID: nil,
                            embedding: normalized,
                            embeddingDimension:
                                embedding.model.embeddingDimension,
                            modelProvider: embedding.model.provider,
                            modelVersion: embedding.model.modelVersion,
                            packageVersion: embedding.model.packageVersion,
                            consentedAt: consentedAt,
                            status: nil
                        )
                    )
                )
            VoiceEnrollmentDiagnostics.logStorageResult(
                succeeded: true,
                reason: nil,
                category: "edge_function",
                httpStatus: 200,
                associatedWithExpectedUser:
                    VoiceEnrollmentDiagnostics.userAssociation(
                        expected: userID,
                        associated: userID
                    )
            )
        } catch {
            VoiceEnrollmentDiagnostics.logCaughtError(
                stage: "enroll_edge_function",
                error: error
            )
            let normalizedError = normalizedFunctionError(error)
            VoiceEnrollmentDiagnostics.logStorageResult(
                succeeded: false,
                reason: VoiceEnrollmentReason.from(normalizedError),
                category: Self.transportCategory(for: error),
                httpStatus: Self.httpStatus(for: error),
                associatedWithExpectedUser:
                    VoiceEnrollmentDiagnostics.userAssociation(
                        expected: userID,
                        associated: nil
                    )
            )
            try? await localStore.delete(userID: userID)
            throw normalizedError
        }
    }

    /// Transport category for diagnostics, derived from the same `FunctionsError`
    /// cases `normalizedFunctionError` inspects.
    private static func transportCategory(for error: Error) -> String {
        guard let functionsError = error as? FunctionsError else {
            return "unknown"
        }
        return switch functionsError {
        case .relayError: "relay_error"
        case .httpError: "http_error"
        }
    }

    private static func httpStatus(for error: Error) -> Int? {
        guard let functionsError = error as? FunctionsError else {
            return nil
        }
        return switch functionsError {
        case .relayError: nil
        case let .httpError(code, _): code
        }
    }

    func candidates(meetingID: UUID) async throws
        -> [CandidateVoiceProfile] {
        let response: VoiceCandidatesResponse = try await client.functions
            .invoke(
                "voice-profiles",
                options: FunctionInvokeOptions(
                    body: VoiceProfileRequest(
                        action: "candidates",
                        meetingID: meetingID,
                        embedding: nil,
                        embeddingDimension:
                            VoiceModelDescriptor.fluidAudioOfflineV1
                                .embeddingDimension,
                        modelProvider:
                            VoiceModelDescriptor.fluidAudioOfflineV1
                                .provider,
                        modelVersion:
                            VoiceModelDescriptor.fluidAudioOfflineV1
                                .modelVersion,
                        packageVersion:
                            VoiceModelDescriptor.fluidAudioOfflineV1
                                .packageVersion,
                        consentedAt: nil,
                        status: nil
                    )
                )
            )

        let expected = VoiceModelDescriptor.fluidAudioOfflineV1
        var afterCompatibilityKey = 0
        var afterNormalization = 0
        var afterDimension = 0

        let candidates = response.candidates.compactMap {
            candidate -> CandidateVoiceProfile? in
            let model = VoiceModelDescriptor(
                provider: candidate.modelProvider,
                packageVersion: candidate.packageVersion,
                modelVersion: candidate.modelVersion,
                embeddingDimension: candidate.embeddingDimension
            )
            guard model.compatibilityKey == expected.compatibilityKey else {
                SpeakerAttributionDiagnostics.logCandidateRejected(
                    provider: candidate.modelProvider,
                    modelVersion: candidate.modelVersion,
                    dimension: candidate.embeddingDimension,
                    reason: "compatibility_key_mismatch"
                )
                return nil
            }
            afterCompatibilityKey += 1

            guard let normalized = VoiceVectorMath.normalized(
                candidate.embedding
            ) else {
                SpeakerAttributionDiagnostics.logCandidateRejected(
                    provider: candidate.modelProvider,
                    modelVersion: candidate.modelVersion,
                    dimension: candidate.embeddingDimension,
                    reason: "normalization_failed"
                )
                return nil
            }
            afterNormalization += 1

            guard normalized.count == model.embeddingDimension else {
                SpeakerAttributionDiagnostics.logCandidateRejected(
                    provider: candidate.modelProvider,
                    modelVersion: candidate.modelVersion,
                    dimension: normalized.count,
                    reason: "dimension_mismatch"
                )
                return nil
            }
            afterDimension += 1

            return CandidateVoiceProfile(
                userID: candidate.userID,
                displayName: candidate.displayName,
                avatarPath: candidate.avatarPath,
                embedding: VoiceEmbedding(
                    values: normalized,
                    model: model
                )
            )
        }

        SpeakerAttributionDiagnostics.logCandidateRetrievalStages(
            serverReturned: response.candidates.count,
            afterCompatibilityKeyFilter: afterCompatibilityKey,
            afterNormalizationFilter: afterNormalization,
            afterDimensionFilter: afterDimension,
            finalCandidates: candidates.count,
            expectedProvider: expected.provider,
            expectedModelVersion: expected.modelVersion,
            expectedDimension: expected.embeddingDimension
        )

        return candidates
    }

    func updateStatus(_ status: VoiceEnrollmentStatus) async throws {
        let _: VoiceProfileMutationResponse = try await client.functions
            .invoke(
                "voice-profiles",
                options: FunctionInvokeOptions(
                    body: VoiceProfileRequest(
                        action: "status",
                        meetingID: nil,
                        embedding: nil,
                        embeddingDimension: nil,
                        modelProvider: nil,
                        modelVersion: nil,
                        packageVersion: nil,
                        consentedAt: nil,
                        status: status
                    )
                )
            )
    }

    func deleteProfile() async throws {
        let userID = try await currentUserID()
        let _: VoiceProfileMutationResponse = try await client.functions
            .invoke(
                "voice-profiles",
                options: FunctionInvokeOptions(
                    body: VoiceProfileRequest(
                        action: "delete",
                        meetingID: nil,
                        embedding: nil,
                        embeddingDimension: nil,
                        modelProvider: nil,
                        modelVersion: nil,
                        packageVersion: nil,
                        consentedAt: nil,
                        status: nil
                    )
                )
            )
        try await localStore.delete(userID: userID)
    }

    private func requireVerifiedUser() async throws -> UUID {
        do {
            let session = try await client.auth.session
            guard VoiceProfileEnrollmentPolicy.canEnroll(
                sessionIsExpired: session.isExpired,
                emailConfirmedAt: session.user.emailConfirmedAt
            ) else {
                throw VoiceRecognitionError.unauthorized
            }
            return session.user.id
        } catch let error as VoiceRecognitionError {
            throw error
        } catch {
            throw VoiceRecognitionError.unauthorized
        }
    }

    private func currentUserID() async throws -> UUID {
        do {
            let session = try await client.auth.session
            guard !session.isExpired else {
                throw VoiceRecognitionError.unauthorized
            }
            return session.user.id
        } catch let error as VoiceRecognitionError {
            throw error
        } catch {
            throw VoiceRecognitionError.unauthorized
        }
    }

    private func normalizedFunctionError(_ error: Error) -> Error {
        guard let functionsError = error as? FunctionsError else {
            return error
        }
        switch functionsError {
        case .relayError:
            return VoiceRecognitionError.offline
        case let .httpError(code, _):
            switch code {
            case 401, 403:
                return VoiceRecognitionError.unauthorized
            case 503:
                return VoiceRecognitionError.configurationMissing
            default:
                return error
            }
        }
    }
}

nonisolated enum VoiceProfileEnrollmentPolicy {
    static func canEnroll(
        sessionIsExpired: Bool,
        emailConfirmedAt: Date?
    ) -> Bool {
        !sessionIsExpired && emailConfirmedAt != nil
    }
}

nonisolated private struct VoiceProfileRequest: Encodable, Sendable {
    let action: String
    let meetingID: UUID?
    let embedding: [Float]?
    let embeddingDimension: Int?
    let modelProvider: String?
    let modelVersion: String?
    let packageVersion: String?
    let consentedAt: Date?
    let status: VoiceEnrollmentStatus?

    enum CodingKeys: String, CodingKey {
        case action
        case meetingID = "meeting_id"
        case embedding
        case embeddingDimension = "embedding_dimension"
        case modelProvider = "model_provider"
        case modelVersion = "model_version"
        case packageVersion = "package_version"
        case consentedAt = "consented_at"
        case status
    }
}

nonisolated private struct VoiceProfileMutationResponse:
    Decodable,
    Sendable {
    let success: Bool
}

nonisolated private struct VoiceCandidatesResponse:
    Decodable,
    Sendable {
    let candidates: [VoiceCandidateDTO]
}

nonisolated private struct VoiceCandidateDTO: Decodable, Sendable {
    let userID: UUID
    let displayName: String
    let avatarPath: String?
    let embedding: [Float]
    let embeddingDimension: Int
    let modelProvider: String
    let modelVersion: String
    let packageVersion: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case embedding
        case embeddingDimension = "embedding_dimension"
        case modelProvider = "model_provider"
        case modelVersion = "model_version"
        case packageVersion = "package_version"
    }
}
