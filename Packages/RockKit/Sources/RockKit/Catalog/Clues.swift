import Foundation

/// Every observable property the app can reason about. Each one is a kid-friendly
/// question, and some can also be estimated from the photo.
public enum ClueID: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case color
    case reddish
    case grains
    case speckled
    case quartzBits
    case sparkle
    case glassy
    case layers
    case sheets
    case holes
    case floats
    case fizz
    case pebbles
    case roundPebbles
    case gritty
    case nailScratch
    case marks
    case fossils
    case lightweight
}

/// An answer to a clue question. Yes/no questions use `yes`/`no`; the color
/// question uses `light`/`medium`/`dark`. `notSure` is always allowed and carries
/// no information.
public enum Answer: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case yes
    case no
    case notSure
    case light
    case medium
    case dark

    public var isInformative: Bool { self != .notSure }
}

/// A question a kid can answer about their rock.
public struct ClueQuestion: Codable, Sendable, Identifiable, Hashable {
    public struct Option: Codable, Sendable, Hashable {
        public let answer: Answer
        public let label: String
        public let emoji: String
        public let detail: String?

        public init(answer: Answer, label: String, emoji: String, detail: String? = nil) {
            self.answer = answer
            self.label = label
            self.emoji = emoji
            self.detail = detail
        }
    }

    /// The question only makes sense once another clue has a given answer
    /// (e.g. "Are the pebbles round?" needs "made of pebbles = yes").
    public struct Prerequisite: Codable, Sendable, Hashable {
        public let clue: ClueID
        public let answer: Answer

        public init(clue: ClueID, answer: Answer) {
            self.clue = clue
            self.answer = answer
        }
    }

    public let id: ClueID
    public let prompt: String
    public let shortLabel: String
    public let emoji: String
    public let howTo: String
    public let safety: String?
    /// 1 = just look, 2 = handle the rock, 3 = needs a tool or a grown-up.
    public let effort: Int
    public let requires: Prerequisite?
    /// Custom answer options. `nil` means a plain yes/no question.
    public let options: [Option]?

    public init(
        id: ClueID,
        prompt: String,
        shortLabel: String,
        emoji: String,
        howTo: String,
        safety: String? = nil,
        effort: Int = 1,
        requires: Prerequisite? = nil,
        options: [Option]? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.shortLabel = shortLabel
        self.emoji = emoji
        self.howTo = howTo
        self.safety = safety
        self.effort = effort
        self.requires = requires
        self.options = options
    }

    /// The informative answers this question can have (never includes `notSure`).
    public var outcomes: [Answer] { options?.map(\.answer) ?? [.yes, .no] }

    public var isYesNo: Bool { options == nil }

    /// Button options shown to kids, always ending with "Not sure".
    public var displayOptions: [Option] {
        let main = options ?? [
            Option(answer: .yes, label: "Yes", emoji: "👍"),
            Option(answer: .no, label: "No", emoji: "👎")
        ]
        return main + [Option(answer: .notSure, label: "Not sure", emoji: "🤷")]
    }

    public func label(for answer: Answer) -> String {
        displayOptions.first { $0.answer == answer }?.label ?? answer.rawValue
    }

    public func emoji(for answer: Answer) -> String {
        displayOptions.first { $0.answer == answer }?.emoji ?? ""
    }
}
