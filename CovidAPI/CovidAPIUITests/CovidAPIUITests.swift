import XCTest

final class CovidAPIUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    func testSearchAndLevelFilter() {
        let firstCell = app.cells["epidemic.cell.0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))

        let search = app.searchFields["epidemic.search"]
        search.tap()
        search.typeText("日本")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '日本-腸病毒'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '美國-沙門氏菌'")).firstMatch.exists)

        app.buttons["Cancel"].tap()
        app.segmentedControls["epidemic.filter"].buttons["三級"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '美國-沙門氏菌'")).firstMatch.waitForExistence(timeout: 2))

        app.segmentedControls["epidemic.filter"].buttons["未分級"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '日本-腸病毒'")).firstMatch.waitForExistence(timeout: 2))
    }

    func testOpensDetailFromList() {
        let firstCell = app.cells["epidemic.cell.0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        firstCell.tap()
        XCTAssertTrue(app.tables["epidemic.detail"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["epidemic.detail.description"].exists)
    }

    func testSwitchesToMap() {
        app.tabBars.buttons["地圖"].tap()
        let map = app.descendants(matching: .any)["epidemic.map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
    }
}
