import XCTest

final class CutrUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateCutListAddPartsAndViewLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()

        // Open All Cut Lists; its empty state offers a button to create the first cut list.
        app.buttons["All Cut Lists"].firstMatch.tap()
        app.buttons["New Cut List"].firstMatch.tap()

        // Add two parts using "Save and Add Another".
        let addPart = app.buttons["Add Part"]
        XCTAssertTrue(addPart.waitForExistence(timeout: 5))
        addPart.tap()

        let name = app.textFields["Name (optional)"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Shelf")
        type(app.textFields["Length"], "1000")
        type(app.textFields["Width"], "300")
        app.buttons["Save and Add Another"].tap()

        app.textFields["Name (optional)"].tap()
        app.textFields["Name (optional)"].typeText("Side")
        type(app.textFields["Length"], "800")
        type(app.textFields["Width"], "400")
        app.buttons["Add"].tap()

        XCTAssertTrue(app.staticTexts["Shelf"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Side"].exists)

        // Open the layout and check one sheet is used.
        let viewLayout = app.buttons.containing(NSPredicate(format: "label CONTAINS 'View Cutting Layout'")).firstMatch
        if !viewLayout.isHittable { app.swipeUp() }
        XCTAssertTrue(viewLayout.waitForExistence(timeout: 5))
        viewLayout.tap()
        XCTAssertTrue(app.staticTexts["Sheet 1 of 1"].waitForExistence(timeout: 5))

        // Export menu offers PDF and print.
        app.buttons["Export"].tap()
        XCTAssertTrue(app.buttons["Export PDF"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Print"].exists)
    }

    @MainActor
    func testSortAndDuplicate() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        app.buttons["All Cut Lists"].firstMatch.tap()

        let first = app.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.staticTexts["Kitchen Base Units"].exists)

        app.buttons["Sort"].tap()
        app.buttons["Name"].tap()
        XCTAssertTrue(app.cells.firstMatch.staticTexts["Bird Box"].waitForExistence(timeout: 3))

        app.cells.firstMatch.press(forDuration: 1)
        app.buttons["Duplicate"].tap()
        XCTAssertTrue(app.staticTexts["Bird Box Copy"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCreateProjectAndAddCutList() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()

        app.buttons["New Project"].firstMatch.tap()
        let nameField = app.textFields["Name, e.g. Kitchen Renovation"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.typeText("Shed")
        app.buttons["Create"].tap()

        // Creating a project opens it; add a cut list inside it.
        XCTAssertTrue(app.navigationBars["Shed"].waitForExistence(timeout: 5))
        app.buttons["New Cut List"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Add Part"].waitForExistence(timeout: 5))

        // The cut list shows the project it belongs to.
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Shed'")).firstMatch.exists)
    }

    @MainActor
    func testShapeEditorPreset() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
        app.buttons["All Cut Lists"].firstMatch.tap()
        app.buttons["New Cut List"].firstMatch.tap()
        app.buttons["Add Part"].tap()

        type(app.textFields["Length"], "1000")
        type(app.textFields["Width"], "300")

        // Open the shape editor and apply the Pointed End preset.
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Rectangle'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Shape"].waitForExistence(timeout: 5))
        app.buttons["Shapes"].tap()
        app.buttons["Pointed End"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '5 points'")).firstMatch.waitForExistence(timeout: 3))

        // Switch tools to check they respond.
        app.buttons["Add Point"].tap()
        app.buttons["Move"].tap()

        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Custom Shape"].waitForExistence(timeout: 3))
        app.buttons["Add"].tap()

        // The part row marks the custom shape.
        XCTAssertTrue(app.images["Custom shape"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEditingExistingPartShapeIsSaved() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "part"]
        app.launch()

        // The demo opens the first part (Side panel) of Kitchen Base Units.
        XCTAssertTrue(app.navigationBars["Edit Part"].waitForExistence(timeout: 5))
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Rectangle'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Shapes"].tap()
        app.buttons["Chamfered Corners"].tap()
        app.buttons["Done"].tap()

        // Back in the part editor the new shape is kept, then saved.
        XCTAssertTrue(app.staticTexts["Custom Shape"].waitForExistence(timeout: 3))
        app.buttons["Save"].tap()

        // Reopen the part: the shape is still there.
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Side panel'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["Custom shape"].firstMatch.exists)
        row.tap()
        XCTAssertTrue(app.staticTexts["Custom Shape"].waitForExistence(timeout: 5))
    }

    private func type(_ field: XCUIElement, _ text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(text)
    }
}
