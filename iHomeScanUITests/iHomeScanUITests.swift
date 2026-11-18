import XCTest

final class iHomeScanUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--precision-tap-ui-test", "--reset-precision-ui-test"]
        app.launch()
        if !app.staticTexts["precision.fixture.label"].waitForExistence(timeout: 5) {
            // Simulator UI automation can occasionally lose the first launch while the previous
            // test runner is being torn down. Relaunch once before treating it as a product failure.
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(app.staticTexts["precision.fixture.label"].waitForExistence(timeout: 8))
    }

    func testWallAndDimensionTapsOpenInlineEditorAndPersist() throws {
        let canvas = app.otherElements["precision.floorPlanCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 3))

        // Top wall in the deterministic 4 m × 3 m fixture.
        let title = app.descendants(matching: .any)["precision.inline.title"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.39)).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3), "Wall tap must open the inline measurement panel")
        XCTAssertTrue(app.descendants(matching: .any)["precision.inline.current"].label.contains("4000"))

        app.buttons["precision.inline.close"].tap()
        XCTAssertFalse(title.waitForExistence(timeout: 1))

        // Dimension annotation is laid out immediately above the same top wall.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.368)).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3), "Dimension label tap must select its associated wall")
        XCTAssertTrue(app.descendants(matching: .any)["precision.inline.current"].label.contains("4000"))

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
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.39)).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["precision.inline.current"].label.contains("4250"))
    }

    func testDoorTapEditsRealOpeningAndPersists() throws {
        let canvas = app.otherElements["precision.floorPlanCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 3))

        // Door occupies the left portion of the deterministic top host wall.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.34, dy: 0.39)).tap()
        let title = app.descendants(matching: .any)["precision.opening.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3), "Door tap must open the opening measurement panel")

        let offset = app.textFields["precision.opening.offset"]
        XCTAssertTrue(offset.waitForExistence(timeout: 2))
        offset.tap()
        offset.press(forDuration: 1.0)
        app.menuItems["Select All"].tap()
        offset.typeText("700")
        app.buttons["precision.opening.confirm"].tap()
        XCTAssertFalse(title.waitForExistence(timeout: 3))

        app.terminate()
        app.launchArguments = ["--precision-tap-ui-test"]
        app.launch()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.39)).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["precision.opening.offset"].value as? String, "700")
    }

    func testDoorWidthOnlyConfirmsWithoutEditingOptionalHeight() throws {
        let canvas = app.otherElements["precision.floorPlanCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 3))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.34, dy: 0.39)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["precision.opening.title"].waitForExistence(timeout: 3))

        let width = app.textFields["precision.opening.width"]
        XCTAssertTrue(width.waitForExistence(timeout: 2))
        width.tap()
        width.press(forDuration: 1.0)
        app.menuItems["Select All"].tap()
        width.typeText("950")

        let confirm = app.buttons["precision.opening.confirm"]
        XCTAssertTrue(confirm.isEnabled, "Unchanged optional dimensions must not block width-only confirmation")
        confirm.tap()
        XCTAssertFalse(app.descendants(matching: .any)["precision.opening.title"].waitForExistence(timeout: 3))
    }

    func testAddColumnRendersAndPersistsAfterReopen() throws {
        let canvas = app.otherElements["precision.floorPlanCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 3))

        app.buttons["structural.add.button"].tap()
        XCTAssertTrue(app.buttons["structural.add.column"].waitForExistence(timeout: 3))
        app.buttons["structural.add.column"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["structural.placement.hint"].waitForExistence(timeout: 3))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.58)).tap()

        replaceText(in: app.textFields["structural.width"], with: "300")
        replaceText(in: app.textFields["structural.depth"], with: "400")
        app.buttons["structural.confirm"].tap()
        XCTAssertTrue(structuralElement(prefix: "precision.column.").waitForExistence(timeout: 3))

        app.terminate()
        app.launchArguments = ["--precision-tap-ui-test"]
        app.launch()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertTrue(structuralElement(prefix: "precision.column.").waitForExistence(timeout: 3))
    }

    func testAddBeamRendersAndPersistsAfterReopen() throws {
        let canvas = app.otherElements["precision.floorPlanCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 3))

        app.buttons["structural.add.button"].tap()
        XCTAssertTrue(app.buttons["structural.add.beam"].waitForExistence(timeout: 3))
        app.buttons["structural.add.beam"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.58)).tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.58)).tap()

        replaceText(in: app.textFields["structural.width"], with: "250")
        replaceText(in: app.textFields["structural.depth"], with: "400")
        app.buttons["structural.confirm"].tap()
        XCTAssertTrue(structuralElement(prefix: "precision.beam.").waitForExistence(timeout: 3))

        app.terminate()
        app.launchArguments = ["--precision-tap-ui-test"]
        app.launch()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertTrue(structuralElement(prefix: "precision.beam.").waitForExistence(timeout: 3))
    }

    private func replaceText(in field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        if let current = field.value as? String, !current.isEmpty, current != "0" {
            field.press(forDuration: 1)
            if app.menuItems["Select All"].waitForExistence(timeout: 1) {
                app.menuItems["Select All"].tap()
            }
        }
        field.typeText(value)
    }

    private func structuralElement(prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .firstMatch
    }
}
