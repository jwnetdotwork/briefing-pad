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
        let sessionPicker = app.popUpButtons["SessionPicker"]
        XCTAssertTrue(sessionPicker.waitForExistence(timeout: 5))

        // Check for Part Header
        // Use a partial match or identifier if possible, but for now we expect Part 1 to be there
        let partHeader = app.staticTexts.containing(find: "Part 1").firstMatch
        XCTAssertTrue(partHeader.waitForExistence(timeout: 5))

        // Check for Controls
        XCTAssertTrue(app.buttons["PreviousPartButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["NextPartButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["StartRecordingButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["FinishPartButton"].waitForExistence(timeout: 5))

        // Check for Section Titles
        XCTAssertTrue(app.staticTexts["TranscriptSection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ObservationSection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["PositiveCandidatesSection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["AIMemoSection"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify initial selection
        let part0 = app.buttons["PartButton-0"]
        XCTAssertTrue(part0.waitForExistence(timeout: 5))
        XCTAssertEqual(part0.value as? String, "Selected")

        let nextButton = app.buttons["NextPartButton"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        XCTAssertTrue(nextButton.isEnabled)
        nextButton.click()

        // Verify that selection moved to Part 1
        let part1 = app.buttons["PartButton-1"]
        let part1Selected = NSPredicate(format: "value == 'Selected'")
        expectation(for: part1Selected, evaluatedWith: part1, handler: nil)

        let part0Unselected = NSPredicate(format: "value == 'Unselected'")
        expectation(for: part0Unselected, evaluatedWith: part0, handler: nil)

        waitForExpectations(timeout: 5, handler: nil)

        let prevButton = app.buttons["PreviousPartButton"]
        XCTAssertTrue(prevButton.waitForExistence(timeout: 5))
        XCTAssertTrue(prevButton.isEnabled)
        prevButton.click()

        // Verify selection moved back to Part 0
        let part0Selected = NSPredicate(format: "value == 'Selected'")
        expectation(for: part0Selected, evaluatedWith: part0, handler: nil)

        let part1Unselected = NSPredicate(format: "value == 'Unselected'")
        expectation(for: part1Unselected, evaluatedWith: part1, handler: nil)

        waitForExpectations(timeout: 5, handler: nil)
    }
}
