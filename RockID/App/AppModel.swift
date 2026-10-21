import CoreGraphics
import Foundation
import Observation
import RockKit

enum Route: Hashable {
    case identify
    case rock(String)
    case collection
    case rockBook
    case rockCycle
}

/// Options read from launch arguments. UI tests use a separate history folder
/// and can ask for a "practice rock" photo, because the simulator has no camera.
struct LaunchOptions {
    var isUITesting = false
    var resetHistory = false
    var practiceRockID: String?

    static var current: LaunchOptions {
        let arguments = ProcessInfo.processInfo.arguments
        var options = LaunchOptions()
        options.isUITesting = arguments.contains("-uiTesting")
        options.resetHistory = arguments.contains("-resetHistory")
        if let index = arguments.firstIndex(of: "-practiceRock"), arguments.indices.contains(index + 1) {
            options.practiceRockID = arguments[index + 1]
        }
        return options
    }
}

/// App-wide state: the rock catalog, the identifier, the saved collection,
/// navigation, and the identification in progress.
@MainActor
@Observable
final class AppModel {
    let catalog: RockCatalog
    let store: HistoryStore
    let launch: LaunchOptions
    private(set) var identifier: RockIdentifier

    var path: [Route] = []
    private(set) var activeSession: IdentificationSession?

    init(launch: LaunchOptions = .current) {
        self.launch = launch
        let catalog: RockCatalog
        do {
            catalog = try RockCatalog.bundled()
        } catch {
            // The catalog ships inside the app and is validated by the test suite.
            fatalError("Rock catalog failed to load: \(error)")
        }
        self.catalog = catalog
        self.identifier = RockIdentifier(catalog: catalog)

        var directory = HistoryStore.defaultDirectory()
        if launch.isUITesting {
            directory = directory.deletingLastPathComponent().appendingPathComponent("RockDetectiveUITests", isDirectory: true)
        }
        if launch.resetHistory {
            try? FileManager.default.removeItem(at: directory)
        }
        self.store = HistoryStore(directory: directory)
    }

    var practiceRock: Rock? {
        launch.practiceRockID.flatMap { catalog.rock(id: $0) }
    }

    /// Turns on picture matching if a reference gallery was bundled
    /// (`ReferenceSamples/<rockID>/*.jpg`). No gallery ships today.
    func loadReferenceGallery() async {
        guard let folder = Bundle.main.url(forResource: "ReferenceSamples", withExtension: nil) else { return }
        let rockIDs = Set(catalog.rocks.map(\.id))
        let samples = await Task.detached(priority: .utility) {
            ReferenceLibrary.samples(in: folder, knownRockIDs: rockIDs)
        }.value
        guard !samples.isEmpty else { return }
        identifier = RockIdentifier(catalog: catalog, reference: ReferenceMatcher(samples: samples))
    }

    func startIdentification(with image: CGImage) {
        let session = IdentificationSession(identifier: identifier, store: store)
        activeSession = session
        path.append(.identify)
        Task { await session.identify(image) }
    }

    func reopen(_ finding: Finding) {
        activeSession = IdentificationSession(restoring: finding, identifier: identifier, store: store)
        path.append(.identify)
    }

    func startPractice() {
        guard let rock = practiceRock,
              let image = RockArtRenderer.renderPracticePhoto(rock.art, size: 1200) else { return }
        startIdentification(with: image)
    }
}
