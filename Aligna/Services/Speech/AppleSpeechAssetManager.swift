import Foundation
import Speech

actor AppleSpeechAssetManager: TranscriptionAssetManaging {
    private var downloadTask: Task<Void, Error>?

    func prepareAssets(
        for request: TranscriptionRequest,
        pass: TranscriptionPass,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        let locale = Locale(identifier: request.localeIdentifier)
        let modules = try await Self.modules(
            engine: request.engine,
            locale: locale,
            pass: pass
        )
        let status = await AssetInventory.status(forModules: modules)

        guard status != .unsupported else {
            throw TranscriptionServiceError.unsupportedLocale(
                request.localeIdentifier
            )
        }
        if status == .installed {
            progress(1)
        } else {
            guard let installation = try await AssetInventory
                .assetInstallationRequest(supporting: modules)
            else {
                throw TranscriptionServiceError.modelUnavailable
            }
            progress(installation.progress.fractionCompleted)
            let reporter = Task {
                while !Task.isCancelled {
                    progress(installation.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
            defer { reporter.cancel() }

            let task = Task {
                try Task.checkCancellation()
                try await installation.downloadAndInstall()
            }
            downloadTask = task
            do {
                try await task.value
            } catch is CancellationError {
                throw TranscriptionServiceError.cancelled
            } catch {
                throw Self.mapAssetError(error)
            }
            downloadTask = nil
            progress(1)
        }

        do {
            let reserved = try await AssetInventory.reserve(locale: locale)
            if !reserved {
                let installed = await AssetInventory.status(
                    forModules: modules
                ) == .installed
                guard installed else {
                    throw TranscriptionServiceError.languageAllocationLimit
                }
            }
        } catch let error as TranscriptionServiceError {
            throw error
        } catch {
            throw Self.mapAssetError(error)
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    nonisolated static func modules(
        engine: TranscriptionEngineKind,
        locale: Locale,
        pass: TranscriptionPass
    ) async throws -> [any SpeechModule] {
        switch engine {
        case .speechTranscriber:
            guard let locale = await SpeechTranscriber.supportedLocale(
                equivalentTo: locale
            ) else {
                throw TranscriptionServiceError.unsupportedLocale(
                    locale.identifier
                )
            }
            let preset: SpeechTranscriber.Preset =
                pass == .live
                ? .timeIndexedProgressiveTranscription
                : .timeIndexedTranscriptionWithAlternatives
            return [SpeechTranscriber(locale: locale, preset: preset)]

        case .dictationTranscriber:
            guard let locale = await DictationTranscriber.supportedLocale(
                equivalentTo: locale
            ) else {
                throw TranscriptionServiceError.unsupportedLocale(
                    locale.identifier
                )
            }
            let preset: DictationTranscriber.Preset =
                pass == .live
                ? .progressiveLongDictation
                : .timeIndexedLongDictation
            return [DictationTranscriber(locale: locale, preset: preset)]
        }
    }

    nonisolated private static func mapAssetError(
        _ error: Error
    ) -> TranscriptionServiceError {
        let description = String(describing: error).lowercased()
        if description.contains("cancel") {
            return .cancelled
        }
        if description.contains("storage")
            || description.contains("resource")
        {
            return .insufficientStorage
        }
        if description.contains("allocated")
            || description.contains("too many")
        {
            return .languageAllocationLimit
        }
        return .modelDownloadFailed
    }
}
