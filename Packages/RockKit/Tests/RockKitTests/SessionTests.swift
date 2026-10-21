import CoreGraphics
import Foundation
import Testing
@testable import RockKit

@MainActor
@Suite("Identification session")
struct SessionTests {
    func practicePhoto(_ rockID: String) throws -> CGImage {
        try #require(RockArtRenderer.renderPracticePhoto(Fixtures.rock(rockID).art, size: 800))
    }

    @Test("SS-01 identifying a photo gives a result, a next question, and a saved find")
    func identify() async throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(directory: folder)
        let session = IdentificationSession(identifier: Fixtures.identifier, store: store)
        #expect(session.phase == .idle)

        await session.identify(try practicePhoto("basalt"))

        #expect(session.phase == .ready)
        #expect(session.photo != nil)
        #expect(session.evidence.photo?.isEmpty == false)
        #expect(session.bestRock != nil)
        #expect(session.alternatives.count == 2)
        #expect(session.nextQuestion != nil)
        #expect(store.findings.count == 1)
        #expect(store.findings.first?.id == session.findingID)
        #expect(store.findings.first?.photoFileName != nil)
        let duration = try #require(session.analysisDuration)
        #expect(duration < .seconds(2))
    }

    @Test("SS-02 answering a clue updates the result and the saved find")
    func answerUpdates() async throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(directory: folder)
        let session = IdentificationSession(identifier: Fixtures.identifier, store: store)
        await session.identify(try practicePhoto("limestone"))

        session.answer(.yes, to: .fizz)
        session.answer(.yes, to: .fossils)
        session.answer(.no, to: .marks)

        #expect(session.result.best.rockID == "limestone")
        #expect(session.answeredClues.map(\.question.id) == [.fizz, .marks, .fossils])
        #expect(store.findings.count == 1)
        #expect(store.findings.first?.bestRockID == "limestone")
        #expect(store.findings.first?.answers[.fizz] == .yes)
        #expect(HistoryStore(directory: folder).findings.first?.answers.count == 3)
    }

    @Test("SS-03 changing an answer to 'not sure' restores the earlier ranking")
    func notSureRestores() async throws {
        let session = IdentificationSession(identifier: Fixtures.identifier, store: nil)
        await session.identify(try practicePhoto("granite"))
        let before = session.result

        session.answer(.yes, to: .fizz)
        #expect(session.result != before)
        session.answer(.notSure, to: .fizz)
        #expect(session.result == before)
        session.clearAnswer(for: .fizz)
        #expect(session.result == before)
        #expect(session.answeredClues.isEmpty)
    }

    @Test("SS-04 a saved find can be reopened with the same ranking")
    func restore() async throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(directory: folder)
        let session = IdentificationSession(identifier: Fixtures.identifier, store: store)
        await session.identify(try practicePhoto("gneiss"))
        session.answer(.yes, to: .layers)

        let saved = try #require(HistoryStore(directory: folder).findings.first)
        let reopened = IdentificationSession(restoring: saved, identifier: Fixtures.identifier, store: store)
        #expect(reopened.phase == .ready)
        #expect(reopened.result == session.result)
        #expect(reopened.evidence.answers == session.evidence.answers)
        #expect(reopened.photo != nil)

        reopened.answer(.no, to: .sheets)
        #expect(store.findings.count == 1)
        #expect(store.findings.first?.answers[.sheets] == .no)
    }

    @Test("Follow-up answers are dropped when their prerequisite changes")
    func prunesFollowUps() async throws {
        let session = IdentificationSession(identifier: Fixtures.identifier, store: nil)
        await session.identify(try practicePhoto("conglomerate"))
        session.answer(.yes, to: .pebbles)
        #expect(session.nextQuestion?.id == .roundPebbles)
        session.answer(.yes, to: .roundPebbles)
        #expect(session.result.best.rockID == "conglomerate")

        session.answer(.no, to: .pebbles)
        #expect(session.evidence.answers[.roundPebbles] == nil)
    }
}
