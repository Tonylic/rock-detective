import CoreGraphics
import Foundation

/// One-stop entry point: photo in, evidence and ranked rocks out.
public struct RockIdentifier: Sendable {
    public let catalog: RockCatalog
    public let matcher: RockMatcher
    public let planner: QuestionPlanner
    public let analyzer: PhotoAnalyzer
    public let reference: ReferenceMatcher

    public init(
        catalog: RockCatalog,
        analyzer: PhotoAnalyzer = PhotoAnalyzer(),
        reference: ReferenceMatcher = ReferenceMatcher(samples: []),
        settings: RockMatcher.Settings = RockMatcher.Settings()
    ) {
        self.catalog = catalog
        self.matcher = RockMatcher(catalog: catalog, settings: settings)
        self.planner = QuestionPlanner(matcher: matcher)
        self.analyzer = analyzer
        self.reference = reference
    }

    /// Reads photo clues (and reference-picture votes, if a gallery is
    /// installed). Synchronous and CPU-bound: call it off the main actor.
    public func evidence(fromPhoto image: CGImage) -> Evidence {
        let photo = analyzer.analyze(image)
        var referenceEvidence: ReferenceEvidence?
        if !reference.isEmpty, let vector = try? FeaturePrinter.vector(for: image) {
            referenceEvidence = reference.evidence(for: vector, rockIDs: catalog.rocks.map(\.id))
        }
        return Evidence(answers: [:], photo: photo, reference: referenceEvidence)
    }

    public func result(for evidence: Evidence) -> MatchResult {
        matcher.match(evidence)
    }

    public func nextQuestion(for evidence: Evidence) -> ClueQuestion? {
        planner.nextQuestion(for: evidence)
    }
}
