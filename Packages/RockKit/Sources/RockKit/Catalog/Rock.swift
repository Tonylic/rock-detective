import Foundation

/// The three great rock families of the rock cycle.
public enum RockFamily: String, Codable, CaseIterable, Sendable, Identifiable {
    case igneous
    case sedimentary
    case metamorphic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .igneous: "Igneous"
        case .sedimentary: "Sedimentary"
        case .metamorphic: "Metamorphic"
        }
    }

    public var emoji: String {
        switch self {
        case .igneous: "🌋"
        case .sedimentary: "🐚"
        case .metamorphic: "🔥"
        }
    }

    /// Where the name comes from, in kid words.
    public var nameMeaning: String {
        switch self {
        case .igneous: "\"Igneous\" comes from the Latin word for fire."
        case .sedimentary: "\"Sedimentary\" comes from the Latin word for settling."
        case .metamorphic: "\"Metamorphic\" comes from Greek words meaning \"change of shape.\""
        }
    }

    public var kidExplanation: String {
        switch self {
        case .igneous:
            "Made when super-hot melted rock (magma or lava) cools down and hardens."
        case .sedimentary:
            "Made when bits of sand, mud, pebbles, shells, or plants pile up and get pressed and glued together."
        case .metamorphic:
            "Made when a rock gets squeezed and heated deep underground until it changes into a new rock, without melting."
        }
    }
}

/// Mohs hardness range of the rock's main minerals.
public struct HardnessRange: Codable, Sendable, Hashable {
    public let min: Double
    public let max: Double

    public init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }

    public var midpoint: Double { (min + max) / 2 }

    public var displayText: String {
        func format(_ value: Double) -> String {
            value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        }
        return min == max ? format(min) : "\(format(min))–\(format(max))"
    }

    /// Everyday comparison used on the rock page. Steel nails and window glass
    /// are both about 5.5 on the Mohs scale.
    public var kidComparison: String {
        if max - min >= 2.5 {
            return "It depends! Some pieces are soft and some are hard, because of what they're made of."
        }
        switch midpoint {
        case ..<2.6: return "Soft — your fingernail can scratch it."
        case ..<4.6: return "Fairly soft — a steel nail can scratch it, but your fingernail can't."
        case ..<5.6: return "Medium — about as hard as a steel nail or window glass."
        default: return "Hard — it can scratch glass, and a steel nail can't scratch it."
        }
    }
}

/// How the procedural illustration of a rock is drawn.
public struct RockArtStyle: Codable, Sendable, Hashable {
    public enum Pattern: String, Codable, Sendable, CaseIterable {
        case speckled, fine, porphyritic, flowBanded, glassy, vesicular, ash
        case crossBedded, fissile, roundClasts, angularClasts, fossiliferous, chalky
        case coal, waxy, slaty, sheen, schistose, banded, veined, sugary
    }

    public let pattern: Pattern
    public let base: String
    public let accents: [String]
    public let seed: UInt64

    public init(pattern: Pattern, base: String, accents: [String], seed: UInt64) {
        self.pattern = pattern
        self.base = base
        self.accents = accents
        self.seed = seed
    }
}

/// Probability of each answer to each clue, for one rock type.
/// In JSON a yes/no clue is a single number, P(yes); the color clue is an
/// object of tone probabilities.
public struct ClueLikelihoods: Sendable, Hashable, Codable {
    public let table: [ClueID: [Answer: Double]]

    public init(table: [ClueID: [Answer: Double]]) {
        self.table = table
    }

    public func probability(of answer: Answer, for clue: ClueID) -> Double? {
        table[clue]?[answer]
    }

    /// P(yes) for a yes/no clue.
    public func yes(_ clue: ClueID) -> Double {
        table[clue]?[.yes] ?? 0
    }

    private enum RawValue: Codable {
        case yes(Double)
        case distribution([String: Double])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                self = .yes(value)
            } else {
                self = .distribution(try container.decode([String: Double].self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .yes(let value): try container.encode(value)
            case .distribution(let values): try container.encode(values)
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: RawValue].self)
        var table: [ClueID: [Answer: Double]] = [:]
        for (key, value) in raw {
            guard let clue = ClueID(rawValue: key) else {
                throw CatalogError.invalid("Unknown clue '\(key)'")
            }
            switch value {
            case .yes(let p):
                table[clue] = [.yes: p, .no: 1 - p]
            case .distribution(let values):
                var distribution: [Answer: Double] = [:]
                for (answerKey, p) in values {
                    guard let answer = Answer(rawValue: answerKey) else {
                        throw CatalogError.invalid("Unknown answer '\(answerKey)' for clue '\(key)'")
                    }
                    distribution[answer] = p
                }
                table[clue] = distribution
            }
        }
        self.table = table
    }

    public func encode(to encoder: Encoder) throws {
        var raw: [String: RawValue] = [:]
        for (clue, distribution) in table {
            if Set(distribution.keys) == [.yes, .no], let p = distribution[.yes] {
                raw[clue.rawValue] = .yes(p)
            } else {
                raw[clue.rawValue] = .distribution(
                    Dictionary(uniqueKeysWithValues: distribution.map { ($0.key.rawValue, $0.value) })
                )
            }
        }
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}

/// One rock type in the knowledge base.
public struct Rock: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    /// How to say tricky names, e.g. gneiss → "NICE".
    public let sayIt: String
    public let family: RockFamily
    /// More precise sub-type, e.g. "Intrusive igneous".
    public let kind: String
    public let summary: String
    public let formation: String
    public let minerals: [String]
    public let hardness: HardnessRange
    public let whereFound: String
    public let funFacts: [String]
    public let formsFrom: [String]
    public let canBecome: [String]
    public let lookAlikeTip: String
    public let safetyNote: String?
    /// How common the rock is where kids look, 1 (rare) … 5 (very common).
    public let commonness: Int
    public let art: RockArtStyle
    public let clues: ClueLikelihoods
}
