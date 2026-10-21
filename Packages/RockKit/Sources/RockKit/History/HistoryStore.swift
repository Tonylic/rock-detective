import CoreGraphics
import Foundation
import Observation

/// One saved identification in a kid's rock collection.
public struct Finding: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var date: Date
    public var photoFileName: String?
    public var bestRockID: String
    public var confidence: Double
    /// Top candidates, best first.
    public var ranking: [Candidate]
    public var answers: [ClueID: Answer]
    public var photoEvidence: PhotoEvidence?
    public var referenceEvidence: ReferenceEvidence?
    public var nickname: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        photoFileName: String? = nil,
        result: MatchResult,
        evidence: Evidence,
        nickname: String? = nil
    ) {
        self.id = id
        self.date = date
        self.photoFileName = photoFileName
        self.bestRockID = result.best.rockID
        self.confidence = result.confidence
        self.ranking = result.top(Finding.rankingLength)
        self.answers = evidence.answers
        self.photoEvidence = evidence.photo
        self.referenceEvidence = evidence.reference
        self.nickname = nickname
    }

    static let rankingLength = 5

    public var evidence: Evidence {
        Evidence(answers: answers, photo: photoEvidence, reference: referenceEvidence)
    }

    public var level: ConfidenceLevel { ConfidenceLevel(probability: confidence) }

    /// Returns a copy updated with a new result and evidence.
    public func updated(result: MatchResult, evidence: Evidence) -> Finding {
        var copy = self
        copy.bestRockID = result.best.rockID
        copy.confidence = result.confidence
        copy.ranking = result.top(Finding.rankingLength)
        copy.answers = evidence.answers
        copy.photoEvidence = evidence.photo
        copy.referenceEvidence = evidence.reference
        return copy
    }
}

/// Persists the rock collection as `history.json` plus one JPEG per find.
@MainActor
@Observable
public final class HistoryStore {
    public private(set) var findings: [Finding] = []
    /// Set when the last load or save failed; the UI can show a gentle message.
    public private(set) var lastError: String?

    public let directory: URL
    private let fileManager = FileManager.default

    public static let maxPhotoPixelSize = 1024

    private var historyURL: URL { directory.appendingPathComponent("history.json") }
    private var photosURL: URL { directory.appendingPathComponent("photos", isDirectory: true) }

    public init(directory: URL) {
        self.directory = directory
        load()
    }

    /// `Application Support/RockDetective`.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("RockDetective", isDirectory: true)
    }

    public var discoveredRockIDs: Set<String> {
        Set(findings.map(\.bestRockID))
    }

    public func finding(id: UUID) -> Finding? {
        findings.first { $0.id == id }
    }

    // MARK: - Loading

    public func load() {
        guard fileManager.fileExists(atPath: historyURL.path) else {
            findings = []
            return
        }
        do {
            let data = try Data(contentsOf: historyURL)
            findings = try Self.decoder.decode([Finding].self, from: data).sorted { $0.date > $1.date }
            lastError = nil
        } catch {
            // Keep the unreadable file for debugging, and start fresh instead of crashing.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = directory.appendingPathComponent("history.corrupt-\(stamp).json")
            try? fileManager.moveItem(at: historyURL, to: backup)
            findings = []
            lastError = "Your old rock list couldn't be read, so we started a fresh one."
        }
    }

    // MARK: - Changes

    /// Saves a new find (and its photo). Returns the stored finding.
    @discardableResult
    public func add(_ finding: Finding, photo: CGImage?) throws -> Finding {
        var stored = finding
        if let photo {
            try ensureDirectories()
            let fileName = "\(finding.id.uuidString).jpg"
            let data = try ImageLoader.jpegData(from: photo, maxPixelSize: Self.maxPhotoPixelSize)
            try data.write(to: photosURL.appendingPathComponent(fileName), options: .atomic)
            stored.photoFileName = fileName
        }
        findings.removeAll { $0.id == stored.id }
        findings.append(stored)
        findings.sort { $0.date > $1.date }
        try save()
        return stored
    }

    public func update(_ finding: Finding) throws {
        guard let index = findings.firstIndex(where: { $0.id == finding.id }) else { return }
        findings[index] = finding
        try save()
    }

    public func delete(id: UUID) throws {
        guard let index = findings.firstIndex(where: { $0.id == id }) else { return }
        let removed = findings.remove(at: index)
        if let url = photoURL(for: removed) {
            try? fileManager.removeItem(at: url)
        }
        try save()
    }

    public func deleteAll() throws {
        findings = []
        try? fileManager.removeItem(at: photosURL)
        try save()
    }

    // MARK: - Photos

    public func photoURL(for finding: Finding) -> URL? {
        finding.photoFileName.map { photosURL.appendingPathComponent($0) }
    }

    public func loadPhoto(for finding: Finding, maxPixelSize: Int = HistoryStore.maxPhotoPixelSize) -> CGImage? {
        guard let url = photoURL(for: finding), let data = try? Data(contentsOf: url) else { return nil }
        return try? ImageLoader.image(from: data, maxPixelSize: maxPixelSize)
    }

    // MARK: - Files

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: photosURL, withIntermediateDirectories: true)
    }

    private func save() throws {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(findings)
            try data.write(to: historyURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Your rock list couldn't be saved."
            throw error
        }
    }

    private static var encoder: JSONEncoder {
        // Dates use the default (exact) encoding so they round-trip unchanged.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        JSONDecoder()
    }
}
