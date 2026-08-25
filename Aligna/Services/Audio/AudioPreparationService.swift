import AVFoundation
import Foundation

nonisolated protocol AudioPreparing: Sendable {
    func prepare(
        recordingURL: URL,
        meetingID: UUID
    ) async throws -> [PreparedAudioChunk]
}

actor AudioPreparationService: AudioPreparing {
    private let directUploadLimit = 22 * 1_024 * 1_024
    private let targetChunkBytes = 18 * 1_024 * 1_024
    private let preferredChunkDuration: TimeInterval = 20 * 60
    private let overlap: TimeInterval = 2

    func prepare(
        recordingURL: URL,
        meetingID: UUID
    ) async throws -> [PreparedAudioChunk] {
        let fileManager = FileManager.default
        let values = try recordingURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey]
        )
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0
        else {
            throw AudioPreparationError.invalidRecording
        }

        let asset = AVURLAsset(url: recordingURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw AudioPreparationError.invalidRecording
        }

        if fileSize <= directUploadLimit {
            return [
                PreparedAudioChunk(
                    fileURL: recordingURL,
                    startSeconds: 0,
                    endSeconds: duration
                ),
            ]
        }

        let bytesPerSecond = Double(fileSize) / duration
        let sizeLimitedDuration = floor(
            Double(targetChunkBytes) / max(bytesPerSecond, 1)
        )
        let chunkDuration = max(
            60,
            min(preferredChunkDuration, sizeLimitedDuration)
        )
        let directory = try MeetingFileLocations.recordingsDirectory(
            fileManager: fileManager
        )
        .appending(path: "UploadChunks", directoryHint: .isDirectory)
        .appending(
            path: meetingID.uuidString.lowercased(),
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var chunks: [PreparedAudioChunk] = []
        var start: TimeInterval = 0
        var index = 0

        while start < duration {
            let end = min(duration, start + chunkDuration)
            let outputURL = directory
                .appending(path: "chunk-\(index)")
                .appendingPathExtension("m4a")
            if fileManager.fileExists(atPath: outputURL.path()) {
                try fileManager.removeItem(at: outputURL)
            }

            guard let exporter = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetAppleM4A
            ) else {
                throw AudioPreparationError.exportFailed
            }
            exporter.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                end: CMTime(seconds: end, preferredTimescale: 600)
            )
            try await exporter.export(to: outputURL, as: .m4a)

            let exportedSize = try outputURL.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize ?? 0
            guard exportedSize > 0, exportedSize <= directUploadLimit else {
                throw AudioPreparationError.chunkTooLarge
            }

            chunks.append(
                PreparedAudioChunk(
                    fileURL: outputURL,
                    startSeconds: start,
                    endSeconds: end
                )
            )
            if end >= duration { break }
            start = max(0, end - overlap)
            index += 1
        }

        return chunks
    }
}

nonisolated enum AudioPreparationError: LocalizedError {
    case invalidRecording
    case exportFailed
    case chunkTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidRecording:
            "The saved recording could not be opened."
        case .exportFailed:
            "The recording could not be prepared."
        case .chunkTooLarge:
            "This recording needs smaller processing sections."
        }
    }
}
