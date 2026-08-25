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
            throw VoiceRecognitionError.invalidEmbedding
        }
        let userID = try await requireVerifiedUser()
        try await localStore.save(embedding, userID: userID)

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
        } catch {
            try? await localStore.delete(userID: userID)
            throw normalizedFunctionError(error)
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

        return response.candidates.compactMap { candidate in
            let model = VoiceModelDescriptor(
                provider: candidate.modelProvider,
                packageVersion: candidate.packageVersion,
                modelVersion: candidate.modelVersion,
                embeddingDimension: candidate.embeddingDimension
            )
            guard model.compatibilityKey
                    == VoiceModelDescriptor.fluidAudioOfflineV1
                        .compatibilityKey,
                  let normalized = VoiceVectorMath.normalized(
                      candidate.embedding
                  ),
                  normalized.count == model.embeddingDimension
            else {
                return nil
            }
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
