import Foundation
import Testing
@testable import RockKit

@Suite("Bayesian matcher")
struct MatcherTests {
    let matcher = Fixtures.matcher
    let catalog = Fixtures.catalog

    func best(_ answers: [ClueID: Answer]) -> MatchResult {
        matcher.match(Evidence(answers: answers))
    }

    @Test("MT-01 no evidence: valid distribution ordered by commonness")
    func noEvidence() {
        let result = matcher.match(Evidence())
        let total = result.candidates.map(\.probability).reduce(0, +)
        #expect(abs(total - 1) < 1e-9)
        #expect(result.candidates.count == catalog.rocks.count)
        let commonness = result.candidates.map { Fixtures.rock($0.rockID).commonness }
        #expect(commonness == commonness.sorted(by: >))
        #expect(Set(result.top(5).map(\.rockID)) == ["granite", "basalt", "sandstone", "shale", "limestone"])
    }

    @Test("MT-02…16 classic field-test combinations identify the right rock", arguments: [
        ("limestone", [ClueID.fizz: Answer.yes, .fossils: .yes, .layers: .yes]),
        ("obsidian", [.glassy: .yes, .color: .dark, .holes: .no]),
        ("pumice", [.floats: .yes, .holes: .yes, .lightweight: .yes]),
        ("scoria", [.holes: .yes, .color: .dark, .floats: .no, .reddish: .yes]),
        ("conglomerate", [.pebbles: .yes, .roundPebbles: .yes]),
        ("breccia", [.pebbles: .yes, .roundPebbles: .no]),
        ("gneiss", [.layers: .yes, .grains: .yes, .speckled: .yes, .sheets: .no]),
        ("schist", [.sparkle: .yes, .layers: .yes, .sheets: .yes, .grains: .yes]),
        ("slate", [.sheets: .yes, .color: .dark, .nailScratch: .no, .sparkle: .no]),
        ("granite", [.color: .light, .grains: .yes, .speckled: .yes, .sparkle: .yes, .fizz: .no]),
        ("gabbro", [.color: .dark, .grains: .yes, .speckled: .yes]),
        ("marble", [.fizz: .yes, .grains: .yes, .sparkle: .yes, .fossils: .no]),
        ("sandstone", [.gritty: .yes, .layers: .yes, .grains: .yes, .fizz: .no]),
        ("coal", [.marks: .yes, .color: .dark, .lightweight: .yes]),
        ("chalk", [.marks: .yes, .color: .light, .fizz: .yes])
    ])
    func classicCombinations(expected: String, answers: [ClueID: Answer]) {
        let result = best(answers)
        #expect(result.best.rockID == expected, "got \(result.top(3).map { "\($0.rockID) \(String(format: "%.2f", $0.probability))" })")
    }

    @Test("MT-04 pumice is very likely once it floats")
    func pumiceConfidence() {
        let result = best([.floats: .yes, .holes: .yes, .lightweight: .yes])
        #expect(result.confidence >= 0.8)
        #expect(result.level == .prettySure)
    }

    @Test("MT-17 'not sure' answers change nothing")
    func notSureIsNeutral() {
        let base = matcher.posterior(for: Evidence(answers: [.fizz: .yes]))
        var answers: [ClueID: Answer] = [.fizz: .yes]
        for clue in ClueID.allCases where clue != .fizz { answers[clue] = .notSure }
        let withNotSure = matcher.posterior(for: Evidence(answers: answers))
        for (a, b) in zip(base, withNotSure) {
            #expect(abs(a - b) < 1e-12)
        }
    }

    @Test("MT-18 contradictory answers still give a valid, uncertain distribution")
    func contradictions() {
        let result = best([.floats: .yes, .fizz: .yes, .glassy: .yes, .pebbles: .yes, .marks: .yes, .nailScratch: .no])
        let total = result.candidates.map(\.probability).reduce(0, +)
        #expect(abs(total - 1) < 1e-9)
        #expect(result.candidates.allSatisfy { $0.probability.isFinite && $0.probability >= 0 })
        #expect(result.confidence < 0.9)
    }

    @Test("MT-19 one wrong answer does not rule out the right rock")
    func robustToMistakes() {
        let result = best([.color: .light, .grains: .yes, .speckled: .yes, .sparkle: .yes, .reddish: .yes, .fizz: .yes])
        let rank = result.rank(of: "granite") ?? 99
        #expect(rank <= 3, "granite rank \(rank)")
    }

