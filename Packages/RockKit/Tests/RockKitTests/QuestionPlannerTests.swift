import Foundation
import Testing
@testable import RockKit

@Suite("Question planner")
struct QuestionPlannerTests {
    let planner = Fixtures.planner
    let catalog = Fixtures.catalog

    @Test("QP-01 with no evidence it suggests an informative, applicable question")
    func firstQuestion() throws {
        let question = try #require(planner.nextQuestion(for: Evidence()))
        #expect(question.id != .roundPebbles)
        let top = try #require(planner.suggestions(for: Evidence()).first)
        #expect(top.gain > 0.2)
        #expect(!planner.suggestions(for: Evidence()).contains { $0.question.id == .roundPebbles })
    }

    @Test("QP-02 after 'made of pebbles = yes' it asks whether the pebbles are round")
    func followUpQuestion() {
        let next = planner.nextQuestion(for: Evidence(answers: [.pebbles: .yes]))
        #expect(next?.id == .roundPebbles)
    }

    @Test("QP-03 answered and 'not sure' questions are never asked again")
    func neverRepeats() {
        var evidence = Evidence()
        var asked: Set<ClueID> = []
        var kid = SimulatedKid(rock: Fixtures.rock("basalt"), seed: 42)
        for step in 0..<catalog.questions.count {
            guard let question = planner.nextQuestion(for: evidence) else { break }
            #expect(!asked.contains(question.id), "repeated \(question.id)")
            asked.insert(question.id)
            evidence.answers[question.id] = step.isMultiple(of: 3) ? .notSure : kid.answer(question)
        }
        #expect(!asked.isEmpty)
    }

    @Test("QP-04 stops asking once the best match is very likely")
    func stopsWhenConfident() {
        let evidence = Evidence(answers: [.floats: .yes, .holes: .yes, .lightweight: .yes, .color: .light, .gritty: .yes])
        #expect(Fixtures.matcher.match(evidence).confidence >= 0.9)
        #expect(planner.nextQuestion(for: evidence) == nil)
    }

    @Test("QP-05 returns nil when every question is answered")
    func allAnswered() {
        var answers: [ClueID: Answer] = [:]
        for question in catalog.questions { answers[question.id] = .notSure }
        #expect(planner.nextQuestion(for: Evidence(answers: answers)) == nil)
        #expect(planner.suggestions(for: Evidence(answers: answers)).isEmpty)
    }

    @Test("QP-06 five adaptive questions beat five random questions")
    func adaptiveBeatsRandom() {
        let maxQuestions = 5
        var adaptive = (top1: 0, top3: 0)
        var random = (top1: 0, top3: 0)
        var total = 0
        for (index, rock) in catalog.rocks.enumerated() {
            for trial in 0..<50 {
                let seed = UInt64(index * 10_000 + trial + 1)

                var kid = SimulatedKid(rock: rock, seed: seed)
                var evidence = Evidence()
                for _ in 0..<maxQuestions {
                    guard let question = planner.nextQuestion(for: evidence) else { break }
                    evidence.answers[question.id] = kid.answer(question)
                }
                let rank = Fixtures.matcher.match(evidence).rank(of: rock.id) ?? 99
                if rank == 1 { adaptive.top1 += 1 }
                if rank <= 3 { adaptive.top3 += 1 }

                var randomKid = SimulatedKid(rock: rock, seed: seed)
                var picker = SeededGenerator(seed: seed &* 31)
                var randomEvidence = Evidence()
                var pool = catalog.questions.filter { $0.requires == nil }
                for _ in 0..<maxQuestions where !pool.isEmpty {
                    let question = pool.remove(at: Int(picker.unit() * Double(pool.count)) % pool.count)
                    randomEvidence.answers[question.id] = randomKid.answer(question)
                }
                let randomRank = Fixtures.matcher.match(randomEvidence).rank(of: rock.id) ?? 99
                if randomRank == 1 { random.top1 += 1 }
                if randomRank <= 3 { random.top3 += 1 }
                total += 1
            }
        }
        let rate = { (hits: Int) in Double(hits) / Double(total) }
        print("QP-06 adaptive top-1 \(rate(adaptive.top1)) top-3 \(rate(adaptive.top3)); random top-1 \(rate(random.top1)) top-3 \(rate(random.top3))")
        #expect(rate(adaptive.top3) >= 0.70)
        #expect(rate(adaptive.top1) >= 0.42)
        #expect(rate(adaptive.top1) >= 1.5 * rate(random.top1))
        #expect(rate(adaptive.top3) > rate(random.top3) + 0.1)
    }

    @Test("QP-07 suggestions have non-negative gain and are ordered by utility")
    func orderedSuggestions() {
        let suggestions = planner.suggestions(for: Evidence(answers: [.color: .dark]))
        #expect(!suggestions.isEmpty)
        #expect(suggestions.allSatisfy { $0.gain >= 0 && $0.utility <= $0.gain + 1e-12 })
        let utilities = suggestions.map(\.utility)
        #expect(utilities == utilities.sorted(by: >))
    }

    @Test("Prerequisite questions are not applicable until unlocked")
    func applicability() {
        let round = Fixtures.question(.roundPebbles)
        #expect(!planner.isApplicable(round, evidence: Evidence()))
        #expect(!planner.isApplicable(round, evidence: Evidence(answers: [.pebbles: .no])))
        #expect(planner.isApplicable(round, evidence: Evidence(answers: [.pebbles: .yes])))
    }
}
