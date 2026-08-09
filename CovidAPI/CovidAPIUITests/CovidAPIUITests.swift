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

    func testSortsListByAlertSeverity() {
        let firstCell = app.cells["epidemic.cell.0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))

        app.buttons["epidemic.favorites.filter"].tap()
        app.buttons["依疫情等級"].tap()

        XCTAssertTrue(firstCell.label.contains("美國-沙門氏菌感染症"))
        app.buttons["epidemic.favorites.filter"].tap()
        XCTAssertTrue(app.buttons["依疫情等級"].isSelected)
    }

    func testResetsListViewOptions() {
        let firstCell = app.cells["epidemic.cell.0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))

        app.buttons["epidemic.favorites.filter"].tap()
        app.buttons["依疫情等級"].tap()
        app.segmentedControls["epidemic.filter"].buttons["三級"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS '美國-沙門氏菌感染症'")
            ).firstMatch.waitForExistence(timeout: 2)
        )

        app.buttons["epidemic.favorites.filter"].tap()
        let reset = app.buttons["重設檢視條件"]
        XCTAssertTrue(reset.waitForExistence(timeout: 2))
        reset.tap()

        XCTAssertTrue(firstCell.label.contains("日本-腸病毒"))
        XCTAssertTrue(app.segmentedControls["epidemic.filter"].buttons["全部"].isSelected)
        app.buttons["epidemic.favorites.filter"].tap()
        XCTAssertTrue(app.buttons["依發布時間"].isSelected)
    }

    func testResetsOptionsFromEmptyState() {
        let firstCell = app.cells["epidemic.cell.0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        let search = app.searchFields["epidemic.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            search.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        }
        search.typeText("不存在的疫情")
        let reset = app.buttons["epidemic.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 2))
        reset.tap()
        XCTAssertTrue(firstCell.waitForExistence(timeout: 2))
        XCTAssertTrue(firstCell.label.contains("日本-腸病毒"))
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

    func testShowsListEpidemicOnMap() {
        let firstCell = app.cells["epidemic.cell.0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        app.buttons["epidemic.detail.showOnMap"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["epidemic.map"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["epidemic.map.marker.日本"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["epidemic.map.callout.level"].waitForExistence(timeout: 2))
    }

    func testShowsAllMarkersAfterFocusingDetail() {
        let firstCell = app.cells["epidemic.cell.0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["epidemic.detail.showOnMap"].tap()

        let japanMarker = app.descendants(matching: .any)["epidemic.map.marker.日本"]
        XCTAssertTrue(japanMarker.waitForExistence(timeout: 5))
        app.buttons["epidemic.map.showAll"].tap()

        let usaMarker = app.descendants(matching: .any)["epidemic.map.marker.美國"]
        XCTAssertTrue(usaMarker.waitForExistence(timeout: 5))
    }

    func testOpensEpidemicFromNotificationRoute() {
        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-notification",
            "日本-腸病毒|1700000000.0"
        ]
        app.launch()

        XCTAssertTrue(app.tables["epidemic.detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["日本-腸病毒"].exists)
        XCTAssertTrue(app.staticTexts["epidemic.detail.description"].exists)
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

    func testResetsMapViewOptions() {
        app.tabBars.buttons["地圖"].tap()
        let japanMarker = app.descendants(matching: .any)["epidemic.map.marker.日本"]
        XCTAssertTrue(japanMarker.waitForExistence(timeout: 5))

        app.buttons["三級"].tap()
        XCTAssertFalse(japanMarker.waitForExistence(timeout: 2))
        app.buttons["epidemic.map.favorites"].tap()
        let reset = app.buttons["重設檢視條件"]
        XCTAssertTrue(reset.waitForExistence(timeout: 2))
        reset.tap()

        XCTAssertTrue(japanMarker.waitForExistence(timeout: 5))
    }

    func testFiltersMapToFavoriteLocations() {
        let firstCell = app.cells["epidemic.cell.0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        firstCell.tap()
        app.buttons["收藏地區"].tap()
        app.tabBars.buttons["地圖"].tap()

        let japanMarker = app.descendants(matching: .any)["epidemic.map.marker.日本"]
        XCTAssertTrue(japanMarker.waitForExistence(timeout: 5))

        app.buttons["epidemic.map.favorites"].tap()
        app.buttons["只顯示收藏地區"].tap()

        XCTAssertTrue(japanMarker.waitForExistence(timeout: 2))
        app.buttons["三級"].tap()
        let emptyStatus = app.staticTexts["epidemic.map.status"]
        XCTAssertTrue(emptyStatus.waitForExistence(timeout: 2))
        XCTAssertEqual(emptyStatus.label, "沒有符合此等級的收藏地區疫情")
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

    func testShowsCachedDataSourceOnMapWhenOffline() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-offline"]
        app.launch()
        app.tabBars.buttons["地圖"].tap()

        let source = app.staticTexts["epidemic.map.source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(source.label.contains("離線資料"))
        XCTAssertTrue(source.label.contains("更新於"))
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

    func testOffersSettingsWhenNotificationPermissionIsDenied() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-notification-denied"]
        app.launch()

        let toggle = app.buttons["epidemic.notifications.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()

        XCTAssertTrue(app.alerts["無法開啟通知"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.alerts.buttons["前往設定"].exists)
        XCTAssertTrue(app.alerts.buttons["取消"].exists)
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
