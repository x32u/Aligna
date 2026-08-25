import Foundation

nonisolated struct SpeakerMatcher: SpeakerMatching, Sendable {
    struct Thresholds: Hashable, Sendable {
        let minimumSimilarity: Float
        let minimumSeparation: Float

        // Cross-session recordings vary more than clusters within one file.
        // Keep a meaningful rejection floor while allowing real-device
        // enrollment samples to match later meeting audio.
        static let conservative = Thresholds(
            minimumSimilarity: 0.72,
            minimumSeparation: 0.08
        )
    }

    let thresholds: Thresholds

    init(thresholds: Thresholds = .conservative) {
        self.thresholds = thresholds
    }

    func match(
        clusters: [SpeakerCluster],
        candidates: [CandidateVoiceProfile]
    ) -> [SpeakerMatch] {
        guard !clusters.isEmpty else { return [] }
        guard !candidates.isEmpty else {
            return clusters.enumerated().map { index, cluster in
                unknown(cluster, index: index)
            }
        }

        let scores = clusters.map { cluster in
            candidates.map { candidate in
                guard cluster.embedding.model.compatibilityKey
                        == candidate.embedding.model.compatibilityKey
                else {
                    return -Float.infinity
                }
                return VoiceVectorMath.cosineSimilarity(
                    cluster.embedding.values,
                    candidate.embedding.values
                ) ?? -Float.infinity
            }
        }
        let assignment = bestOneToOneAssignment(scores: scores)

        return clusters.enumerated().map { clusterIndex, cluster in
            guard let candidateIndex = assignment[clusterIndex],
                  candidateIndex < candidates.count
            else {
                return unknown(
                    cluster,
                    index: clusterIndex,
                    confidence: bestFiniteScore(
                        scores[clusterIndex]
                    )
                )
            }

            let score = scores[clusterIndex][candidateIndex]
            guard score >= thresholds.minimumSimilarity else {
                return unknown(
                    cluster,
                    index: clusterIndex,
                    confidence: score
                )
            }

            let alternative = scores[clusterIndex]
                .enumerated()
                .filter { $0.offset != candidateIndex }
                .map(\.element)
                .max() ?? -Float.infinity
            guard score - alternative >= thresholds.minimumSeparation else {
                return SpeakerMatch(
                    stableSpeakerKey: cluster.stableSpeakerKey,
                    state: .ambiguous,
                    userID: nil,
                    displayName: "Speaker \(clusterIndex + 1)",
                    confidence: score
                )
            }

            let candidate = candidates[candidateIndex]
            return SpeakerMatch(
                stableSpeakerKey: cluster.stableSpeakerKey,
                state: .recognized,
                userID: candidate.userID,
                displayName: candidate.displayName,
                confidence: score
            )
        }
    }

    private func unknown(
        _ cluster: SpeakerCluster,
        index: Int,
        confidence: Float? = nil
    ) -> SpeakerMatch {
        SpeakerMatch(
            stableSpeakerKey: cluster.stableSpeakerKey,
            state: .unknown,
            userID: nil,
            displayName: "Speaker \(index + 1)",
            confidence: confidence
        )
    }

    private func bestFiniteScore(_ scores: [Float]) -> Float? {
        scores.filter(\.isFinite).max()
    }

    private func bestOneToOneAssignment(
        scores: [[Float]]
    ) -> [Int: Int] {
        let candidateCount = min(scores.first?.count ?? 0, 16)
        var bestScore = -Float.infinity
        var best: [Int: Int] = [:]

        func search(
            clusterIndex: Int,
            usedMask: UInt64,
            total: Float,
            current: [Int: Int]
        ) {
            if clusterIndex == scores.count {
                if total > bestScore {
                    bestScore = total
                    best = current
                }
                return
            }

            search(
                clusterIndex: clusterIndex + 1,
                usedMask: usedMask,
                total: total,
                current: current
            )

            for candidateIndex in 0..<candidateCount {
                let bit = UInt64(1) << UInt64(candidateIndex)
                guard usedMask & bit == 0 else { continue }
                let score = scores[clusterIndex][candidateIndex]
                guard score.isFinite, score >= thresholds.minimumSimilarity
                else {
                    continue
                }
                var next = current
                next[clusterIndex] = candidateIndex
                search(
                    clusterIndex: clusterIndex + 1,
                    usedMask: usedMask | bit,
                    total: total + score,
                    current: next
                )
            }
        }

        search(clusterIndex: 0, usedMask: 0, total: 0, current: [:])
        return best
    }
}
