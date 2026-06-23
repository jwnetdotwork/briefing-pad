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
        XCTAssertTrue(app.staticTexts["セッション選択"].exists || app.popUpButtons.firstMatch.exists)

        // Check for Part Header (at least one part title from dummy data)
        XCTAssertTrue(app.staticTexts["Part 1. 挨拶をする"].exists)

        // Check for Controls
        XCTAssertTrue(app.buttons["前へ"].exists)
        XCTAssertTrue(app.buttons["次へ"].exists)
        XCTAssertTrue(app.buttons["開始"].exists)
        XCTAssertTrue(app.buttons["パート終了"].exists)

        // Check for Section Titles
        XCTAssertTrue(app.staticTexts["文字起こし"].exists)
        XCTAssertTrue(app.staticTexts["学習ポイント"].exists)
        XCTAssertTrue(app.staticTexts["観察メモ"].exists)
        XCTAssertTrue(app.staticTexts["良かった点候補"].exists)
        XCTAssertTrue(app.staticTexts["🤖 AIメモ"].exists)
    }

    @MainActor
    func testNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        let nextButton = app.buttons["次へ"]
        XCTAssertTrue(nextButton.isEnabled)
        nextButton.click()

        XCTAssertTrue(app.staticTexts["Part 4. 会話を始める"].exists)

        let prevButton = app.buttons["前へ"]
        XCTAssertTrue(prevButton.isEnabled)
        prevButton.click()

        XCTAssertTrue(app.staticTexts["Part 1. 挨拶をする"].exists)
    }
}
