import XCTest

final class iHomeScanUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--precision-tap-ui-test", "--reset-precision-ui-test"]
        app.launch()
        XCTAssertTrue(app.staticTexts["precision.fixture.label"].waitForExistence(timeout: 5))
    }

    func testWallAndDimensionTapsOpenInlineEditorAndPersist() throws {
        let canvas = app.otherElements["precision.floorPlanCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 3))

        // Top wall in the deterministic 4 m × 3 m fixture.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.35)).tap()
        let title = app.staticTexts["precision.inline.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3), "Wall tap must open the inline measurement panel")
        XCTAssertTrue(app.staticTexts["precision.inline.current"].label.contains("4000"))

        app.buttons["precision.inline.close"].tap()
        XCTAssertFalse(title.waitForExistence(timeout: 1))

        // Dimension annotation is laid out immediately above the same top wall.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.375)).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3), "Dimension label tap must select its associated wall")
        XCTAssertTrue(app.staticTexts["precision.inline.current"].label.contains("4000"))

        let input = app.textFields["precision.inline.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        input.tap()
        input.press(forDuration: 1.0)
        app.menuItems["Select All"].tap()
        input.typeText("4250")
        app.buttons["precision.inline.confirm"].tap()
        XCTAssertFalse(title.waitForExistence(timeout: 3))

        app.terminate()
        app.launchArguments = ["--precision-tap-ui-test"]
        app.launch()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.35)).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["precision.inline.current"].label.contains("4250"))
    }
}
