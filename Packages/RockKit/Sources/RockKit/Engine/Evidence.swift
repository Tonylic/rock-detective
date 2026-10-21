import Foundation

/// Numbers measured from a photo. Kept so a saved find can show its photo clues
/// again without re-analysing the picture.
public struct PhotoFeatures: Codable, Sendable, Hashable {
    /// Median brightness, 0 (black) … 1 (white).
    public var medianLuminance: Double
    /// Fraction of pixels that are clearly pink, red, or orange.
    public var warmFraction: Double
    /// Mean local contrast (5×5 standard deviation), ignoring glare: visible grains.
    public var textureEnergy: Double
    /// Fraction of pixels that stand out strongly from their 9×9 neighbourhood:
    /// salt-and-pepper specks (glare excluded).
    public var speckleFraction: Double
    /// 0 … 1, how strongly the picture's edges line up in one direction
    /// (layers, stripes, bands).
    public var orientationCoherence: Double
    /// Fraction of small, bright, colourless highlights on a darker body: glassy shine.
    public var specularFraction: Double

    public init(
        medianLuminance: Double,
        warmFraction: Double,
        textureEnergy: Double,
        speckleFraction: Double,
        orientationCoherence: Double,
        specularFraction: Double
    ) {
        self.medianLuminance = medianLuminance
        self.warmFraction = warmFraction
        self.textureEnergy = textureEnergy
        self.speckleFraction = speckleFraction
        self.orientationCoherence = orientationCoherence
        self.specularFraction = specularFraction
    }
}

/// Soft evidence read from a photo: for some clues, a belief in each answer.
/// Beliefs are deliberately never certain, because lighting and cameras can
/// fool photo analysis.
public struct PhotoEvidence: Codable, Sendable, Hashable {
    public var features: PhotoFeatures?
    public var beliefs: [ClueID: [Answer: Double]]

    public init(features: PhotoFeatures? = nil, beliefs: [ClueID: [Answer: Double]] = [:]) {
        self.features = features
        self.beliefs = beliefs
    }

    public static let none = PhotoEvidence()

    public var isEmpty: Bool { beliefs.isEmpty }

    public func belief(_ answer: Answer, for clue: ClueID) -> Double? {
        beliefs[clue]?[answer]
    }
}

/// Per-rock likelihoods from matching the photo against reference pictures.
public struct ReferenceEvidence: Codable, Sendable, Hashable {
    public var likelihoods: [String: Double]

    public init(likelihoods: [String: Double]) {
        self.likelihoods = likelihoods
    }
}

/// Everything known about the rock so far.
public struct Evidence: Codable, Sendable, Hashable {
    public var answers: [ClueID: Answer]
    public var photo: PhotoEvidence?
    public var reference: ReferenceEvidence?

    public init(
        answers: [ClueID: Answer] = [:],
        photo: PhotoEvidence? = nil,
        reference: ReferenceEvidence? = nil
    ) {
        self.answers = answers
        self.photo = photo
        self.reference = reference
    }

    /// Answers that carry information (everything except "not sure").
    public var informativeAnswers: [ClueID: Answer] {
        answers.filter { $0.value.isInformative }
    }

    public func answering(_ clue: ClueID, with answer: Answer) -> Evidence {
        var copy = self
        copy.answers[clue] = answer
        return copy
    }
}
