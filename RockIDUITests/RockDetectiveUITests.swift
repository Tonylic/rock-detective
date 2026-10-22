import XCTest

/// End-to-end flows on the iPad simulator. The simulator has no camera, so the
/// app is launched with `-practiceRock <id>`, which adds a button that feeds a
/// procedurally drawn "photo" of that rock through the real identification flow.
final class RockDetectiveUITests: XCTestCase {
    private let timeout: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(reset: Bool, practiceRock: String = "gneiss") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-practiceRock", practiceRock]
        if reset { app.launchArguments.append("-resetHistory") }
        app.launch()
        return app
    }

    @MainActor
    private func identifyPracticeRock(in app: XCUIApplication) {
        let practice = app.buttons["practiceRockButton"]
        XCTAssertTrue(practice.waitForExistence(timeout: timeout))
        practice.tap()
        // Every photo goes through "Frame your rock" first.
        let use = app.buttons["useCropButton"]
        XCTAssertTrue(use.waitForExistence(timeout: timeout), "The crop screen did not appear")
        use.tap()
        XCTAssertTrue(app.staticTexts["bestMatchName"].waitForExistence(timeout: timeout), "No result appeared")
    }

    @MainActor
    private func goHome(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        while back.exists && back.isHittable {
            back.tap()
            if app.staticTexts["appTitle"].waitForExistence(timeout: 2) { return }
        }
    }

    /// UI-01
    @MainActor
    func testHomeShowsMainActions() {
        let app = launch(reset: true)
        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["choosePhotoButton"].exists)
        XCTAssertTrue(app.buttons["myRocksButton"].exists)
        XCTAssertTrue(app.buttons["rockBookButton"].exists)
    }

    /// UI-02, UI-03, UI-04, UI-05, UI-07
    @MainActor
    func testIdentifyAnswerSaveAndPersist() {
        var app = launch(reset: true)

        // UI-02: photo → result with look-alikes.
        identifyPracticeRock(in: app)
        XCTAssertFalse(app.staticTexts["bestMatchName"].label.isEmpty)
        XCTAssertTrue(app.otherElements["couldAlsoBe"].exists || app.staticTexts["Could also be…"].exists)

        // UI-03: answer a detective clue; it shows up under "Your clues".
        XCTAssertTrue(app.staticTexts["cluePrompt"].waitForExistence(timeout: timeout), "The clue question is not reachable")
        let yes = app.buttons["answer_yes"]
        let light = app.buttons["answer_light"]
        let answer = yes.waitForExistence(timeout: timeout) ? yes : light
        XCTAssertTrue(answer.waitForExistence(timeout: timeout), "No clue question was offered")
        answer.tap()
        XCTAssertTrue(app.staticTexts["Your clues"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["bestMatchName"].exists)

        // UI-04: the find is in My Rocks.
        goHome(app)
        app.buttons["myRocksButton"].tap()
        let finding = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'finding_'")).firstMatch
        XCTAssertTrue(finding.waitForExistence(timeout: timeout))

        // UI-05: it survives a relaunch.
        app.terminate()
        app = launch(reset: false)
        XCTAssertTrue(app.buttons["myRocksButton"].waitForExistence(timeout: timeout))
        app.buttons["myRocksButton"].tap()
        let persisted = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'finding_'")).firstMatch
        XCTAssertTrue(persisted.waitForExistence(timeout: timeout), "The find was not saved across launches")

        // UI-07: delete it.
        app.buttons["editCollectionButton"].tap()
        let delete = app.buttons["deleteFindingButton"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: timeout))
        delete.tap()
        let remove = app.alerts.buttons["Remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: timeout))
        remove.tap()
        XCTAssertTrue(app.descendants(matching: .any)["emptyCollection"].waitForExistence(timeout: timeout))
    }

    /// UI-06
    @MainActor
    func testRockBookShowsGranite() {
        let app = launch(reset: true)
        XCTAssertTrue(app.buttons["rockBookButton"].waitForExistence(timeout: timeout))
        app.buttons["rockBookButton"].tap()

        let granite = app.descendants(matching: .any)["rockCard_granite"]
        XCTAssertTrue(granite.waitForExistence(timeout: timeout))
        granite.tap()

        XCTAssertTrue(app.staticTexts["rockDetailName"].waitForExistence(timeout: timeout))
        XCTAssertEqual(app.staticTexts["rockDetailName"].label, "Granite")
        XCTAssertTrue(app.staticTexts["🌋 Igneous"].exists || app.descendants(matching: .any)["rockFamily"].exists)
        let hardness = app.staticTexts["hardnessText"]
        for _ in 0..<4 where !hardness.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(hardness.exists)
        XCTAssertTrue(hardness.label.contains("6"))
    }

    /// UI-08: framing the photo — cancel saves nothing; zooming really crops
    /// the photo that gets identified; zoom out returns to 100%.
    @MainActor
    func testFrameYourRock() {
        let app = launch(reset: true, practiceRock: "granite")
        let practice = app.buttons["practiceRockButton"]
        XCTAssertTrue(practice.waitForExistence(timeout: timeout))

        // Cancel: back home, nothing saved.
        practice.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cropView"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Frame your rock 🎯"].exists)
        app.buttons["cancelCropButton"].tap()
        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: timeout))
        app.buttons["myRocksButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["emptyCollection"].waitForExistence(timeout: timeout))
        goHome(app)

        practice.tap()
        let area = app.descendants(matching: .any)["cropArea"]
        XCTAssertTrue(area.waitForExistence(timeout: timeout))
        // Let the rock finder settle so it can't change the framing mid-test.
        let settled = NSPredicate(format: "label != %@", "Looking for your rock…")
        expectation(for: settled, evaluatedWith: app.staticTexts["cropHint"])
        waitForExpectations(timeout: timeout)

        // Zoom out resets to 100%.
        app.buttons["zoomOutButton"].tap()
        let full = NSPredicate(format: "value == %@", "Zoom 100 percent")
        expectation(for: full, evaluatedWith: area)
        waitForExpectations(timeout: timeout)

        // Pinch to zoom in, then use the photo: the identified photo must be the
        // smaller cropped square, not the whole 1200 × 1200 practice photo.
        area.pinch(withScale: 2.5, velocity: 2)
        XCTAssertNotEqual(area.value as? String, "Zoom 100 percent", "Pinching did not zoom")
        app.buttons["useCropButton"].tap()
        XCTAssertTrue(app.staticTexts["bestMatchName"].waitForExistence(timeout: timeout))
        let resultPhoto = app.descendants(matching: .any)["resultPhoto"]
        XCTAssertTrue(resultPhoto.waitForExistence(timeout: timeout))
        let size = (resultPhoto.value as? String ?? "").split(separator: " ").compactMap { Int($0) }
        XCTAssertEqual(size.count, 2, "Unexpected photo description: \(String(describing: resultPhoto.value))")
        if size.count == 2 {
            XCTAssertEqual(size[0], size[1], "The crop should be square")
            XCTAssertLessThan(size[0], 1000, "The photo was not cropped")
        }
    }

    /// Learning flow: from a result into the rock's page and the rock cycle.
    @MainActor
    func testLearnMoreFromResult() {
        let app = launch(reset: true, practiceRock: "obsidian")
        identifyPracticeRock(in: app)
        let learnMore = app.buttons["learnMoreButton"]
        XCTAssertTrue(learnMore.waitForExistence(timeout: timeout))
        learnMore.tap()
        XCTAssertTrue(app.staticTexts["rockDetailName"].waitForExistence(timeout: timeout))
    }
}
