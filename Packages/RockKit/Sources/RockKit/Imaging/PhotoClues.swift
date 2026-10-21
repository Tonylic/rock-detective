import Foundation

/// A short, kid-readable description of something noticed in the photo.
public struct PhotoClue: Sendable, Hashable, Identifiable {
    public let id: String
    public let emoji: String
    public let text: String
    public let clue: ClueID

    public init(id: String, emoji: String, text: String, clue: ClueID) {
        self.id = id
        self.emoji = emoji
        self.text = text
        self.clue = clue
    }
}

extension PhotoEvidence {
    static let strongBelief = 0.65
    static let weakBelief = 0.3

    /// The answer the photo points to for a clue, if it points clearly
    /// anywhere. Shown to kids as a guess to check, never as a fact.
    public func suggestedAnswer(for clue: ClueID) -> Answer? {
        guard let beliefs = beliefs[clue] else { return nil }
        if clue == .color {
            guard let (tone, belief) = beliefs.max(by: { $0.value < $1.value }), belief >= 0.5 else { return nil }
            return tone
        }
        guard let yes = beliefs[.yes] else { return nil }
        if yes >= Self.strongBelief { return .yes }
        if yes <= Self.weakBelief { return .no }
        return nil
    }

    /// The clues worth telling a kid about, strongest first.
    public var spottedClues: [PhotoClue] {
        var clues: [PhotoClue] = []

        if let tones = beliefs[.color], let (tone, belief) = tones.max(by: { $0.value < $1.value }), belief >= 0.45 {
            switch tone {
            case .light: clues.append(PhotoClue(id: "light", emoji: "☁️", text: "Mostly light colors", clue: .color))
            case .dark: clues.append(PhotoClue(id: "dark", emoji: "🌑", text: "Mostly dark colors", clue: .color))
            default: clues.append(PhotoClue(id: "medium", emoji: "🌥️", text: "In-between colors", clue: .color))
            }
        }
        if let p = belief(.yes, for: .reddish), p >= Self.strongBelief {
            clues.append(PhotoClue(id: "reddish", emoji: "🌸", text: "A pink or reddish tint", clue: .reddish))
        }
        if let p = belief(.yes, for: .speckled), p >= Self.strongBelief {
            clues.append(PhotoClue(id: "speckled", emoji: "🧂", text: "Salt-and-pepper specks", clue: .speckled))
        }
        if let p = belief(.yes, for: .grains) {
            if p >= Self.strongBelief {
                clues.append(PhotoClue(id: "grains", emoji: "🔍", text: "A grainy texture", clue: .grains))
            } else if p <= Self.weakBelief {
                clues.append(PhotoClue(id: "fine", emoji: "🫧", text: "A smooth, fine texture", clue: .grains))
            }
        }
        if let p = belief(.yes, for: .layers), p >= Self.strongBelief {
            clues.append(PhotoClue(id: "layers", emoji: "🍰", text: "Stripes or layers", clue: .layers))
        }
        if let p = belief(.yes, for: .glassy), p >= Self.strongBelief {
            clues.append(PhotoClue(id: "glassy", emoji: "🪞", text: "A glassy shine", clue: .glassy))
        }
        return clues
    }
}
