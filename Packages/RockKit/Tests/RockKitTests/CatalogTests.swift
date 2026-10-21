import Foundation
import Testing
@testable import RockKit

@Suite("Knowledge base")
struct CatalogTests {
    let catalog = Fixtures.catalog

    @Test("KB-01 bundled catalog loads with 24 rocks and 19 questions")
    func loadsBundledCatalog() throws {
        let catalog = try RockCatalog.bundled()
        #expect(catalog.rocks.count == 24)
        #expect(catalog.questions.count == 19)
        #expect(Set(catalog.questions.map(\.id)) == Set(ClueID.allCases))
    }

    @Test("KB-02 ids and names are unique and non-empty")
    func uniqueIDs() {
        let ids = catalog.rocks.map(\.id)
        let names = catalog.rocks.map(\.name)
        #expect(Set(ids).count == ids.count)
        #expect(Set(names).count == names.count)
        #expect(ids.allSatisfy { !$0.isEmpty })
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    @Test("KB-03 every rock has a likelihood strictly between 0 and 1 for every yes/no clue")
    func yesNoLikelihoods() {
        for rock in catalog.rocks {
            for question in catalog.questions where question.isYesNo {
                let p = rock.clues.yes(question.id)
                #expect(p > 0 && p < 1, "\(rock.id).\(question.id) = \(p)")
            }
        }
    }

    @Test("KB-04 every color distribution sums to 1")
    func colorDistributions() {
        for rock in catalog.rocks {
            let distribution = rock.clues.table[.color] ?? [:]
            #expect(Set(distribution.keys) == [.light, .medium, .dark], "\(rock.id)")
            #expect(abs(distribution.values.reduce(0, +) - 1) <= 0.01, "\(rock.id)")
        }
    }

    @Test("KB-05 each family is well represented")
    func familyCounts() {
        #expect(catalog.rocks(in: .igneous).count == 10)
        #expect(catalog.rocks(in: .sedimentary).count == 8)
        #expect(catalog.rocks(in: .metamorphic).count == 6)
    }

    @Test("KB-06 hardness ranges are valid Mohs values")
    func hardnessRanges() {
        for rock in catalog.rocks {
            #expect(rock.hardness.min >= 1 && rock.hardness.max <= 10 && rock.hardness.min <= rock.hardness.max, "\(rock.id)")
        }
    }

    @Test("KB-07 rock-cycle links point to real rocks and are mirrored")
    func rockCycleLinks() {
        for rock in catalog.rocks {
            for target in rock.canBecome {
                let other = catalog.rock(id: target)
                #expect(other != nil, "\(rock.id) → \(target)")
                #expect(other?.formsFrom.contains(rock.id) == true, "\(target) should list \(rock.id) in formsFrom")
            }
            for source in rock.formsFrom {
                let other = catalog.rock(id: source)
                #expect(other != nil, "\(source) → \(rock.id)")
                #expect(other?.canBecome.contains(rock.id) == true, "\(source) should list \(rock.id) in canBecome")
            }
        }
    }

    @Test("KB-08 question prerequisites reference existing questions and answers")
    func prerequisites() {
        let round = Fixtures.question(.roundPebbles)
        #expect(round.requires == ClueQuestion.Prerequisite(clue: .pebbles, answer: .yes))
        for question in catalog.questions {
            if let requirement = question.requires {
                #expect(catalog.question(requirement.clue)?.outcomes.contains(requirement.answer) == true)
            }
        }
    }

    @Test("KB-09 kid-facing text is present for every rock and question")
    func kidText() {
        for rock in catalog.rocks {
            #expect(!rock.summary.isEmpty, "\(rock.id)")
            #expect(!rock.formation.isEmpty, "\(rock.id)")
            #expect(!rock.minerals.isEmpty, "\(rock.id)")
            #expect(!rock.whereFound.isEmpty, "\(rock.id)")
            #expect(rock.funFacts.count >= 2, "\(rock.id)")
            #expect(!rock.lookAlikeTip.isEmpty, "\(rock.id)")
            #expect(!rock.sayIt.isEmpty, "\(rock.id)")
            #expect(!rock.kind.isEmpty, "\(rock.id)")
        }
        for question in catalog.questions {
            #expect(!question.prompt.isEmpty && !question.howTo.isEmpty && !question.emoji.isEmpty, "\(question.id)")
            #expect(question.displayOptions.last?.answer == .notSure)
        }
        // Tests that need a tool or vinegar must carry a safety note.
        #expect(Fixtures.question(.fizz).safety != nil)
        #expect(Fixtures.question(.nailScratch).safety != nil)
        #expect(Fixtures.rock("obsidian").safetyNote != nil)
    }

    @Test("KB-10 only carbonate rocks fizz strongly with vinegar")
    func fizzScience() {
        for id in ["limestone", "chalk", "marble"] {
            #expect(Fixtures.rock(id).clues.yes(.fizz) >= 0.85, "\(id)")
        }
        for rock in catalog.rocks where !["limestone", "chalk", "marble"].contains(rock.id) {
            #expect(rock.clues.yes(.fizz) <= 0.2, "\(rock.id) fizz")
        }
    }

    @Test("KB-11 hardness clues match mineralogy")
    func nailScience() {
        for id in ["quartzite", "chert"] {
            #expect(Fixtures.rock(id).clues.yes(.nailScratch) <= 0.1, "\(id)")
        }
        for id in ["limestone", "chalk", "coal"] {
            #expect(Fixtures.rock(id).clues.yes(.nailScratch) >= 0.8, "\(id)")
        }
        // Rocks harder than a steel nail (≈5.5) should rarely be scratched by one.
        for rock in catalog.rocks where rock.hardness.min >= 6 {
            #expect(rock.clues.yes(.nailScratch) <= 0.35, "\(rock.id)")
        }
    }

    @Test("KB-12 only pumice usually floats")
    func floatScience() {
        for rock in catalog.rocks {
            if rock.id == "pumice" {
                #expect(rock.clues.yes(.floats) >= 0.5)
            } else {
                #expect(rock.clues.yes(.floats) < 0.5, "\(rock.id)")
            }
        }
    }

    @Test("KB-13 igneous rocks almost never contain fossils")
    func igneousFossils() {
        for rock in catalog.rocks(in: .igneous) {
            #expect(rock.clues.yes(.fossils) <= 0.03, "\(rock.id)")
        }
    }

    @Test("KB-14 Mohs hardness spot checks")
    func mohsSpotChecks() {
        #expect(Fixtures.rock("quartzite").hardness.max >= 7)
        #expect(Fixtures.rock("chert").hardness.max >= 7)
        #expect(Fixtures.rock("limestone").hardness.max <= 4)
        #expect(Fixtures.rock("marble").hardness.max <= 4)
        #expect(Fixtures.rock("chalk").hardness.max <= 3)
        #expect(Fixtures.rock("obsidian").hardness.max <= 6)
    }

    @Test("KB-15 rocks are in the right family", arguments: [
        ("granite", RockFamily.igneous), ("basalt", .igneous), ("obsidian", .igneous), ("pumice", .igneous),
        ("sandstone", .sedimentary), ("limestone", .sedimentary), ("shale", .sedimentary), ("coal", .sedimentary),
        ("marble", .metamorphic), ("slate", .metamorphic), ("gneiss", .metamorphic), ("quartzite", .metamorphic)
    ])
    func families(id: String, family: RockFamily) {
        #expect(Fixtures.rock(id).family == family)
    }

    @Test("KB-16 malformed catalogs are rejected")
    func malformedCatalog() throws {
        #expect(throws: CatalogError.self) { try RockCatalog(data: Data("not json".utf8)) }

        // A rock missing a clue.
        let url = try #require(Bundle.module.url(forResource: "rocks", withExtension: "json"))
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var rocks = try #require(json["rocks"] as? [[String: Any]])
        var clues = try #require(rocks[0]["clues"] as? [String: Any])
        clues.removeValue(forKey: "fizz")
        rocks[0]["clues"] = clues
        json["rocks"] = rocks
        let broken = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: CatalogError.self) { try RockCatalog(data: broken) }

        // A probability outside 0…1.
        clues["fizz"] = 1.5
        rocks[0]["clues"] = clues
        json["rocks"] = rocks
        #expect(throws: CatalogError.self) { try RockCatalog(data: JSONSerialization.data(withJSONObject: json)) }

        // A link to an unknown rock.
        clues["fizz"] = 0.1
        rocks[0]["clues"] = clues
        rocks[0]["canBecome"] = ["unobtainium"]
        json["rocks"] = rocks
        #expect(throws: CatalogError.self) { try RockCatalog(data: JSONSerialization.data(withJSONObject: json)) }
    }

    @Test("Likelihood JSON round-trips")
    func likelihoodRoundTrip() throws {
        let original = Fixtures.rock("granite").clues
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClueLikelihoods.self, from: data)
        #expect(decoded == original)
    }
}
