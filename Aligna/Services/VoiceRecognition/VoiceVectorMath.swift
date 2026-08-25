import Foundation

nonisolated enum VoiceVectorMath {
    static func normalized(_ values: [Float]) -> [Float]? {
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else {
            return nil
        }
        let magnitudeSquared = values.reduce(Float.zero) {
            $0 + ($1 * $1)
        }
        guard magnitudeSquared.isFinite, magnitudeSquared > 0 else {
            return nil
        }
        let inverseMagnitude = 1 / sqrt(magnitudeSquared)
        return values.map { $0 * inverseMagnitude }
    }

    static func cosineSimilarity(
        _ lhs: [Float],
        _ rhs: [Float]
    ) -> Float? {
        guard lhs.count == rhs.count,
              let left = normalized(lhs),
              let right = normalized(rhs)
        else {
            return nil
        }
        return zip(left, right).reduce(Float.zero) {
            $0 + ($1.0 * $1.1)
        }
    }

    static func aggregateEnrollment(
        _ embeddings: [[Float]],
        minimumSamples: Int = 3,
        maximumOutlierDistance: Float = 0.24
    ) -> [Float]? {
        let valid = embeddings.compactMap(normalized)
        guard valid.count >= minimumSamples,
              let dimension = valid.first?.count,
              valid.allSatisfy({ $0.count == dimension })
        else {
            return nil
        }

        let centroid = normalized(mean(valid)) ?? []
        let retained = valid.filter {
            guard let similarity = cosineSimilarity($0, centroid) else {
                return false
            }
            return 1 - similarity <= maximumOutlierDistance
        }
        guard retained.count >= minimumSamples else { return nil }
        return normalized(mean(retained))
    }

    private static func mean(_ vectors: [[Float]]) -> [Float] {
        guard let dimension = vectors.first?.count else { return [] }
        var result = [Float](repeating: 0, count: dimension)
        for vector in vectors {
            for index in vector.indices {
                result[index] += vector[index]
            }
        }
        let count = Float(vectors.count)
        return result.map { $0 / count }
    }
}

nonisolated struct EnrollmentAudioQualityAnalyzer: Sendable {
    let sampleRate: Double
    let minimumVoicedSeconds: TimeInterval
    let minimumRMS: Float
    let clippingAmplitude: Float
    let maximumClippedFraction: Float

    init(
        sampleRate: Double = 16_000,
        minimumVoicedSeconds: TimeInterval = 0.75,
        minimumRMS: Float = 0.004,
        clippingAmplitude: Float = 0.985,
        maximumClippedFraction: Float = 0.005
    ) {
        self.sampleRate = sampleRate
        self.minimumVoicedSeconds = minimumVoicedSeconds
        self.minimumRMS = minimumRMS
        self.clippingAmplitude = clippingAmplitude
        self.maximumClippedFraction = maximumClippedFraction
    }

    func analyze(_ samples: [Float]) -> EnrollmentSampleQuality {
        guard !samples.isEmpty else {
            return EnrollmentSampleQuality(
                durationSeconds: 0,
                voicedSeconds: 0,
                rootMeanSquare: 0,
                peakAmplitude: 0,
                issue: .insufficientSpeech
            )
        }

        let duration = Double(samples.count) / sampleRate
        let squareMean = samples.reduce(Double.zero) {
            $0 + Double($1 * $1)
        } / Double(samples.count)
        let rms = Float(sqrt(squareMean))
        let peak = samples.reduce(Float.zero) {
            max($0, abs($1))
        }
        let clippedCount = samples.reduce(into: 0) {
            if abs($1) >= clippingAmplitude { $0 += 1 }
        }
        let clippedFraction = Float(clippedCount) / Float(samples.count)

        let frameCount = max(1, Int(sampleRate * 0.02))
        let voicedFrames = stride(
            from: 0,
            to: samples.count,
            by: frameCount
        ).reduce(into: 0) { count, start in
            let end = min(samples.count, start + frameCount)
            let frame = samples[start..<end]
            let energy = sqrt(
                frame.reduce(Double.zero) {
                    $0 + Double($1 * $1)
                } / Double(frame.count)
            )
            if energy >= Double(minimumRMS * 0.65) {
                count += 1
            }
        }
        let voicedSeconds = Double(voicedFrames * frameCount) / sampleRate

        let issue: EnrollmentSampleIssue?
        if clippedFraction > maximumClippedFraction {
            issue = .clipped
        } else if rms < minimumRMS {
            issue = .tooQuiet
        } else if voicedSeconds < minimumVoicedSeconds {
            issue = .insufficientSpeech
        } else {
            issue = nil
        }

        return EnrollmentSampleQuality(
            durationSeconds: duration,
            voicedSeconds: voicedSeconds,
            rootMeanSquare: rms,
            peakAmplitude: peak,
            issue: issue
        )
    }
}
