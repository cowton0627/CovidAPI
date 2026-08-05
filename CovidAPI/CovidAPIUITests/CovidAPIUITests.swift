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

    func testSharesEpidemicFromDetail() {
        let firstCell = app.cells["epidemic.cell.0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        firstCell.tap()

        app.buttons["epidemic.share"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5))
    }

    func testSwitchesToMap() {
        app.tabBars.buttons["地圖"].tap()
        let map = app.descendants(matching: .any)["epidemic.map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
    }

    func testOpensMapMarkerCalloutAndDetail() {
        app.tabBars.buttons["地圖"].tap()

        let marker = app.descendants(matching: .any)["epidemic.map.marker.日本"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        marker.tap()

        XCTAssertTrue(app.staticTexts["epidemic.map.callout.level"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["epidemic.map.callout.date"].exists)
        XCTAssertTrue(app.staticTexts["epidemic.map.callout.description"].exists)

        app.buttons["epidemic.map.callout.detail"].tap()
        XCTAssertTrue(app.tables["epidemic.detail"].waitForExistence(timeout: 2))
    }

    func testFiltersMapByAlertLevel() {
        app.tabBars.buttons["地圖"].tap()
        let marker = app.descendants(matching: .any)["epidemic.map.marker.日本"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5))

        let unknownFilter = app.buttons["未分級"]
        XCTAssertTrue(unknownFilter.waitForExistence(timeout: 2))
        unknownFilter.tap()
        XCTAssertTrue(marker.waitForExistence(timeout: 2))

        app.buttons["三級"].tap()
        XCTAssertFalse(marker.waitForExistence(timeout: 2))
    }

    func testShowsCachedDataWhenOffline() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-offline"]
        app.launch()

        XCTAssertTrue(app.cells["epidemic.cell.0"].waitForExistence(timeout: 5))
        let footer = app.staticTexts["epidemic.updatedAt"]
        XCTAssertTrue(footer.waitForExistence(timeout: 2))
        XCTAssertTrue(footer.label.contains("離線資料"))
    }

    func testFavoritesLocationFromDetail() {
        let firstCell = app.cells["epidemic.cell.0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        firstCell.tap()

        app.buttons["收藏地區"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["epidemic.favorites.filter"].tap()
        app.buttons["只顯示收藏地區"].tap()

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '日本-腸病毒'")).firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '美國-沙門氏菌'")).firstMatch.exists)
    }

    func testManagesFavoriteLocations() {
        let firstCell = app.cells["epidemic.cell.0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        firstCell.tap()
        app.buttons["收藏地區"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["epidemic.favorites.filter"].tap()
        app.buttons["管理收藏地區"].tap()

        let favorite = app.cells["epidemic.favorite.location.日本"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 2))
        favorite.swipeLeft()
        app.buttons["移除 日本 收藏"].tap()
        XCTAssertTrue(app.staticTexts["epidemic.favorites.empty"].waitForExistence(timeout: 2))
    }

    func testNotificationOptInControlExists() {
        XCTAssertTrue(
            app.buttons["epidemic.notifications.toggle"].waitForExistence(timeout: 5)
        )
    }

    func testEnablesNotificationsAfterSystemPermissionIsGranted() {
        addUIInterruptionMonitor(withDescription: "通知權限") { alert in
            let allowButton = alert.buttons["Allow"]
            if allowButton.exists {
                allowButton.tap()
            } else if alert.buttons["允許"].exists {
                alert.buttons["允許"].tap()
            } else if alert.buttons.count > 0 {
                alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
            } else {
                return false
            }
            return true
        }

        let toggle = app.buttons["epidemic.notifications.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.label == "關閉收藏地區新疫情通知" {
            toggle.tap()
        }
        toggle.tap()
        app.tap()

        let enabledToggle = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label == %@", "epidemic.notifications.toggle", "關閉收藏地區新疫情通知")
        ).firstMatch
        XCTAssertTrue(enabledToggle.waitForExistence(timeout: 5))
    }
}
