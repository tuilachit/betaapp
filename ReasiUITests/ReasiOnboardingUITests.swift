import XCTest

final class ReasiOnboardingUITests: XCTestCase {
    @MainActor
    private func launchOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ReasiForceOnboarding",
            "-ReasiSkipBrandIntro",
            "-ReasiUITestUnauthenticated",
        ]
        app.launch()
        return app
    }

    @MainActor
    func testFreshInstallCanReachRequiredSignInWithoutADeadEnd() throws {
        continueAfterFailure = false
        let app = launchOnboarding()
        let getStarted = app.buttons["Get started"]
        let foundGetStarted = getStarted.waitForExistence(timeout: 8)
        XCTAssertTrue(foundGetStarted)
        getStarted.tap()

        let continueButton = app.buttons["Continue"]
        let foundContinue = continueButton.waitForExistence(timeout: 3)
        XCTAssertTrue(foundContinue)
        continueButton.tap()

        let foundPurpose = app.staticTexts["What makes groceries hardest?"].waitForExistence(timeout: 3)
        XCTAssertTrue(foundPurpose)

        for expectedHeading in [
            "How many are you cooking for?",
            "What feels good to cook?",
            "How should Reasi talk about money?",
            "Where do you usually shop?",
        ] {
            let skip = app.buttons["Skip"]
            let foundSkip = skip.waitForExistence(timeout: 3)
            XCTAssertTrue(foundSkip)
            skip.tap()
            let foundHeading = app.staticTexts[expectedHeading].waitForExistence(timeout: 3)
            XCTAssertTrue(foundHeading)
        }

        app.buttons["Skip"].tap()

        let foundSignIn = app.staticTexts["Save your Reasi setup."].waitForExistence(timeout: 3)
        let hasEmail = app.buttons["Continue with email"].exists
        let requiresSignIn = app.buttons["Sign in to continue"].exists
        let hasMaybeLater = app.buttons["Maybe later"].exists
        XCTAssertTrue(foundSignIn)
        XCTAssertTrue(hasEmail)
        XCTAssertTrue(requiresSignIn)
        XCTAssertFalse(hasMaybeLater)
    }

    @MainActor
    func testSpendOverviewOpensProfileAndTripRecap() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ReasiShowSpendFixture",
            "-ReasiSkipBrandIntro",
            "-ReasiUITestUnauthenticated",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Spend"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Projected basket"].exists)
        XCTAssertTrue(app.staticTexts["Based on 8 of 10 priced items"].exists)

        let profile = app.buttons["reasi-profile-button"]
        XCTAssertTrue(profile.exists)
        profile.tap()
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 3))
        app.buttons["Back"].tap()

        let chart = app.otherElements["spend-category-chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 3))

        let protein = app.buttons["spend-category-legend-protein"]
        XCTAssertTrue(protein.exists)
        let chartFrame = chart.frame
        let chartTap = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(
                dx: chartFrame.maxX - chartFrame.width * 0.10,
                dy: chartFrame.midY
            ))
        chartTap.tap()
        let chartSelectedLegend = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND value == %@",
            "spend-category-legend-",
            "Selected"
        )).firstMatch
        XCTAssertTrue(chartSelectedLegend.waitForExistence(timeout: 2))
        chartSelectedLegend.tap()
        protein.tap()
        XCTAssertEqual(protein.value as? String, "Selected")

        let periodControl = app.segmentedControls["Spending period"]
        XCTAssertTrue(periodControl.exists)
        periodControl.buttons["Month"].tap()
        XCTAssertTrue(app.staticTexts["THIS MONTH"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "average per week")).firstMatch.exists)
        periodControl.buttons["Week"].tap()
        XCTAssertTrue(app.staticTexts["THIS WEEK"].waitForExistence(timeout: 3))

        let moreInsights = app.buttons["spend-more-insights"]
        XCTAssertTrue(moreInsights.waitForExistence(timeout: 3))
        for _ in 0..<6 where !isClearOfFloatingTabBar(moreInsights, in: app) {
            app.swipeUp()
        }
        XCTAssertTrue(isClearOfFloatingTabBar(moreInsights, in: app))
        moreInsights.tap()
        XCTAssertEqual(moreInsights.value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts["PATTERN"].exists)
        XCTAssertTrue(app.staticTexts["WHY IT MATTERS"].exists)

        let shop = app.buttons["spend-recent-trip-ui-test-trip"]
        XCTAssertTrue(shop.waitForExistence(timeout: 3))
        for _ in 0..<6 where !isClearOfFloatingTabBar(shop, in: app) {
            app.swipeUp()
        }
        XCTAssertTrue(isClearOfFloatingTabBar(shop, in: app))
        shop.tap()
        XCTAssertTrue(app.staticTexts["Shop recap"].waitForExistence(timeout: 3))
    }

    private func isClearOfFloatingTabBar(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        element.isHittable && element.frame.maxY < app.frame.maxY - 150
    }

    @MainActor
    func testPurposeSurveyAcceptsThreeOrderedPriorities() throws {
        continueAfterFailure = false
        let app = launchOnboarding()
        let foundGetStarted = app.buttons["Get started"].waitForExistence(timeout: 8)
        XCTAssertTrue(foundGetStarted)
        app.buttons["Get started"].tap()
        app.buttons["Continue"].tap()

        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Groceries cost too much")).firstMatch
        let second = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Shopping takes too long")).firstMatch
        let third = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Finding products is frustrating")).firstMatch

        let foundFirst = first.waitForExistence(timeout: 3)
        XCTAssertTrue(foundFirst)
        first.tap()
        second.tap()
        third.tap()

        let firstValue = first.value as? String
        let secondValue = second.value as? String
        let thirdValue = third.value as? String
        let showsLimit = app.staticTexts["3/3"].exists
        let canContinue = app.buttons["Continue"].isEnabled
        XCTAssertEqual(firstValue, "Priority 1")
        XCTAssertEqual(secondValue, "Priority 2")
        XCTAssertEqual(thirdValue, "Priority 3")
        XCTAssertTrue(showsLimit)
        XCTAssertTrue(canContinue)
    }
}
