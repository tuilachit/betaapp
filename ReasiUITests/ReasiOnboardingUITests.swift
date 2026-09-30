import XCTest
import UIKit

final class ReasiOnboardingUITests: XCTestCase {
    @MainActor
    func testPlanBuilderPickerPreservesDraftAndOpensProductSearch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ReasiShowShoppingFixture", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated",
                               "-reasi.settings.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 8))
        app.buttons["Home"].tap()
        app.buttons["Create a plan"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText("Salmon pasta and flan for two.")
        let add = app.buttons["plan-builder-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        reveal(add, in: app)
        add.tap()
        XCTAssertTrue(app.staticTexts["Add to your plan"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        for option in ["Meal photo", "Find product", "Product photo", "List photo"] {
            XCTAssertTrue(app.buttons[option].isHittable)
        }
        let pickerScreenshot = XCTAttachment(screenshot: app.screenshot())
        pickerScreenshot.name = "Plan add options light"
        pickerScreenshot.lifetime = .keepAlways
        self.add(pickerScreenshot)
        app.buttons["Find product"].tap()
        XCTAssertTrue(app.textFields["Search products"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Scan product barcode"].exists)
        app.buttons["Close product search"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "Salmon pasta and flan for two.")
        add.tap()
        app.buttons["Close add options"].tap()
        XCTAssertTrue(app.staticTexts["Add to your plan"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "Salmon pasta and flan for two.")
        let composerScreenshot = XCTAttachment(screenshot: app.screenshot())
        composerScreenshot.name = "Plan composer light"
        composerScreenshot.lifetime = .keepAlways
        self.add(composerScreenshot)
        for option in ["Meal photo", "Product photo", "List photo"] {
            add.tap()
            XCTAssertTrue(app.buttons[option].waitForExistence(timeout: 3))
            app.buttons[option].tap()
            let cancel = app.buttons["Cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 8), "\(option) must open the photo library")
            cancel.tap()
            XCTAssertTrue(add.waitForExistence(timeout: 3))
            XCTAssertEqual(editor.value as? String, "Salmon pasta and flan for two.")
        }
        app.buttons["Close plan builder"].tap()
        app.buttons["Create a plan"].firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "Salmon pasta and flan for two.")
    }

    @MainActor
    func testPlanBuilderPickerSupportsLargeTextAndBothAppearances() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark"] {
            app.launchArguments = ["-ReasiShowShoppingFixture", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated",
                                   "-reasi.settings.appearance", appearance,
                                   "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
            app.launch()
            XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 8))
            app.buttons["Home"].tap()
            app.buttons["Create a plan"].firstMatch.tap()
            XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3))
            let add = app.buttons["plan-builder-add"]
            reveal(add, in: app)
            add.tap()
            XCTAssertTrue(app.buttons["Meal photo"].waitForExistence(timeout: 3))
            for option in ["Meal photo", "Find product", "Product photo", "List photo"] {
                let button = app.buttons[option]
                for _ in 0..<5 where !button.isHittable { app.swipeUp() }
                XCTAssertTrue(button.isHittable)
                XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX)
                XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
            }
            try app.performAccessibilityAudit(for: .textClipped)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Plan add options large text \(appearance)"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            app.buttons["Close add options"].tap()
            app.terminate()
        }
    }

