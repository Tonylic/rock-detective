import CoreGraphics
import Foundation
import Testing
@testable import RockKit

@MainActor
@Suite("Rock collection history")
struct HistoryStoreTests {
    func makeFinding(rock: String, answers: [ClueID: Answer] = [:], date: Date = Date()) -> Finding {
        var evidence = Evidence(answers: answers)
        evidence.photo = PhotoEvidence(beliefs: [.layers: [.yes: 0.7, .no: 0.3]])
        var result = Fixtures.matcher.match(evidence)
        if result.best.rockID != rock {
            // Force the requested best rock for bookkeeping tests.
            let others = result.candidates.filter { $0.rockID != rock }
            result = MatchResult(candidates: [Candidate(rockID: rock, probability: 0.7)] + others)
        }
        return Finding(date: date, result: result, evidence: evidence)
    }

    func photo() throws -> CGImage {
        try #require(TestImages.speckles(size: 2000))
    }

    @Test("HS-01 a saved find and its photo survive a reload")
    func saveAndReload() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = HistoryStore(directory: folder)
        let finding = makeFinding(rock: "granite", answers: [.fizz: .no, .color: .light])
        let stored = try store.add(finding, photo: photo())
        #expect(stored.photoFileName != nil)

        let reloaded = HistoryStore(directory: folder)
        #expect(reloaded.findings == [stored])
        let url = try #require(reloaded.photoURL(for: stored))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(reloaded.loadPhoto(for: stored) != nil)
        #expect(reloaded.findings.first?.evidence == stored.evidence)
    }

    @Test("HS-02 finds are listed newest first")
    func newestFirst() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(directory: folder)
        let old = makeFinding(rock: "basalt", date: Date(timeIntervalSince1970: 1_000))
        let new = makeFinding(rock: "slate", date: Date(timeIntervalSince1970: 2_000))
        let middle = makeFinding(rock: "chalk", date: Date(timeIntervalSince1970: 1_500))
        for finding in [old, new, middle] { try store.add(finding, photo: nil) }
        #expect(store.findings.map(\.bestRockID) == ["slate", "chalk", "basalt"])
        #expect(HistoryStore(directory: folder).findings.map(\.bestRockID) == ["slate", "chalk", "basalt"])
    }

    @Test("HS-03 updating a find persists new answers")
    func updatePersists() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(directory: folder)
        let stored = try store.add(makeFinding(rock: "granite"), photo: nil)

        let evidence = Evidence(answers: [.fizz: .yes, .fossils: .yes])
        let updated = stored.updated(result: Fixtures.matcher.match(evidence), evidence: evidence)
        try store.update(updated)

        let reloaded = HistoryStore(directory: folder)
        #expect(reloaded.findings.count == 1)
        #expect(reloaded.findings.first?.answers == [.fizz: .yes, .fossils: .yes])
        #expect(reloaded.findings.first?.bestRockID == "limestone")
        #expect(reloaded.findings.first?.ranking.count == 5)
    }

    @Test("HS-04 deleting a find removes its photo")
    func deleteRemovesPhoto() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(directory: folder)
        let keep = try store.add(makeFinding(rock: "basalt"), photo: photo())
        let remove = try store.add(makeFinding(rock: "granite"), photo: photo())
        let removedURL = try #require(store.photoURL(for: remove))

        try store.delete(id: remove.id)
        #expect(store.findings.map(\.id) == [keep.id])
        #expect(!FileManager.default.fileExists(atPath: removedURL.path))
        #expect(HistoryStore(directory: folder).findings.map(\.id) == [keep.id])
        // Deleting something unknown is harmless.
        try store.delete(id: UUID())
        #expect(store.findings.count == 1)
    }

    @Test("HS-05 a corrupt history file is set aside instead of crashing")
    func corruptFile() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ this is not json".utf8).write(to: folder.appendingPathComponent("history.json"))

        let store = HistoryStore(directory: folder)
        #expect(store.findings.isEmpty)
        #expect(store.lastError != nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.contains { $0.hasPrefix("history.corrupt-") })

        // The store keeps working afterwards.
        try store.add(makeFinding(rock: "slate"), photo: nil)
        #expect(HistoryStore(directory: folder).findings.count == 1)
    }

    @Test("HS-06 saved photos are downscaled")
    func photoDownscaled() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(directory: folder)
        let stored = try store.add(makeFinding(rock: "granite"), photo: photo())
        let url = try #require(store.photoURL(for: stored))
        let image = try ImageLoader.image(from: Data(contentsOf: url), maxPixelSize: 10_000)
        #expect(max(image.width, image.height) <= HistoryStore.maxPhotoPixelSize)
    }

    @Test("HS-07 discovered rock types are the unique best matches")
    func discovered() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(directory: folder)
        for rock in ["granite", "granite", "basalt"] {
            try store.add(makeFinding(rock: rock), photo: nil)
        }
        #expect(store.discoveredRockIDs == ["granite", "basalt"])
    }

    @Test("HS-08 delete all empties the collection and its photos")
    func deleteAll() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(directory: folder)
        try store.add(makeFinding(rock: "granite"), photo: photo())
        try store.add(makeFinding(rock: "basalt"), photo: photo())
        try store.deleteAll()
        #expect(store.findings.isEmpty)
        #expect(HistoryStore(directory: folder).findings.isEmpty)
        let photos = folder.appendingPathComponent("photos")
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: photos.path)) ?? []
        #expect(remaining.isEmpty)
    }

    @Test("A missing history folder starts empty")
    func missingFolder() {
        let store = HistoryStore(directory: Fixtures.temporaryDirectory())
        #expect(store.findings.isEmpty)
        #expect(store.lastError == nil)
    }
}
