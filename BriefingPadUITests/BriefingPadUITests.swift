import XCTest

final class BriefingPadUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMainSectionsExist() throws {
        let app = XCUIApplication()
        app.launch()

        // Check for Session Toolbar
        XCTAssertTrue(app.popUpButtons["SessionPicker"].exists)

        // Check for Part Header
        // Use a partial match or identifier if possible, but for now we expect Part 1 to be there
        XCTAssertTrue(app.staticTexts.containing(find: "Part 1").firstMatch.exists)

        // Check for Controls
        XCTAssertTrue(app.buttons["PreviousPartButton"].exists)
        XCTAssertTrue(app.buttons["NextPartButton"].exists)
        XCTAssertTrue(app.buttons["StartRecordingButton"].exists)
        XCTAssertTrue(app.buttons["FinishPartButton"].exists)

        // Check for Section Titles
        XCTAssertTrue(app.staticTexts["TranscriptSection"].exists)
        XCTAssertTrue(app.staticTexts["ObservationSection"].exists)
        XCTAssertTrue(app.staticTexts["PositiveCandidatesSection"].exists)
        XCTAssertTrue(app.staticTexts["AIMemoSection"].exists)
    }

    @MainActor
    func testNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        let nextButton = app.buttons["NextPartButton"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        XCTAssertTrue(nextButton.isEnabled)
        nextButton.click()

        // Verify that we moved to Part 2 (based on default data order)
        XCTAssertTrue(app.staticTexts.containing(find: "Part 4").firstMatch.exists)

        let prevButton = app.buttons["PreviousPartButton"]
        XCTAssertTrue(prevButton.isEnabled)
        prevButton.click()

        XCTAssertTrue(app.staticTexts.containing(find: "Part 1").firstMatch.exists)
    }
}
