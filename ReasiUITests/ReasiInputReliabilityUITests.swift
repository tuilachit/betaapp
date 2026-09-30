import XCTest

final class ReasiInputReliabilityUITests: XCTestCase {
    @MainActor
    func testListPhotoReviewKeepsUncertainItemsEditableAndAddsOnlySelectedRows() throws {
        continueAfterFailure = false
        let app = launchFixtureApp(arguments: ["-ReasiListPhotoReviewFixture"])
        XCTAssertTrue(app.navigationBars["Your list"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Check spelling"].exists)
        let add = app.buttons["list-photo-add-items"]
        XCTAssertEqual(add.label, "Add 3 items")
        XCTAssertTrue(add.isEnabled, "Unmatched and partially read items must remain addable")

        app.buttons["Include Coriander"].tap()
        XCTAssertEqual(add.label, "Add 2 items")

        let quantity = app.textFields["Quantity for chicken thing"]
        XCTAssertTrue(quantity.exists)
        quantity.tap()
        quantity.typeText("500 g")
        app.buttons["Done"].tap()
        add.tap()

        XCTAssertTrue(app.navigationBars["Your list"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Shopping list"].exists)
        let chicken = app.buttons["Product details for chicken thing"]
        for _ in 0..<12 where !chicken.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(chicken.exists)
        let chickenDetails = try XCTUnwrap(chicken.value as? String)
        XCTAssertTrue(
            chickenDetails.components(separatedBy: ", ").contains("Recipe needs 500 g"),
            "The added chicken item must retain its edited quantity: \(chickenDetails)"
        )
        XCTAssertTrue(app.buttons["Product details for Oat milk"].exists)
        XCTAssertFalse(app.buttons["Check Coriander"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "List photo partial reading retained after editing"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
    }

    @MainActor
    func testProductLinkImportFailureRemainsVisibleAfterRetry() throws {
        continueAfterFailure = false
        let app = launchFixtureApp(arguments: ["-reasi-ui-test-product-link-failure"])
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 8))
        app.buttons["Home"].tap()
        let createPlan = app.buttons["Create a plan"].firstMatch
        XCTAssertTrue(createPlan.waitForExistence(timeout: 3))
        createPlan.tap()

        let add = app.buttons["plan-builder-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        for _ in 0..<8 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertTrue(app.staticTexts["Add to your plan"].waitForExistence(timeout: 3))
        app.buttons["Find product"].tap()

        let search = app.textFields["Search products"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "https://example.com/product")
        let importButton = app.buttons["product-link-import"]
        let error = app.descendants(matching: .any)["product-link-error"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        XCTAssertEqual(importButton.label, "Import product")
        XCTAssertFalse(error.exists)

        for attempt in 1...2 {
            XCTAssertTrue(importButton.isEnabled)
            importButton.tap()
            XCTAssertTrue(error.waitForExistence(timeout: 5), "Import attempt \(attempt) must show an error")
            XCTAssertTrue(error.isHittable)
            XCTAssertEqual(error.label, "That link could not be read. Try searching by product name.")
            XCTAssertEqual(importButton.label, "Try again")
            XCTAssertTrue(importButton.isEnabled)
            XCTAssertEqual(search.value as? String, "https://example.com/product")
        }
    }

    @MainActor
    private func launchFixtureApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ReasiShowShoppingFixture", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated",
            "-reasi.settings.appearance", "light",
        ] + arguments
        // Empty environment values override bundled developer credentials in ReasiConfig.
        app.launchEnvironment = [
            "REASI_SUPABASE_URL": "",
            "REASI_SUPABASE_ANON_KEY": "",
            "REASI_POSTHOG_KEY": "",
            "REASI_POSTHOG_HOST": "",
            "REASI_REVENUECAT_PUBLIC_KEY": "",
            "REASI_ENABLE_REVENUECAT": "NO",
        ]
        app.launch()
        return app
    }
}
