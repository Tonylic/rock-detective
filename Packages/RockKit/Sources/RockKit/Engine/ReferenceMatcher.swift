import Foundation

/// One labelled reference picture, stored as its feature-print embedding.
public struct ReferenceSample: Codable, Sendable, Hashable {
    public let rockID: String
    public let vector: [Float]

    public init(rockID: String, vector: [Float]) {
        self.rockID = rockID
        self.vector = vector
    }
}

/// Distance-weighted k-nearest-neighbour matching against a gallery of
/// reference pictures. Feature-print distances are only meaningful relative to
/// each other, so votes are weighted by 1 / (distance + ε) and turned into
/// smoothed per-rock likelihoods.
public struct ReferenceMatcher: Sendable {
    public let samples: [ReferenceSample]
    public var k: Int
    /// Share of probability spread evenly over all rocks, so rocks missing from
    /// the neighbourhood are never ruled out.
    public var smoothing: Double

    public init(samples: [ReferenceSample], k: Int = 5, smoothing: Double = 0.1) {
        self.samples = samples
        self.k = max(1, k)
        self.smoothing = smoothing
    }

    public var isEmpty: Bool { samples.isEmpty }

    public struct Neighbor: Sendable, Hashable {
        public let rockID: String
        public let distance: Double
    }

    public func nearestNeighbors(to query: [Float]) -> [Neighbor] {
        samples
            .filter { $0.vector.count == query.count }
            .map { Neighbor(rockID: $0.rockID, distance: Self.distance($0.vector, query)) }
            .sorted { $0.distance < $1.distance }
            .prefix(k)
            .map { $0 }
    }

    /// Per-rock likelihoods for `rockIDs`, or `nil` when there is nothing to compare with.
    public func evidence(for query: [Float], rockIDs: [String]) -> ReferenceEvidence? {
        let neighbors = nearestNeighbors(to: query)
        guard !neighbors.isEmpty, !rockIDs.isEmpty else { return nil }

        var votes: [String: Double] = [:]
        for neighbor in neighbors {
            votes[neighbor.rockID, default: 0] += 1 / (neighbor.distance + 1e-3)
        }
        let total = votes.values.reduce(0, +)
        let uniform = smoothing / Double(rockIDs.count)
        var likelihoods: [String: Double] = [:]
        for id in rockIDs {
            likelihoods[id] = uniform + (1 - smoothing) * (votes[id, default: 0] / total)
        }
        return ReferenceEvidence(likelihoods: likelihoods)
    }

    static func distance(_ a: [Float], _ b: [Float]) -> Double {
        var sum: Float = 0
        for i in a.indices {
            let d = a[i] - b[i]
            sum += d * d
        }
        return Double(sum.squareRoot())
    }
}
