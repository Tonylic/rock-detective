import Foundation

/// Picks the clue question that will teach us the most, like a good game of
/// 20 Questions: the one with the largest expected information gain (drop in
/// entropy of the posterior), gently discounted for tests that need a tool.
public struct QuestionPlanner: Sendable {
    public struct Suggestion: Sendable, Hashable {
        public let question: ClueQuestion
        /// Expected information gain in bits.
        public let gain: Double
        /// Gain adjusted for effort and follow-ups; suggestions are ordered by this.
        public let utility: Double
    }

    public let matcher: RockMatcher
    /// Stop asking once the best match is at least this likely.
    public var stopConfidence: Double
    /// Stop asking when no question is expected to gain at least this many bits.
    public var minimumGain: Double
    /// Utility = gain / (1 + effortPenalty × (effort − 1)).
    public var effortPenalty: Double
    /// Follow-up questions that were just unlocked (e.g. "Are the pebbles
    /// round?") get this utility multiplier, so the conversation stays on topic.
    public var followUpBonus: Double

    public init(
        matcher: RockMatcher,
        stopConfidence: Double = 0.9,
        minimumGain: Double = 0.02,
        effortPenalty: Double = 0.15,
        followUpBonus: Double = 2
    ) {
        self.matcher = matcher
        self.stopConfidence = stopConfidence
        self.minimumGain = minimumGain
        self.effortPenalty = effortPenalty
        self.followUpBonus = followUpBonus
    }

    private var catalog: RockCatalog { matcher.catalog }

    public func isApplicable(_ question: ClueQuestion, evidence: Evidence) -> Bool {
        guard evidence.answers[question.id] == nil else { return false }
        if let requirement = question.requires {
            return evidence.answers[requirement.clue] == requirement.answer
        }
        return true
    }

    /// All applicable questions ordered by utility (best first).
    public func suggestions(for evidence: Evidence) -> [Suggestion] {
        let posterior = matcher.posterior(for: evidence)
        let entropy = Self.entropy(posterior)

        var suggestions: [Suggestion] = []
        for (q, question) in catalog.questions.enumerated() where isApplicable(question, evidence: evidence) {
            var expectedEntropy = 0.0
            for o in question.outcomes.indices {
                var updated = posterior
                var total = 0.0
                for r in updated.indices {
                    updated[r] *= matcher.answerLikelihood(rock: r, question: q, outcome: o)
                    total += updated[r]
                }
                guard total > 0 else { continue }
                for r in updated.indices { updated[r] /= total }
                expectedEntropy += total * Self.entropy(updated)
            }
            let gain = max(0, entropy - expectedEntropy)
            var utility = gain / (1 + effortPenalty * Double(question.effort - 1))
            if question.requires != nil { utility *= followUpBonus }
            suggestions.append(Suggestion(question: question, gain: gain, utility: utility))
        }

        // Stable order: by utility, then by catalog order (simpler questions come first).
        let order = Dictionary(uniqueKeysWithValues: catalog.questions.enumerated().map { ($1.id, $0) })
        return suggestions.sorted {
            if abs($0.utility - $1.utility) > 1e-12 { return $0.utility > $1.utility }
            return order[$0.question.id, default: 0] < order[$1.question.id, default: 0]
        }
    }

    /// The best next question, or `nil` when we are confident enough or no
    /// question would help.
    public func nextQuestion(for evidence: Evidence) -> ClueQuestion? {
        let posterior = matcher.posterior(for: evidence)
        if let best = posterior.max(), best >= stopConfidence { return nil }
        guard let top = suggestions(for: evidence).first, top.gain >= minimumGain else { return nil }
        return top.question
    }

    static func entropy(_ distribution: [Double]) -> Double {
        distribution.reduce(0) { partial, p in
            p > 0 ? partial - p * log2(p) : partial
        }
    }
}
