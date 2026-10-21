import Foundation

public enum CatalogError: Error, Equatable, CustomStringConvertible {
    case missingResource
    case invalid(String)

    public var description: String {
        switch self {
        case .missingResource: "The rock catalog file is missing."
        case .invalid(let reason): "The rock catalog is invalid: \(reason)"
        }
    }
}

/// The rock knowledge base: all rocks, all clue questions, and a dense
/// likelihood table the matcher uses for fast scoring.
public struct RockCatalog: Sendable {
    public let version: Int
    public let rocks: [Rock]
    public let questions: [ClueQuestion]

    /// likelihoods[rockIndex][questionIndex][outcomeIndex], where outcomes follow
    /// `questions[questionIndex].outcomes`.
    let likelihoods: [[[Double]]]
    private let rockIndexByID: [String: Int]
    private let questionIndexByID: [ClueID: Int]

    private struct File: Codable {
        let version: Int
        let questions: [ClueQuestion]
        let rocks: [Rock]
    }

    public init(data: Data) throws {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch let error as CatalogError {
            throw error
        } catch {
            throw CatalogError.invalid("JSON could not be decoded (\(error))")
        }
        try self.init(version: file.version, rocks: file.rocks, questions: file.questions)
    }

    public init(version: Int = 1, rocks: [Rock], questions: [ClueQuestion]) throws {
        try Self.validate(rocks: rocks, questions: questions)
        self.version = version
        self.rocks = rocks
        self.questions = questions
        self.rockIndexByID = Dictionary(uniqueKeysWithValues: rocks.enumerated().map { ($1.id, $0) })
        self.questionIndexByID = Dictionary(uniqueKeysWithValues: questions.enumerated().map { ($1.id, $0) })
        self.likelihoods = rocks.map { rock in
            questions.map { question in
                question.outcomes.map { rock.clues.probability(of: $0, for: question.id) ?? 0 }
            }
        }
    }

    /// The catalog shipped inside the package.
    public static func bundled() throws -> RockCatalog {
        guard let url = Bundle.module.url(forResource: "rocks", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        return try RockCatalog(data: Data(contentsOf: url))
    }

    public func rock(id: String) -> Rock? {
        rockIndexByID[id].map { rocks[$0] }
    }

    public func index(ofRock id: String) -> Int? {
        rockIndexByID[id]
    }

    public func question(_ id: ClueID) -> ClueQuestion? {
        questionIndexByID[id].map { questions[$0] }
    }

    public func index(ofQuestion id: ClueID) -> Int? {
        questionIndexByID[id]
    }

    public func rocks(in family: RockFamily) -> [Rock] {
        rocks.filter { $0.family == family }
    }

    // MARK: - Validation

    static func validate(rocks: [Rock], questions: [ClueQuestion]) throws {
        guard !rocks.isEmpty else { throw CatalogError.invalid("No rocks") }
        guard !questions.isEmpty else { throw CatalogError.invalid("No questions") }

        let rockIDs = rocks.map(\.id)
        guard Set(rockIDs).count == rockIDs.count else {
            throw CatalogError.invalid("Duplicate rock ids")
        }
        let questionIDs = questions.map(\.id)
        guard Set(questionIDs).count == questionIDs.count else {
            throw CatalogError.invalid("Duplicate question ids")
        }

        for question in questions {
            guard (1...3).contains(question.effort) else {
                throw CatalogError.invalid("Question \(question.id) has effort \(question.effort)")
            }
            if let requirement = question.requires {
                guard let parent = questions.first(where: { $0.id == requirement.clue }),
                      parent.outcomes.contains(requirement.answer) else {
                    throw CatalogError.invalid("Question \(question.id) has an invalid prerequisite")
                }
            }
            guard !question.outcomes.contains(.notSure), question.outcomes.count >= 2 else {
                throw CatalogError.invalid("Question \(question.id) needs at least two informative outcomes")
            }
        }

        let knownRocks = Set(rockIDs)
        for rock in rocks {
            guard !rock.id.isEmpty, !rock.name.isEmpty else {
                throw CatalogError.invalid("A rock has an empty id or name")
            }
            guard (1...5).contains(rock.commonness) else {
                throw CatalogError.invalid("\(rock.id) commonness must be 1…5")
            }
            guard rock.hardness.min >= 1, rock.hardness.max <= 10, rock.hardness.min <= rock.hardness.max else {
                throw CatalogError.invalid("\(rock.id) has an invalid hardness range")
            }
            for link in rock.formsFrom + rock.canBecome where !knownRocks.contains(link) {
                throw CatalogError.invalid("\(rock.id) links to unknown rock \(link)")
            }
            for question in questions {
                guard let distribution = rock.clues.table[question.id] else {
                    throw CatalogError.invalid("\(rock.id) is missing clue \(question.id)")
                }
                guard Set(distribution.keys) == Set(question.outcomes) else {
                    throw CatalogError.invalid("\(rock.id) clue \(question.id) has the wrong answers")
                }
                let total = distribution.values.reduce(0, +)
                guard abs(total - 1) <= 0.011 else {
                    throw CatalogError.invalid("\(rock.id) clue \(question.id) probabilities sum to \(total)")
                }
                guard distribution.values.allSatisfy({ $0 > 0 && $0 < 1 }) else {
                    throw CatalogError.invalid("\(rock.id) clue \(question.id) needs probabilities strictly between 0 and 1")
                }
            }
            for clue in rock.clues.table.keys where !questionIDs.contains(clue) {
                throw CatalogError.invalid("\(rock.id) has a clue \(clue) with no question")
            }
        }
    }
}