    @MainActor
    func testOnboardingHasNoClippedTextAtAccessibilitySizes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        for size in ["UICTContentSizeCategoryAccessibilityXL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            for appearance in ["light", "dark"] {
                app.launchArguments = [
                    "-ReasiForceOnboarding", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated",
                    "-reasi.onboarding.preferences.v1", "",
                    "-reasi.onboarding.completed.v1", "NO",
                    "-reasi.settings.appearance", appearance,
                    "-UIPreferredContentSizeCategoryName", size,
                ]
                app.launch()
                XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 8))
                let heading = app.staticTexts["Never think about\ngroceries again."]
                let viewport = app.scrollViews.firstMatch.frame
                XCTAssertLessThanOrEqual(heading.frame.height, viewport.height,
                                         "The welcome heading must be readable within one viewport at \(size)")
                XCTAssertGreaterThanOrEqual(heading.frame.minX, viewport.minX - 1)
                XCTAssertLessThanOrEqual(heading.frame.maxX, viewport.maxX + 1)
                XCTAssertLessThanOrEqual(heading.frame.maxY, app.buttons["Get started"].frame.minY,
                                         "The welcome heading must not be hidden behind the fixed action")
                try app.performAccessibilityAudit(for: .textClipped)
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "Onboarding \(size) \(appearance)"
                attachment.lifetime = .keepAlways
                add(attachment)

                app.buttons["Get started"].tap()
                for (title, action) in [
                    ("Plan your week, build your list, and shop smarter in minutes.", "Continue"),
                    ("What makes groceries hardest?", "Skip"),
                    ("How many are you cooking for?", "Skip"),
                    ("What feels good to cook?", "Skip"),
                    ("How should Reasi talk about money?", "Skip"),
                    ("Where do you usually shop?", "Skip"),
                    ("Save your Reasi setup.", ""),
                ] {
                    let titleElement = app.staticTexts[title]
                    XCTAssertTrue(titleElement.waitForExistence(timeout: 3))
                    XCTAssertGreaterThanOrEqual(titleElement.frame.minX, viewport.minX - 1)
                    XCTAssertLessThanOrEqual(titleElement.frame.maxX, viewport.maxX + 1)
                    try app.performAccessibilityAudit(for: .textClipped)
                    let screen = XCTAttachment(screenshot: app.screenshot())
                    screen.name = "\(title) \(size) \(appearance)"
                    screen.lifetime = .keepAlways
                    add(screen)
                    if !action.isEmpty {
                        app.buttons[action].tap()
                        XCTAssertTrue(titleElement.waitForNonExistence(timeout: 3), "Each tap must leave exactly one onboarding step")
                    }
                }
                app.terminate()
            }
        }
    }

    @MainActor
    func testThemeScreensAndLargeTextInBothAppearances() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let fixtures = ["-ReasiShowShoppingFixture", "-ReasiShowSpendFixture", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated"]
        for (name, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            let appearance = ["-reasi.settings.appearance", name]
            app.launchArguments = fixtures + appearance
            app.launch()
            XCTAssertTrue(app.staticTexts["Shopping list"].waitForExistence(timeout: 8))
            for (tab, title) in [("Home", "Home"), ("Plans", "Your week"), ("List", "Shopping list"), ("Spend", "Spend")] {
                app.buttons[tab].tap()
                waitForSettledHeading(title, in: app)
                assertAppearance(style, in: app, name: "\(tab) \(name)")
                if tab == "Plans" {
                    let meal = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Miso salmon rice bowls")).firstMatch
                    reveal(meal, in: app)
                    meal.tap()
                    XCTAssertTrue(app.buttons["Close recipe"].waitForExistence(timeout: 3))
                    assertAppearance(style, in: app, name: "Recipe overlay \(name)")
                    app.buttons["Close recipe"].tap()
                }
            }
            app.buttons["reasi-profile-button"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
            assertAppearance(style, in: app, name: "Account \(name)")
            app.terminate()

            app.launchArguments = fixtures + appearance + ["-reasi-show-paywall", "-reasi-show-paywall-fixture"]
            app.launch()
            XCTAssertTrue(app.staticTexts["Reasi Pro"].waitForExistence(timeout: 8))
            assertAppearance(style, in: app, name: "Paywall \(name)")
            app.terminate()

            app.launchArguments = appearance + ["-ReasiForceOnboarding", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated",
                                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
            app.launch()
            XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 8))
            assertAppearance(style, in: app, name: "Onboarding large text \(name)")
            app.terminate()
        }
    }

    @MainActor
    func testAppearanceSwitchesAcrossScreensAndPersistsAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ReasiShowShoppingFixture", "-ReasiShowSpendFixture", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated"]
        app.launch()
        XCTAssertTrue(app.buttons["reasi-profile-button"].waitForExistence(timeout: 8))
        app.buttons["reasi-profile-button"].tap()

        let picker = app.buttons["reasi-appearance-picker"]
        reveal(picker, in: app)
        picker.tap()
        app.buttons["Dark"].tap()
        assertAppearance(.dark, in: app, name: "Profile Dark")
        picker.tap()
        app.buttons["Light"].tap()
        XCTAssertTrue(picker.label.contains("Light"))
        assertAppearance(.light, in: app, name: "Profile Light")

        let listSettings = app.buttons["settings-shopping"]
        reveal(listSettings, in: app)
        listSettings.tap()
        XCTAssertTrue(app.navigationBars["List behavior"].waitForExistence(timeout: 3))
        assertAppearance(.light, in: app, name: "Settings Sheet Light")
        app.buttons["Done"].tap()
        for _ in 0..<8 where !app.buttons["Back"].isHittable { app.swipeDown() }
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["Shopping list"].waitForExistence(timeout: 3))
        assertAppearance(.light, in: app, name: "Shopping Light")
        app.buttons["Spend"].tap()
        XCTAssertTrue(app.staticTexts["Projected basket"].waitForExistence(timeout: 3))
        assertAppearance(.light, in: app, name: "Spend Light")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Shopping list"].waitForExistence(timeout: 8))
        assertAppearance(.light, in: app, name: "Relaunch Light")
        app.buttons["reasi-profile-button"].tap()
        reveal(picker, in: app)
        XCTAssertTrue(picker.label.contains("Light"))
        picker.tap()
        app.buttons["Dark"].tap()
        assertAppearance(.dark, in: app, name: "Profile Restored Dark")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Shopping list"].waitForExistence(timeout: 8))
        assertAppearance(.dark, in: app, name: "Relaunch Dark")
    }

    @MainActor
    func testSettingsDraftsDiscardAndSave() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ReasiShowShoppingFixture", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated",
                               "-reasi.settings.appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.buttons["reasi-profile-button"].waitForExistence(timeout: 8))
        app.buttons["reasi-profile-button"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Create a plan"].exists, "Settings should not have the floating add button")
        XCTAssertFalse(app.textFields["Email"].exists, "Sign-in fields belong in the sign-in sheet")
        app.buttons["settings-sign-in"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 3))
        app.buttons["Close"].tap()

        app.buttons["settings-planning"].tap()
        XCTAssertTrue(app.navigationBars["Meal preferences"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["settings-save"].exists)
        let foodStyle = app.buttons["Vietnamese"]
        let initialValue = foodStyle.value as? String
        foodStyle.tap()
        XCTAssertTrue(app.buttons["settings-save"].exists)
        app.buttons["Close"].tap()
        app.buttons["Discard changes"].tap()
        app.buttons["settings-planning"].tap()
        XCTAssertEqual(foodStyle.value as? String, initialValue, "Discard must leave preferences unchanged")

        foodStyle.tap()
        let changedValue = foodStyle.value as? String
        app.buttons["settings-save"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["settings-planning"].tap()
        XCTAssertEqual(foodStyle.value as? String, changedValue, "Saved preferences must reopen with the edited value")
        foodStyle.tap()
        app.buttons["settings-save"].tap()

        app.buttons["settings-spending"].tap()
        XCTAssertTrue(app.navigationBars["Budget & coaching"].waitForExistence(timeout: 3))
        let budget = app.textFields["settings-weekly-budget"]
        budget.tap()
        if let value = budget.value as? String, value != "No target" {
            budget.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        budget.typeText("10001")
        app.buttons["settings-save"].tap()
        XCTAssertTrue(app.staticTexts["Enter an amount above zero, up to A$10,000."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Budget & coaching"].exists)
        app.buttons["Close"].tap()
        app.buttons["Discard changes"].tap()

        app.buttons["settings-store"].tap()
        XCTAssertTrue(app.navigationBars["Preferred store"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["settings-save"].exists)
        app.buttons["Close"].tap()
        app.buttons["settings-reminders"].tap()
        XCTAssertTrue(app.navigationBars["Weekly reminder"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
    }

    @MainActor
    func testSettingsLargeTextAndListPreferencePersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ReasiShowShoppingFixture", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated",
                               "-reasi.settings.appearance", "light",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        XCTAssertTrue(app.buttons["reasi-profile-button"].waitForExistence(timeout: 8))
        app.buttons["reasi-profile-button"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        try app.performAccessibilityAudit(for: .textClipped)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Settings large text"
        attachment.lifetime = .keepAlways
        add(attachment)
        let list = app.buttons["settings-shopping"]
        for _ in 0..<5 where !list.isHittable { app.swipeUp() }
        list.tap()
        XCTAssertTrue(app.navigationBars["List behavior"].waitForExistence(timeout: 3))
        try app.performAccessibilityAudit(for: .textClipped)
        let toggle = app.switches["settings-hide-bought"]
        let initialValue = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = NSPredicate(format: "value != %@", initialValue ?? "")
        expectation(for: changed, evaluatedWith: toggle)
        waitForExpectations(timeout: 3)
        let editedValue = toggle.value as? String
        XCTAssertNotEqual(initialValue, editedValue)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["reasi-profile-button"].waitForExistence(timeout: 8))
        app.buttons["reasi-profile-button"].tap()
        for _ in 0..<5 where !list.isHittable { app.swipeUp() }
        list.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, editedValue)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            let frame = element.frame
            if element.isHittable && frame.minY >= app.frame.minY + 100 && frame.maxY <= app.frame.maxY - 150 { break }
            if element.exists && frame.minY < app.frame.minY + 100 { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func waitForSettledHeading(_ title: String, in app: XCUIApplication) {
        let heading = app.staticTexts[title].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        var previousFrame = CGRect.null
        // A tab tap can return while its slide transition is still drawing.
        let settled = NSPredicate { _, _ in
            guard heading.exists, heading.isHittable else { return false }
            let frame = heading.frame
            let isSettled = app.frame.contains(frame) && frame == previousFrame
            previousFrame = frame
            return isSettled
        }
        let expectation = XCTNSPredicateExpectation(predicate: settled, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, "\(title) must settle before sampling its background")
    }

    @MainActor
    private func assertAppearance(_ style: UIUserInterfaceStyle, in app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // Sample the unobstructed outer background, not the selected picker label.
        let image = screenshot.image.cgImage!
        let pixel = image.cropping(to: CGRect(x: image.width / 100, y: image.height / 2, width: 1, height: 1))!
        var rgba = [UInt8](repeating: 0, count: 4)
        rgba.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let brightness = Double(Int(rgba[0]) + Int(rgba[1]) + Int(rgba[2])) / (3 * 255)
        if style == .light {
            XCTAssertGreaterThan(brightness, 0.8, name)
        } else {
            XCTAssertLessThan(brightness, 0.2, name)
        }
    }

    @MainActor
    private func launchOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ReasiForceOnboarding",
            "-ReasiSkipBrandIntro",
            "-ReasiUITestUnauthenticated",
            "-reasi.onboarding.preferences.v1", "",
            "-reasi.onboarding.completed.v1", "NO",
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
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
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

    @MainActor
    func testPaywallUsesReasiVisualHierarchy() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ReasiShowShoppingFixture",
            "-ReasiSkipBrandIntro",
            "-ReasiUITestUnauthenticated",
            "-reasi-show-paywall",
            "-reasi-show-paywall-fixture",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Reasi Pro"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Start your 2-week free trial."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Try Reasi Pro before your first charge."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["In 2 weeks"].exists)
        XCTAssertTrue(app.staticTexts["No charge today"].exists)
        XCTAssertTrue(app.staticTexts["Annual"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["A$79.99"].exists)
        XCTAssertTrue(app.staticTexts["A$17.99"].exists)
        XCTAssertTrue(app.staticTexts["A$7.99"].exists)
        XCTAssertTrue(app.buttons["Restore Purchases"].exists)
        XCTAssertTrue(app.buttons["More paywall details"].exists)
        XCTAssertTrue(app.staticTexts["Billing begins at A$79.99 per year"].exists)
        XCTAssertTrue(app.staticTexts["After 2 weeks: A$79.99 per year. Auto-renews."].exists)
        XCTAssertFalse(app.staticTexts["Your first complete week is included. Reasi Pro unlocks every new week after that."].exists)

        let monthlyPlan = app.buttons["Monthly plan"]
        XCTAssertTrue(monthlyPlan.exists)
        monthlyPlan.tap()
        XCTAssertTrue(app.staticTexts["Start your 3-day free trial."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["In 3 days"].exists)
        XCTAssertTrue(app.staticTexts["After 3 days: A$17.99 per month. Auto-renews."].exists)

        let weeklyPlan = app.buttons["Weekly plan"]
        XCTAssertTrue(weeklyPlan.exists)
        XCTAssertFalse((weeklyPlan.value as? String ?? "").localizedCaseInsensitiveContains("free"))
        XCTAssertTrue((weeklyPlan.value as? String ?? "").contains("A$7.99"))
        let paywallDetails = app.buttons["More paywall details"]
        reveal(paywallDetails, in: app)
        paywallDetails.tap()
        XCTAssertTrue(app.buttons["Why Reasi Pro?"].waitForExistence(timeout: 3))
        app.buttons["Why Reasi Pro?"].tap()
        XCTAssertTrue(app.staticTexts["Why you're seeing this"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()

        let closePaywall = app.buttons["Close paywall"]
        reveal(closePaywall, in: app)
        closePaywall.tap()
        XCTAssertTrue(app.staticTexts["Not ready yet?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Keep my plan"].exists)
        XCTAssertTrue(app.buttons["View plans"].exists)
    }

    private func isClearOfFloatingTabBar(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        element.isHittable && element.frame.maxY < app.frame.maxY - 150
    }

    @MainActor
    func testSavedIngredientsResolveToRealCatalogueProducts() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ReasiShowShoppingFixture", "-ReasiMatchCatalogueFixture", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Coles Regular Pork Mince"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Estimated total"].exists)
        XCTAssertTrue(app.buttons["Uncheck Pork mince"].exists)
        XCTAssertTrue(app.staticTexts["500g"].exists)
        XCTAssertFalse(app.staticTexts["Need 200g"].exists)
        XCTAssertTrue(app.buttons["Change product for Pork mince"].isHittable)
        XCTAssertFalse(app.staticTexts["Choose a product"].exists)
        app.buttons["Change product for Pork mince"].tap()
        XCTAssertTrue(app.navigationBars["Change product"].waitForExistence(timeout: 5))
        app.buttons["Close product search"].tap()

        app.buttons["Product details for Pork mince"].tap()
        XCTAssertTrue(app.staticTexts["200g · Meat"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Uncheck Pork mince"].exists, "Opening details must not toggle the item")

        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "Saved list resolved to actual Coles products"
        top.lifetime = .keepAlways
        add(top)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Coles Soy Sauce"].exists)
        XCTAssertTrue(app.staticTexts["Squid Fish Sauce"].exists)
        let bottom = XCTAttachment(screenshot: app.screenshot())
        bottom.name = "Specific sauce products with catalogue photos"
        bottom.lifetime = .keepAlways
        add(bottom)
    }

    @MainActor
    func testSavedShopShowsSubtotalAndOpensMatchingRecap() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark"] {
            app.launchArguments = ["-ReasiShowShoppingFixture", "-ReasiShopSavedFixture", "-ReasiShowSpendFixture",
                                   "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated", "-reasi.settings.appearance", appearance]
            app.launch()
            let card = app.otherElements["shop-saved-card"]
            XCTAssertTrue(card.waitForExistence(timeout: 8))
            XCTAssertTrue(card.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Estimated subtotal")).firstMatch.exists)
            XCTAssertTrue(card.staticTexts["Excludes 2 unpriced items"].exists)
            XCTAssertFalse(app.staticTexts["Swipe to finish"].exists)
            XCTAssertFalse(app.buttons["Ask Reasi"].exists)
            let button = app.buttons["view-saved-shop"]
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Shop saved \(appearance)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            button.tap()
            XCTAssertTrue(app.staticTexts["Shop recap"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testSavedShopHandlesMissingPricesAndLargeText() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ReasiShowShoppingFixture", "-ReasiShopSavedFixture", "-ReasiUnpricedShopFixture", "-ReasiShowSpendFixture",
                               "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated", "-reasi.settings.appearance", "light",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        let card = app.otherElements["shop-saved-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertTrue(card.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Total unavailable")).firstMatch.exists)
        XCTAssertFalse(card.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "$0.00")).firstMatch.exists)
        let button = app.buttons["view-saved-shop"]
        reveal(button, in: app)
        XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX - 20)
        XCTAssertGreaterThanOrEqual(button.frame.minX, 20)
        try app.performAccessibilityAudit(for: .textClipped)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shop saved with large text and unavailable prices"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        button.tap()
        XCTAssertTrue(app.staticTexts["THIS WEEK"].waitForExistence(timeout: 5), "Without a loaded matching trip, the button should open Spend history")
        XCTAssertFalse(app.staticTexts["Shop recap"].exists)
    }

    @MainActor
    func testProductPickerKeepsResultsConciseAndMovesCalculationsIntoDetails() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ReasiShowShoppingFixture", "-ReasiProductPickerFixture", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated"]
        app.launch()
        let change = app.buttons["Change product for Brown onions"]
        XCTAssertTrue(change.waitForExistence(timeout: 8))
        change.tap()
        let review = app.buttons["Review Coles Brown Onions"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Show the prefilled results without covering them with the keyboard")
        XCTAssertFalse(app.staticTexts["Required quantity or price unconfirmed"].exists)
        XCTAssertFalse(app.scrollViews["product-search-results"].staticTexts["Fresh Produce"].exists)
        XCTAssertTrue(app.buttons["Current product: Coles Loose Brown Onions"].exists)
        XCTAssertFalse(app.buttons["Current product: Coles Loose Brown Onions"].isEnabled)
        review.tap()
        XCTAssertTrue(app.navigationBars["Product details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 medium"].exists)
        XCTAssertTrue(app.staticTexts["Quantity or price needs checking"].exists)
        XCTAssertFalse(app.textFields["Shelf price per pack"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Clean onion product picker"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testProductPickerPreservesBudgetReviewAndRecalculatesShelfPrice() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ReasiShowShoppingFixture", "-ReasiProductPickerFixture", "-ReasiPickerBudgetFixture", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated"]
        app.launch()
        let change = app.buttons["Change product for Brown onions"]
        XCTAssertTrue(change.waitForExistence(timeout: 8))
        change.tap()
        let review = app.buttons["Review Coles Brown Onions"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Over budget"].firstMatch.exists)
        review.tap()
        let useProduct = app.buttons["Use this product"]
        XCTAssertTrue(useProduct.waitForExistence(timeout: 5))
        XCTAssertFalse(useProduct.isEnabled)
        let shelfPrice = app.buttons["Different shelf price?"]
        for _ in 0..<4 where !shelfPrice.isHittable { app.swipeUp() }
        XCTAssertTrue(shelfPrice.isHittable)
        shelfPrice.tap()
        let field = app.textFields["Shelf price per pack"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        reveal(field, in: app)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        field.typeText("1.50")
        XCTAssertTrue(useProduct.isEnabled, "Recalculate the full basket when the shelf price is corrected")
    }

    @MainActor
    func testShoppingProductControlsRemainUsableWithLargeText() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ReasiShowShoppingFixture", "-ReasiMatchCatalogueFixture", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"
        ]
        app.launch()
        let change = app.buttons["Change product for Pork mince"]
        XCTAssertTrue(change.waitForExistence(timeout: 8))
        for _ in 0..<5 where !change.isHittable || change.frame.maxY > app.frame.maxY - 190 {
            app.swipeUp()
        }
        XCTAssertTrue(change.isHittable)
        XCTAssertGreaterThanOrEqual(change.frame.height, 44)
        XCTAssertLessThanOrEqual(change.frame.maxX, app.frame.maxX - 10)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Compact shopping controls with large text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        change.tap()
        XCTAssertTrue(app.navigationBars["Change product"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testShoppingListShowsChosenProductsAndAVisibleChangeAction() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ReasiShowShoppingFixture", "-ReasiSkipBrandIntro", "-ReasiUITestUnauthenticated"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Shopping list"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Coles Baby Spinach"].exists)
        XCTAssertTrue(app.staticTexts["Priced subtotal"].exists)
        let change = app.buttons["Change product for Baby spinach"]
        XCTAssertTrue(change.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Product choices and budget overview"
        attachment.lifetime = .keepAlways
        add(attachment)

        change.tap()
        XCTAssertTrue(app.navigationBars["Change product"].waitForExistence(timeout: 5))
        app.buttons["Close product search"].tap()
        XCTAssertTrue(app.buttons["Uncheck Baby spinach"].exists)
    }

    @MainActor
    func testShoppingListScrollsPastDockControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ReasiShowShoppingFixture",
            "-ReasiSkipBrandIntro",
            "-ReasiUITestUnauthenticated",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Shopping list"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Swipe to finish"].exists)
        XCTAssertTrue(app.buttons["Ask Reasi"].exists)

        let finalItem = app.staticTexts["Pita bread"]
        for _ in 0..<8 where !finalItem.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(finalItem.isHittable)
        XCTAssertTrue(app.buttons["Ask Reasi"].isHittable)
    }

    @MainActor
    func testShoppingAssistantFloatsOverScrollingListWithoutCheckedItems() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ReasiShowShoppingFixture",
            "-ReasiSkipBrandIntro",
            "-ReasiUITestUnauthenticated",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Shopping list"].waitForExistence(timeout: 8))
        app.buttons["Uncheck Baby spinach"].tap()
        app.buttons["Uncheck Lemons"].tap()
        XCTAssertFalse(app.staticTexts["Swipe to finish"].exists)

        let assistant = app.buttons["Ask Reasi"]
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(assistant.isHittable)
        let initialFrame = assistant.frame
        XCTAssertGreaterThan(scrollView.frame.maxY, initialFrame.maxY,
                             "The list viewport must extend behind the floating assistant.")
        XCTAssertLessThan(initialFrame.maxY, app.buttons["List"].frame.minY)

        let finalItem = app.staticTexts["Pita bread"]
        for _ in 0..<8 {
            if finalItem.isHittable && finalItem.frame.maxY < assistant.frame.minY { break }
            scrollView.swipeUp()
            XCTAssertTrue(assistant.isHittable)
            XCTAssertEqual(assistant.frame.minY, initialFrame.minY, accuracy: 1)
        }
        XCTAssertTrue(finalItem.isHittable)
        XCTAssertLessThan(finalItem.frame.maxY, assistant.frame.minY)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Floating assistant over scrolled unchecked list"
        attachment.lifetime = .keepAlways
        add(attachment)

        assistant.tap()
        XCTAssertTrue(app.navigationBars["Shopping assistant"].waitForExistence(timeout: 3))
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
        XCTAssertTrue(app.staticTexts["0/3"].exists, "A new user must start without inherited survey answers")
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
