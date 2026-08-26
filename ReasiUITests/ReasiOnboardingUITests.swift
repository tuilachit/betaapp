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