    @Test("MT-20 every rock wins when every clue gets its most likely answer")
    func selfConsistency() {
        for rock in catalog.rocks {
            var answers: [ClueID: Answer] = [:]
            for question in catalog.questions {
                if let requirement = question.requires, answers[requirement.clue] != requirement.answer { continue }
                let distribution = rock.clues.table[question.id] ?? [:]
                answers[question.id] = question.outcomes.max { (distribution[$0] ?? 0) < (distribution[$1] ?? 0) }
            }
            let result = best(answers)
            #expect(result.best.rockID == rock.id,
                    "\(rock.id): got \(result.top(3).map { "\($0.rockID) \(String(format: "%.2f", $0.probability))" })")
        }
    }

    @Test("MT-21 simulated kids answering every clue: close to the Bayes-optimal classifier")
    func monteCarloAccuracy() {
        // Every rock is equally likely in this simulation and answers are drawn
        // from the catalog's exact probabilities, so the Bayes-optimal classifier
        // uses those probabilities with a uniform prior and no mistake allowance.
        // The app's matcher instead keeps its commonness prior and mistake rate.
        let optimal = RockMatcher(catalog: catalog, settings: .init(mistakeRate: 0, useCommonnessPrior: false))
        var hits = (top1: 0, top3: 0, optimalTop1: 0, optimalTop3: 0)
        var total = 0
        for (index, rock) in catalog.rocks.enumerated() {
            for trial in 0..<200 {
                var kid = SimulatedKid(rock: rock, seed: UInt64(index * 1000 + trial + 1))
                let evidence = kid.answerEverything(catalog: catalog)
                let rank = matcher.match(evidence).rank(of: rock.id) ?? 99
                let optimalRank = optimal.match(evidence).rank(of: rock.id) ?? 99
                if rank == 1 { hits.top1 += 1 }
                if rank <= 3 { hits.top3 += 1 }
                if optimalRank == 1 { hits.optimalTop1 += 1 }
                if optimalRank <= 3 { hits.optimalTop3 += 1 }
                total += 1
            }
        }
        let top1 = Double(hits.top1) / Double(total)
        let top3 = Double(hits.top3) / Double(total)
        let optimalTop1 = Double(hits.optimalTop1) / Double(total)
        let optimalTop3 = Double(hits.optimalTop3) / Double(total)
        print("MT-21 top-1 \(top1) (Bayes-optimal \(optimalTop1)), top-3 \(top3) (Bayes-optimal \(optimalTop3))")
        #expect(top1 >= optimalTop1 - 0.03)
        #expect(top3 >= optimalTop3 - 0.02)
        #expect(top1 >= 0.65)
        #expect(top3 >= 0.90)
    }

    @Test("MT-25 the uniform-prior option treats every rock as equally likely")
    func uniformPrior() {
        let uniform = RockMatcher(catalog: catalog, settings: .init(useCommonnessPrior: false))
        let probabilities = uniform.posterior(for: Evidence())
        let expected = 1 / Double(catalog.rocks.count)
        #expect(probabilities.allSatisfy { abs($0 - expected) < 1e-12 })
        // Turning the option back on restores the commonness ordering (MT-01).
        var switched = uniform
        switched.settings.useCommonnessPrior = true
        #expect(switched.match(Evidence()).top(5).allSatisfy { Fixtures.rock($0.rockID).commonness == 5 })
    }

    @Test("MT-22 photo evidence alone is softer than kid answers")
    func photoEvidenceIsSoft() {
        let photo = PhotoEvidence(beliefs: [
            .color: [.light: 0.1, .medium: 0.1, .dark: 0.8],
            .grains: [.yes: 0.2, .no: 0.8],
            .glassy: [.yes: 0.8, .no: 0.2]
        ])
        let photoResult = matcher.match(Evidence(photo: photo))
        #expect((photoResult.rank(of: "obsidian") ?? 99) <= 3)

        let answered = best([.color: .dark, .grains: .no, .glassy: .yes])
        #expect(answered.best.rockID == "obsidian")
        #expect(answered.probability(of: "obsidian") > photoResult.probability(of: "obsidian"))
    }

    @Test("MT-22b a kid's answer overrides the photo's guess for the same clue")
    func answersOverridePhoto() {
        let photo = PhotoEvidence(beliefs: [.layers: [.yes: 0.8, .no: 0.2]])
        let withPhoto = matcher.posterior(for: Evidence(answers: [.layers: .no], photo: photo))
        let withoutPhoto = matcher.posterior(for: Evidence(answers: [.layers: .no]))
        for (a, b) in zip(withPhoto, withoutPhoto) {
            #expect(abs(a - b) < 1e-12)
        }
    }

    @Test("MT-23 photo weight 0 ignores photo evidence")
    func zeroPhotoWeight() {
        var settings = RockMatcher.Settings()
        settings.photoWeight = 0
        let silent = RockMatcher(catalog: catalog, settings: settings)
        let photo = PhotoEvidence(beliefs: [.color: [.light: 0.1, .medium: 0.1, .dark: 0.8]])
        let a = silent.posterior(for: Evidence(photo: photo))
        let b = silent.posterior(for: Evidence())
        for (x, y) in zip(a, b) {
            #expect(abs(x - y) < 1e-12)
        }
    }

    @Test("MT-24 confidence levels", arguments: [
        (0.95, ConfidenceLevel.prettySure), (0.6, .prettySure), (0.59, .goodGuess),
        (0.35, .goodGuess), (0.34, .hunch), (0.05, .hunch)
    ])
    func confidenceLevels(probability: Double, level: ConfidenceLevel) {
        #expect(ConfidenceLevel(probability: probability) == level)
        #expect((1...3).contains(level.stars))
    }

    @Test("Reference evidence boosts the matching rock")
    func referenceEvidence() {
        var likelihoods: [String: Double] = [:]
        for rock in catalog.rocks { likelihoods[rock.id] = 0.01 }
        likelihoods["gneiss"] = 0.77
        let result = matcher.match(Evidence(reference: ReferenceEvidence(likelihoods: likelihoods)))
        #expect(result.best.rockID == "gneiss")
    }
}
