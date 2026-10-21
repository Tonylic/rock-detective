import CoreGraphics
import Foundation
import Observation

/// View model for one rock identification: photo → photo clues → ranked rocks,
/// then kid answers that refine the ranking. Every change is saved to the
/// collection.
@MainActor
@Observable
public final class IdentificationSession {
    public enum Phase: Equatable, Sendable {
        case idle
        case analyzing
        case ready
    }

    public private(set) var phase: Phase = .idle
    public private(set) var photo: CGImage?
    public private(set) var evidence = Evidence()
    public private(set) var result: MatchResult
    public private(set) var nextQuestion: ClueQuestion?
    public private(set) var findingID: UUID?
    /// How long the photo analysis took (for diagnostics and tests).
    public private(set) var analysisDuration: Duration?

    public let identifier: RockIdentifier
    private let store: HistoryStore?

    public init(identifier: RockIdentifier, store: HistoryStore?) {
        self.identifier = identifier
        self.store = store
        self.result = identifier.result(for: Evidence())
    }

    /// Re-opens a saved find so the kid can keep answering clues.
    public convenience init(restoring finding: Finding, identifier: RockIdentifier, store: HistoryStore?) {
        self.init(identifier: identifier, store: store)
        evidence = finding.evidence
        findingID = finding.id
        photo = store?.loadPhoto(for: finding)
        refresh()
        phase = .ready
    }

    public var catalog: RockCatalog { identifier.catalog }

    public var bestRock: Rock? { catalog.rock(id: result.best.rockID) }

    /// The next two most likely rocks.
    public var alternatives: [Candidate] { Array(result.candidates.dropFirst().prefix(2)) }

    public var photoClues: [PhotoClue] { evidence.photo?.spottedClues ?? [] }

    /// Answered questions in catalog order.
    public var answeredClues: [(question: ClueQuestion, answer: Answer)] {
        catalog.questions.compactMap { question in
            evidence.answers[question.id].map { (question, $0) }
        }
    }

    // MARK: - Actions

    /// Analyses the photo off the main actor, ranks the rocks, and saves the find.
    public func identify(_ image: CGImage) async {
        phase = .analyzing
        photo = image
        findingID = nil
        let identifier = self.identifier
        let start = ContinuousClock.now
        let photoEvidence = await Task.detached(priority: .userInitiated) {
            identifier.evidence(fromPhoto: image)
        }.value
        analysisDuration = ContinuousClock.now - start
        evidence = photoEvidence
        refresh()
        phase = .ready
        persist()
    }

    public func answer(_ answer: Answer, to clue: ClueID) {
        evidence.answers[clue] = answer
        pruneUnreachableAnswers()
        refresh()
        persist()
    }

    public func clearAnswer(for clue: ClueID) {
        evidence.answers[clue] = nil
        pruneUnreachableAnswers()
        refresh()
        persist()
    }

    // MARK: - Private

    /// Drops answers to follow-up questions whose prerequisite no longer holds
    /// (e.g. "round pebbles" after changing "made of pebbles" to no).
    private func pruneUnreachableAnswers() {
        var changed = true
        while changed {
            changed = false
            for question in catalog.questions {
                guard let requirement = question.requires, evidence.answers[question.id] != nil else { continue }
                if evidence.answers[requirement.clue] != requirement.answer {
                    evidence.answers[question.id] = nil
                    changed = true
                }
            }
        }
    }

    private func refresh() {
        result = identifier.result(for: evidence)
        nextQuestion = identifier.nextQuestion(for: evidence)
    }

    private func persist() {
        guard let store else { return }
        if let id = findingID, let existing = store.finding(id: id) {
            try? store.update(existing.updated(result: result, evidence: evidence))
        } else {
            let finding = Finding(result: result, evidence: evidence)
            findingID = finding.id
            _ = try? store.add(finding, photo: photo)
        }
    }
}
