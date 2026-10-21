import Foundation

/// How sure the app is, in kid words.
public enum ConfidenceLevel: String, Codable, Sendable, CaseIterable {
    case prettySure
    case goodGuess
    case hunch

    public init(probability: Double) {
        switch probability {
        case 0.6...: self = .prettySure
        case 0.35...: self = .goodGuess
        default: self = .hunch
        }
    }

    public var stars: Int {
        switch self {
        case .prettySure: 3
        case .goodGuess: 2
        case .hunch: 1
        }
    }

    public var title: String {
        switch self {
        case .prettySure: "I'm pretty sure!"
        case .goodGuess: "Good guess!"
        case .hunch: "Just a hunch…"
        }
    }

    public var encouragement: String {
        switch self {
        case .prettySure: "The clues fit really well. Great detective work!"
        case .goodGuess: "Answer a clue or two to be more certain."
        case .hunch: "Photos can be tricky. Answer some clues so we can crack the case!"
        }
    }
}

public struct Candidate: Codable, Sendable, Hashable, Identifiable {
    public let rockID: String
    public let probability: Double

    public var id: String { rockID }

    public init(rockID: String, probability: Double) {
        self.rockID = rockID
        self.probability = probability
    }
}

/// A ranked list of rock candidates. Probabilities sum to 1.
public struct MatchResult: Codable, Sendable, Hashable {
    public let candidates: [Candidate]

    public init(candidates: [Candidate]) {
        precondition(!candidates.isEmpty, "A match result needs at least one candidate")
        self.candidates = candidates
    }

    public var best: Candidate { candidates[0] }
    public var confidence: Double { best.probability }
    public var level: ConfidenceLevel { ConfidenceLevel(probability: confidence) }

    public func top(_ count: Int) -> [Candidate] {
        Array(candidates.prefix(count))
    }

    public func probability(of rockID: String) -> Double {
        candidates.first { $0.rockID == rockID }?.probability ?? 0
    }

    public func rank(of rockID: String) -> Int? {
        candidates.firstIndex { $0.rockID == rockID }.map { $0 + 1 }
    }
}

/// Naive Bayes over the knowledge base, with:
/// * a small "kid mistake" rate on answers, so one wrong answer can't rule a rock out;
/// * photo clues folded in as virtual (soft) evidence, down-weighted;
/// * optional reference-picture likelihoods (k-NN over feature prints).
public struct RockMatcher: Sendable {
    public struct Settings: Sendable, Hashable {
        /// Chance a kid's answer is effectively random (mixes each likelihood
        /// with a uniform distribution over the question's outcomes).
        public var mistakeRate: Double
        /// Exponent applied to photo virtual evidence.
        public var photoWeight: Double
        /// Exponent applied to reference-picture evidence.
        public var referenceWeight: Double
        /// Weight rocks by how common they are where kids look. Turn off for a
        /// uniform prior (e.g. when every rock is equally likely, as in tests).
        public var useCommonnessPrior: Bool

        public init(
            mistakeRate: Double = 0.08,
            photoWeight: Double = 0.7,
            referenceWeight: Double = 0.6,
            useCommonnessPrior: Bool = true
        ) {
            self.mistakeRate = mistakeRate
            self.photoWeight = photoWeight
            self.referenceWeight = referenceWeight
            self.useCommonnessPrior = useCommonnessPrior
        }
    }

    public let catalog: RockCatalog
    public var settings: Settings
    private let commonnessLogPriors: [Double]

    public init(catalog: RockCatalog, settings: Settings = Settings()) {
        self.catalog = catalog
        self.settings = settings
        let total = Double(catalog.rocks.reduce(0) { $0 + $1.commonness })
        self.commonnessLogPriors = catalog.rocks.map { log(Double($0.commonness) / total) }
    }

    private var logPriors: [Double] {
        settings.useCommonnessPrior
            ? commonnessLogPriors
            : Array(repeating: -log(Double(catalog.rocks.count)), count: catalog.rocks.count)
    }

    /// P(answer | rock) including the kid-mistake rate.
    func answerLikelihood(rock: Int, question: Int, outcome: Int) -> Double {
        let probabilities = catalog.likelihoods[rock][question]
        let uniform = 1.0 / Double(probabilities.count)
        return (1 - settings.mistakeRate) * probabilities[outcome] + settings.mistakeRate * uniform
    }

    /// Unnormalised log posterior for every rock, in catalog order.
    public func logScores(for evidence: Evidence) -> [Double] {
        var scores = logPriors
        let photoBeliefs = settings.photoWeight > 0 ? evidence.photo?.beliefs ?? [:] : [:]

        // Walk the questions in catalog order so sums are deterministic.
        for (q, question) in catalog.questions.enumerated() {
            if let answer = evidence.answers[question.id], answer.isInformative {
                guard let o = question.outcomes.firstIndex(of: answer) else { continue }
                for r in scores.indices {
                    scores[r] += log(answerLikelihood(rock: r, question: q, outcome: o))
                }
            } else if let beliefs = photoBeliefs[question.id] {
                // Photo clues only count when the kid hasn't answered that clue:
                // their own observation beats the photo's guess.
                let weights = question.outcomes.map { beliefs[$0] ?? 0 }
                guard weights.contains(where: { $0 > 0 }) else { continue }
                for r in scores.indices {
                    let probabilities = catalog.likelihoods[r][q]
                    var likelihood = 0.0
                    for o in weights.indices {
                        likelihood += probabilities[o] * weights[o]
                    }
                    scores[r] += settings.photoWeight * log(max(likelihood, 1e-9))
                }
            }
        }

        if let reference = evidence.reference, settings.referenceWeight > 0, !reference.likelihoods.isEmpty {
            let floor = 0.1 / Double(catalog.rocks.count)
            for (r, rock) in catalog.rocks.enumerated() {
                let likelihood = max(reference.likelihoods[rock.id] ?? floor, 1e-9)
                scores[r] += settings.referenceWeight * log(likelihood)
            }
        }
        return scores
    }

    /// Normalised posterior probabilities, in catalog order.
    public func posterior(for evidence: Evidence) -> [Double] {
        Self.softmax(logScores(for: evidence))
    }

    public func match(_ evidence: Evidence) -> MatchResult {
        let probabilities = posterior(for: evidence)
        let candidates = zip(catalog.rocks, probabilities)
            .map { Candidate(rockID: $0.id, probability: $1) }
            .sorted {
                $0.probability != $1.probability ? $0.probability > $1.probability : $0.rockID < $1.rockID
            }
        return MatchResult(candidates: candidates)
    }

    static func softmax(_ values: [Double]) -> [Double] {
        guard let maximum = values.max(), maximum.isFinite else {
            return Array(repeating: 1 / Double(max(values.count, 1)), count: values.count)
        }
        let exponentials = values.map { exp($0 - maximum) }
        let total = exponentials.reduce(0, +)
        return exponentials.map { $0 / total }
    }
}
