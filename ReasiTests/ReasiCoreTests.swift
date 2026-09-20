import XCTest
import SwiftUI
import UIKit
@testable import Reasi

@MainActor
final class ReasiAppearanceTests: XCTestCase {
    func testAppearanceDefaultsToLightAndRejectsUnknownValues() {
        let name = "ReasiAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertEqual(UserSettingsStore(defaults: defaults).appearance, .light)
        defaults.set("system", forKey: ReasiSettingKey.appearance)
        XCTAssertEqual(UserSettingsStore(defaults: defaults).appearance, .light)
        defaults.set(42, forKey: ReasiSettingKey.appearance)
        XCTAssertEqual(UserSettingsStore(defaults: defaults).appearance, .light)
    }

    func testAppearanceUpdatesAndRestoresBothChoices() {
        let name = "ReasiAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = UserSettingsStore(defaults: defaults)

        for appearance in ReasiAppearance.allCases {
            settings.setAppearance(appearance)
            XCTAssertEqual(settings.appearance, appearance)
            XCTAssertEqual(defaults.string(forKey: ReasiSettingKey.appearance), appearance.rawValue)
            XCTAssertEqual(UserSettingsStore(defaults: defaults).appearance, appearance)
        }
        XCTAssertEqual(ReasiAppearance.light.colorScheme, .light)
        XCTAssertEqual(ReasiAppearance.dark.colorScheme, .dark)
    }

    func testPaletteAdaptsAndPreservesOriginalDarkColors() {
        let colors = Color.reasi
        let original: [(Color, UInt)] = [
            (colors.background, 0x09090A), (colors.backgroundElevated, 0x0D0D0F),
            (colors.surface, 0x171719), (colors.surfaceHigh, 0x202023),
            (colors.border, 0x29292D), (colors.borderStrong, 0x3D3D43),
            (colors.text, 0xF4F4F5), (colors.textMuted, 0xB8B8BF),
            (colors.muted, 0x85858E), (colors.dim, 0x5E5E66),
            (colors.danger, 0xFF6B6B), (colors.warning, 0xFFD36A),
            (colors.success, 0xD7F4D0), (colors.planHighlight, 0x20251E),
        ]
        for (color, hex) in original {
            let dark = components(color, style: .dark)
            XCTAssertEqual(dark[0], Double((hex >> 16) & 255) / 255, accuracy: 0.001)
            XCTAssertEqual(dark[1], Double((hex >> 8) & 255) / 255, accuracy: 0.001)
            XCTAssertEqual(dark[2], Double(hex & 255) / 255, accuracy: 0.001)
            XCTAssertNotEqual(dark, components(color, style: .light))
        }
        for style: UIUserInterfaceStyle in [.light, .dark] {
            XCTAssertEqual(components(colors.glass, style: style)[3], 0.82, accuracy: 0.001)
            XCTAssertGreaterThan(contrast(colors.background, colors.text, style: style), 7)
            XCTAssertGreaterThan(contrast(colors.background, colors.success, style: style), 4.5)
            XCTAssertGreaterThan(contrast(colors.onImageMuted, colors.imageBackground, style: style), 4.5)
        }
        XCTAssertEqual(components(colors.onImage, style: .light), components(colors.onImage, style: .dark))
    }

    func testLightModeTextAndStatusContrastAcrossSurfaces() {
        let colors = Color.reasi
        for background in [colors.background, colors.backgroundElevated, colors.surface, colors.surfaceHigh, colors.planHighlight] {
            for foreground in [colors.text, colors.textMuted, colors.muted, colors.dim, colors.danger, colors.warning, colors.success] {
                XCTAssertGreaterThanOrEqual(contrast(foreground, background, style: .light), 4.5)
            }
        }
    }

    private func components(_ color: Color, style: UIUserInterfaceStyle) -> [Double] {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &a))
        return [Double(r), Double(g), Double(b), Double(a)]
    }

    private func contrast(_ foreground: Color, _ background: Color, style: UIUserInterfaceStyle) -> Double {
        func luminance(_ color: Color) -> Double {
            let rgb = components(color, style: style).prefix(3).map {
                $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
            }
            return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
        }
        let first = luminance(foreground), second = luminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}

final class ReasiCoreTests: XCTestCase {
    func testPurposeSelectionKeepsPriorityOrderAndCapsAtThree() {
        let normalized = OnboardingPreferences.normalizedPurposeSelection([
            .saveMoney,
            .saveShoppingTime,
            .saveMoney,
            .findProductsFaster,
            .eatHealthier,
        ])

        XCTAssertEqual(normalized, [.saveMoney, .saveShoppingTime, .findProductsFaster])
    }

    func testPurposeToggleRemovesAndAppendsWithoutExceedingLimit() {
        var preferences = OnboardingPreferences.empty
        preferences.togglePurpose(.saveMoney)
        preferences.togglePurpose(.saveShoppingTime)
        preferences.togglePurpose(.findProductsFaster)
        preferences.togglePurpose(.eatHealthier)

        XCTAssertEqual(
            preferences.selectedPurposes,
            [.saveMoney, .saveShoppingTime, .findProductsFaster]
        )

        preferences.togglePurpose(.saveShoppingTime)
        preferences.togglePurpose(.eatHealthier)

        XCTAssertEqual(
            preferences.selectedPurposes,
            [.saveMoney, .findProductsFaster, .eatHealthier]
        )
    }

    func testRecipeProducesCookableStepsAndTotalTime() {
        let recipe = RecipeInfo(
            ingredients: [
                RecipeIngredient(name: "Garlic", quantity: "2 cloves", category: "Produce"),
            ],
            instructionsBrief: "Chop the garlic. Cook gently until fragrant.",
            prepTimeMin: 5,
            cookTimeMin: 12,
            method: nil,
            serves: 2
        )

        XCTAssertEqual(recipe.steps, ["Chop the garlic.", "Cook gently until fragrant."])
        XCTAssertEqual(recipe.totalTimeMin, 17)
        XCTAssertEqual(recipe.normalized(fallbackCookTimeMin: 20).cookTimeMin, 12)
    }

    func testRecipeUsesFallbackCookTimeWhenMissing() {
        let recipe = RecipeInfo(
            ingredients: [],
            instructionsBrief: "Mix and serve.",
            prepTimeMin: 4,
            cookTimeMin: nil,
            method: nil,
            serves: 2
        )

        let normalized = recipe.normalized(fallbackCookTimeMin: 16)
        XCTAssertEqual(normalized.cookTimeMin, 16)
        XCTAssertEqual(normalized.totalTimeMin, 20)
    }

    func testUserFacingCopyRemovesInternalServiceNames() {
        XCTAssertEqual(
            ReasiUserFacingCopy.text("Supabase Edge Function failed"),
            "Reasi failed"
        )
        XCTAssertEqual(
            ReasiUserFacingCopy.sourceName(
                "OpenAI web result",
                sourceURL: URL(string: "https://www.coles.com.au/product/example")
            ),
            "coles.com.au"
        )
        XCTAssertEqual(ReasiUserFacingCopy.sourceName("PostHog", sourceURL: nil), "Reasi")
    }

    func testAssistantResponseDecodesAppliedListMutations() throws {
        let data = Data(#"""
        {
          "threadId": "thread-1",
          "message": {
            "id": "message-1",
            "role": "assistant",
            "content": "Added bananas. Removed milk.",
            "cards": [],
            "caveats": [],
            "createdAt": null
          },
          "mutations": [
            {"operation":"add","itemId":"item-2","name":"Bananas","quantity":"6","checked":false,"sectionLabel":"Fresh Produce","sectionSortKey":10,"sectionType":"perimeter","aisleLabel":null},
            {"operation":"delete","itemId":"item-1","name":"Milk","quantity":null,"checked":null}
          ]
        }
        """#.utf8)

        let response = try JSONDecoder().decode(AssistantResponse.self, from: data)
        XCTAssertEqual(response.appliedMutations.map(\.operation), ["add", "delete"])
        XCTAssertEqual(response.appliedMutations.first?.quantity, "6")
        XCTAssertEqual(response.appliedMutations.first?.sectionLabel, "Fresh Produce")
        XCTAssertEqual(response.appliedMutations.first?.sectionType, .perimeter)
    }

    func testAssistantResponseWithoutMutationsRemainsBackwardsCompatible() throws {
        let data = Data(#"""
        {
          "threadId": "thread-1",
          "message": {
            "id": "message-1",
            "role": "assistant",
            "content": "Aisle 4.",
            "cards": [],
            "caveats": [],
            "createdAt": null
          }
        }
        """#.utf8)

        let response = try JSONDecoder().decode(AssistantResponse.self, from: data)
        XCTAssertTrue(response.appliedMutations.isEmpty)
    }

    func testLaunchStoreRegistryContainsExactlyFiveUniqueSupportedStores() {
        let stores = FixtureStores.launchStores
        let expectedIDs: Set<StoreID> = [
            .topRyde,
            .eastVillage,
            .rhodes,
            .surryHills,
            .woolworthsRhodes,
        ]

        XCTAssertEqual(stores.count, 5)
        XCTAssertEqual(Set(stores.map(\.id)), expectedIDs)
        XCTAssertEqual(stores.map(\.id).count, Set(stores.map(\.id)).count)
        XCTAssertEqual(stores.filter { $0.retailer == "coles" }.count, 4)
        XCTAssertEqual(stores.filter { $0.retailer == "woolworths" }.count, 1)
    }

    func testGenerationStagesMapToStableUserFacingProgress() {
        XCTAssertEqual(WeekPlanGenerationStage(serverStage: .preparing), .preparing)
        XCTAssertEqual(WeekPlanGenerationStage(serverStage: .planningMeals), .planningMeals)
        XCTAssertEqual(
            WeekPlanGenerationStage(serverStage: .organizingStoreRoute),
            .organizingStoreRoute
        )
        XCTAssertEqual(WeekPlanGenerationStage(serverStage: .ready), .ready)
        XCTAssertEqual(WeekPlanGenerationStage(serverStage: .failed), .ready)
    }

    func testPlanBriefRoundTripsOccasionDateAsISO8601() throws {
        let date = Date(timeIntervalSince1970: 1_788_000_000)
        let brief = PlanBrief(
            kind: .occasion,
            entryMethod: .describe,
            briefText: "Romantic dinner for two",
            serves: 2,
            occasionAt: date,
            budgetTargetAud: 90,
            desiredCount: 4,
            ideas: [PlanIdea(type: .dish, title: "Flan")]
        )

        let data = try JSONEncoder().encode(brief)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(try XCTUnwrap(json["occasionAt"] as? String).contains("T"))
        XCTAssertEqual(json["desiredMealCount"] as? Int, 4)
        XCTAssertNil(json["desiredCount"])
        let encodedIdeas = try XCTUnwrap(json["ideas"] as? [[String: Any]])
        XCTAssertEqual(encodedIdeas.first?["mustKeep"] as? Bool, true)

        let decoded = try JSONDecoder().decode(PlanBrief.self, from: data)
        XCTAssertEqual(decoded.kind, .occasion)
        XCTAssertEqual(
            try XCTUnwrap(decoded.occasionAt).timeIntervalSince1970,
            date.timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testProductIdeaDefaultsToUseInPlan() {
        let idea = PlanIdea(type: .product, title: "Salmon fillets")
        XCTAssertEqual(idea.productRole, .useInPlan)
    }

    func testPreviouslyCachedWeekPlanDecodesWithoutNewMetadata() throws {
        let data = try JSONEncoder().encode(FixtureWeekPlan.current)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "kind")
        json.removeValue(forKey: "entryMethod")
        json.removeValue(forKey: "occasionAt")
        if var shoppingList = json["shoppingList"] as? [String: Any] {
            shoppingList.removeValue(forKey: "status")
            shoppingList.removeValue(forKey: "completedAt")
            json["shoppingList"] = shoppingList
        }

        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(WeekPlan.self, from: legacyData)
        XCTAssertEqual(decoded.kind, .week)
        XCTAssertNil(decoded.entryMethod)
        XCTAssertEqual(decoded.id, FixtureWeekPlan.current.id)
    }

    func testBudgetCoverageExcludesAlreadyOwnedProductsAndNeverGuessesMissingPrice() {
        let priced = fixtureProduct(name: "Pasta", price: 4.50)
        let owned = fixtureProduct(name: "Olive oil", price: 12)
        let unknown = fixtureProduct(name: "Fresh herbs", price: nil)
        let coverage = PlanBudgetCoverage(ideas: [
            PlanIdea(type: .product, title: priced.name, product: priced, productRole: .useInPlan),
            PlanIdea(type: .product, title: owned.name, product: owned, productRole: .alreadyHave),
            PlanIdea(type: .product, title: unknown.name, product: unknown, productRole: .addToList),
            PlanIdea(type: .dish, title: "Flan"),
        ])

        XCTAssertEqual(coverage.knownSubtotalAud, 4.50, accuracy: 0.001)
        XCTAssertEqual(coverage.pricedProductCount, 1)
        XCTAssertEqual(coverage.eligibleProductCount, 2)
        XCTAssertEqual(coverage.fraction, 0.5, accuracy: 0.001)
    }

    func testInterpretationCapsAlternativeSwapsAtTwo() {
        let swaps = (1...4).map {
            PlanGapRecommendation(title: "Option \($0)", reason: "Reason", courseRole: "entree")
        }
        let interpretation = PlanInterpretation(
            normalizedBrief: nil,
            clarification: "Choose one main",
            recommendation: swaps.first,
            swaps: swaps,
            notes: []
        )
        XCTAssertEqual(interpretation.swaps.count, 2)
    }

    func testInterpretationDecodesBackendClarificationAndAlternatives() throws {
        let data = Data(#"""
        {
          "normalizedBrief": {
            "version": 1,
            "kind": "occasion",
            "entryMethod": "describe",
            "briefText": "Romantic dinner",
            "serves": 2,
            "occasionAt": null,
            "budgetTargetAud": 80,
            "desiredMealCount": 4,
            "ideas": [
              {
                "id": "flan",
                "type": "dish",
                "title": "Flan",
                "detail": null,
                "sourceUrl": null,
                "uploadPath": null,
                "mustKeep": true,
                "productRole": null,
                "courseHint": "dessert"
              }
            ]
          },
          "clarification": {
            "question": "Keep both dishes as full mains?",
            "options": ["Keep both as mains", "Make one a smaller course"]
          },
          "recommendation": {
            "courseRole": "starter",
            "title": "Tomato crostini",
            "reason": "Fresh and quick."
          },
          "alternatives": [
            {"courseRole":"starter","title":"Salad","reason":"Light."},
            {"courseRole":"starter","title":"Soup","reason":"Make ahead."}
          ],
          "budgetNote": "Price coverage depends on matched products."
        }
        """#.utf8)

        let result = try JSONDecoder().decode(PlanInterpretation.self, from: data)
        XCTAssertEqual(result.normalizedBrief?.desiredCount, 4)
        XCTAssertEqual(result.normalizedBrief?.ideas.first?.isRequired, true)
        XCTAssertEqual(result.clarification, "Keep both dishes as full mains?")
        XCTAssertEqual(result.clarificationOptions.count, 2)
        XCTAssertEqual(result.swaps.map(\.title), ["Salad", "Soup"])
        XCTAssertEqual(result.notes, ["Price coverage depends on matched products."])
    }

    func testMealIdeaResponseDecodesStructuredRecipeWrapper() throws {
        let data = Data(#"""
        {
          "status": "resolved",
          "source": "structured_data",
          "idea": {
            "title": "Classic flan",
            "description": "A caramel custard.",
            "imageUrl": "https://example.com/flan.jpg",
            "ingredients": ["4 eggs", "500 ml milk"],
            "method": ["Make caramel.", "Bake the custard."],
            "prepTimeMin": 15,
            "cookTimeMin": 45,
            "serves": 6,
            "sourceName": "example.com",
            "sourceUrl": "https://example.com/flan",
            "capturedAt": "2026-08-28T00:00:00Z",
            "confidence": "high",
            "confidenceReason": "Published recipe data.",
            "priceAud": null,
            "budgetNote": "No current price."
          }
        }
        """#.utf8)

        let response = try JSONDecoder().decode(ResolveMealIdeaResponse.self, from: data)
        let resolved = try XCTUnwrap(response.idea?.resolved)
        XCTAssertEqual(resolved.title, "Classic flan")
        XCTAssertEqual(resolved.recipe?.ingredients.count, 2)
        XCTAssertEqual(resolved.recipe?.totalTimeMin, 60)
        XCTAssertEqual(resolved.confidence, .high)
    }

    func testInterpretationKeepsSourceBackedRecipeEvidence() {
        let original = PlanBrief(
            kind: .occasion,
            entryMethod: .build,
            ideas: [PlanIdea(
                id: "flan",
                type: .dish,
                title: "Classic flan",
                detail: "Ingredients: eggs, milk, sugar. About 60 minutes",
                sourceURL: URL(string: "https://example.com/flan"),
                courseHint: "dessert"
            )]
        )
        let interpreted = PlanBrief(
            kind: .occasion,
            entryMethod: .build,
            ideas: [PlanIdea(
                id: "flan",
                type: .dish,
                title: "Classic flan",
                detail: "AI summary"
            )]
        )

        let merged = interpreted.mergingClientMetadata(from: original)
        XCTAssertEqual(merged.ideas.first?.detail, original.ideas.first?.detail)
        XCTAssertEqual(merged.ideas.first?.sourceURL, original.ideas.first?.sourceURL)
        XCTAssertEqual(merged.ideas.first?.courseHint, "dessert")
    }

    @MainActor
    func testPlanBuilderDraftRestoresPerUserAndClearsExplicitly() {
        let userId = "test-\(UUID().uuidString)"
        let first = PlanBuilderStore()
        first.activate(userId: userId)
        first.update(PlanBrief(kind: .occasion, entryMethod: .build, briefText: "Dinner", serves: 2))

        let restored = PlanBuilderStore()
        restored.activate(userId: userId)
        XCTAssertEqual(restored.draft?.briefText, "Dinner")
        XCTAssertEqual(restored.draft?.kind, .occasion)

        restored.discard()
        let afterDiscard = PlanBuilderStore()
        afterDiscard.activate(userId: userId)
        XCTAssertNil(afterDiscard.draft)
    }

    @MainActor
    func testReasiProContractIdentifiersMatchBackendContract() {
        let entitlementId = RevenueCatService.entitlementId
        let offeringId = RevenueCatService.offeringId
        let weeklyProductId = RevenueCatService.weeklyProductId
        let monthlyProductId = RevenueCatService.monthlyProductId
        let annualProductId = RevenueCatService.annualProductId

        XCTAssertEqual(entitlementId, "reasi_pro")
        XCTAssertEqual(offeringId, "default")
        XCTAssertEqual(weeklyProductId, "ai.reasi.pro.weekly")
        XCTAssertEqual(monthlyProductId, "ai.reasi.pro.monthly")
        XCTAssertEqual(annualProductId, "ai.reasi.pro.annual")
    }

    func testReasiProPlanKindsExposeLaunchBillingLabelsAndOrder() {
        XCTAssertEqual(ReasiProPlanKind.weekly.title, "Weekly")
        XCTAssertEqual(ReasiProPlanKind.weekly.billingLabel, "per week")
        XCTAssertEqual(ReasiProPlanKind.displayOrder, [.annual, .monthly, .weekly])
    }

    func testRevenueCatKeyValidationRejectsUnsafeReleaseKeys() {
        XCTAssertFalse(ReasiConfig.isValidRevenueCatPublicKey("", allowTestStore: false))
        XCTAssertFalse(ReasiConfig.isValidRevenueCatPublicKey("test_example", allowTestStore: false))
        XCTAssertFalse(ReasiConfig.isValidRevenueCatPublicKey("sk_example", allowTestStore: false))
        XCTAssertTrue(ReasiConfig.isValidRevenueCatPublicKey("appl_example", allowTestStore: false))
        XCTAssertTrue(ReasiConfig.isValidRevenueCatPublicKey("test_example", allowTestStore: true))
    }

    func testBasketPriceSummarySeparatesCheckedBasketFromPlannedCoverage() {
        let items = [
            ShoppingListItem(
                id: "actual",
                name: "Pasta sauce",
                quantity: "1 jar",
                checked: true,
                aisleLabel: "Aisle 10",
                sectionType: .numbered,
                product: ProductSnapshot(
                    sku: "sauce",
                    productName: "Pasta sauce",
                    brand: nil,
                    size: "500 g",
                    priceAud: 5,
                    imageUrl: nil,
                    capturedAt: "2026-08-28",
                    actualPriceAud: 4.50
                )
            ),
            ShoppingListItem(
                id: "catalog",
                name: "Chocolate",
                quantity: "1 block",
                checked: false,
                aisleLabel: "Aisle 6",
                sectionType: .numbered,
                product: ProductSnapshot(
                    sku: "chocolate",
                    productName: "Chocolate",
                    brand: nil,
                    size: "180 g",
                    priceAud: 3.20,
                    imageUrl: nil,
                    capturedAt: "2026-08-27"
                )
            ),
            ShoppingListItem(
                id: "unknown",
                name: "Fresh herbs",
                quantity: "1 bunch",
                checked: true,
                aisleLabel: "Fresh Produce",
                sectionType: .perimeter,
                product: nil
            ),
        ]

        let summary = BasketPriceSummary(items: items)
        XCTAssertEqual(summary.inBasketTotalAud, 4.50, accuracy: 0.001)
        XCTAssertEqual(summary.plannedTotalAud, 7.70, accuracy: 0.001)
        XCTAssertEqual(summary.pricedItemCount, 2)
        XCTAssertEqual(summary.pricedCheckedItemCount, 1)
        XCTAssertEqual(summary.unpricedCheckedItemCount, 1)
        XCTAssertEqual(summary.coverageFraction, 2.0 / 3.0, accuracy: 0.001)
    }

    func testShoppingCompletionPayloadIncludesEveryVisibleCheckState() throws {
        let shoppingList = FixtureWeekPlan.current.shoppingList
        let items = shoppingList.sections.flatMap(\.items)
        let checkedID = try XCTUnwrap(items.first?.id)

        let payload = ShoppingCompletionPayload(
            shoppingList: shoppingList,
            checkedItemIDs: [checkedID]
        )

        XCTAssertEqual(payload.shoppingListId, shoppingList.id)
        XCTAssertEqual(payload.expectedStoreId, shoppingList.storeId)
        XCTAssertEqual(payload.checkedStates.count, items.count)
        XCTAssertEqual(payload.checkedStates[checkedID], true)
        XCTAssertTrue(
            items.dropFirst().allSatisfy { payload.checkedStates[$0.id] == false }
        )

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload))
        let object = try XCTUnwrap(encoded as? [String: Any])
        XCTAssertEqual(object["shoppingListId"] as? String, shoppingList.id)
        XCTAssertEqual((object["checkedStates"] as? [String: Bool])?[checkedID], true)
    }

    func testShoppingCheckReconciliationDropsInvisiblePendingItems() {
        let reconciliation = ShoppingCheckStateReconciliation(
            visibleItemIDs: ["visible-item"],
            pendingItemIDs: ["visible-item", "deleted-item"],
            states: ["visible-item": true, "deleted-item": true]
        )

        XCTAssertEqual(reconciliation.pendingItemIDs, ["visible-item"])
        XCTAssertEqual(reconciliation.states, ["visible-item": true])
    }

    func testMealImageRefreshOnlyAddsImageMetadata() {
        let original = FixtureWeekPlan.current.meals[0]
        let refreshed = MealSummary(
            id: original.id,
            day: original.day,
            dish: original.dish,
            description: "Changed remotely",
            cuisine: original.cuisine,
            cookTimeMin: original.cookTimeMin,
            costAud: original.costAud,
            estimatedProteinG: original.estimatedProteinG,
            estimatedCalories: original.estimatedCalories,
            estimatedCarbsG: original.estimatedCarbsG,
            tone: original.tone,
            recipe: nil,
            imageUrl: URL(string: "https://images.example.com/meal.jpg"),
            imageSourceName: "Photo source"
        )

        let merged = original.withImageMetadata(from: refreshed)
        XCTAssertEqual(merged.imageUrl, refreshed.imageUrl)
        XCTAssertEqual(merged.imageSourceName, "Photo source")
        XCTAssertEqual(merged.description, original.description)
        XCTAssertEqual(merged.recipe, original.recipe)
    }

    func testSpendingDashboardKeepsActiveBasketOutOfCompletedSpend() throws {
        let data = Data(#"""
        {
          "period": "week",
          "startDate": "2026-08-31",
          "endDateExclusive": "2026-09-07",
          "currency": "AUD",
          "completedSpendAud": 67,
          "trackedItemSpendAud": 65,
          "checkoutDifferenceAud": 2,
          "weeklyBudgetAud": 100,
          "budgetRemainingAud": 33,
          "priceCoverage": 0.8,
          "checkedItems": 5,
          "pricedCheckedItems": 4,
          "plannedSpendAud": 55,
          "addedSpendAud": 10,
          "categories": [{"label":"Protein","amountAud":55}],
          "trend": [{"weekStart":"2026-08-31","amountAud":67}],
          "averageWeeklySpendAud": null,
          "activeBasket": {
            "shoppingListId": "active-list",
            "projectedTotalAud": 24,
            "pricedItems": 3,
            "totalItems": 4
          },
          "recentTrips": [],
          "insightStatus": "completed",
          "insightCards": [],
          "timezone": "Australia/Sydney",
          "coachTone": "supportive"
        }
        """#.utf8)

        let dashboard = try JSONDecoder().decode(SpendingDashboard.self, from: data)
        XCTAssertEqual(dashboard.completedSpendAud, 67)
        XCTAssertEqual(dashboard.activeBasket?.projectedTotalAud, 24)
        XCTAssertEqual(dashboard.budgetRemainingAud, 33)
        XCTAssertEqual(dashboard.period, .week)
    }

    func testSpendCategoryBreakdownKeepsTopFourAndCombinesTheRest() {
        let breakdown = SpendCategoryBreakdown(categories: [
            SpendingCategoryAmount(label: "Frozen", amountAud: 5),
            SpendingCategoryAmount(label: "Protein", amountAud: 40),
            SpendingCategoryAmount(label: "Drinks", amountAud: 3),
            SpendingCategoryAmount(label: "Produce", amountAud: 30),
            SpendingCategoryAmount(label: "Dairy & eggs", amountAud: 10),
            SpendingCategoryAmount(label: "Pantry", amountAud: 20),
        ])

        XCTAssertEqual(breakdown.slices.map(\.label), [
            "Protein",
            "Produce",
            "Pantry",
            "Dairy & eggs",
            "Other",
        ])
        XCTAssertEqual(breakdown.slices.map(\.amountAud), [40, 30, 20, 10, 8])
        XCTAssertEqual(breakdown.totalAud, 108, accuracy: 0.001)
    }

    func testSpendCategoryBreakdownKeepsCombinedOtherInDescendingOrder() {
        let breakdown = SpendCategoryBreakdown(categories: [
            SpendingCategoryAmount(label: "Protein", amountAud: 40),
            SpendingCategoryAmount(label: "Produce", amountAud: 30),
            SpendingCategoryAmount(label: "Pantry", amountAud: 20),
            SpendingCategoryAmount(label: "Dairy & eggs", amountAud: 10),
            SpendingCategoryAmount(label: "Frozen", amountAud: 9),
            SpendingCategoryAmount(label: "Drinks", amountAud: 8),
        ])

        XCTAssertEqual(
            breakdown.slices.map(\.label),
            ["Protein", "Produce", "Pantry", "Other", "Dairy & eggs"]
        )
        XCTAssertEqual(breakdown.slices.map(\.amountAud), [40, 30, 20, 17, 10])
    }

    func testSpendCategoryBreakdownPreservesTotalOrderAndPercentages() {
        let breakdown = SpendCategoryBreakdown(categories: [
            SpendingCategoryAmount(label: "Produce", amountAud: 25),
            SpendingCategoryAmount(label: "Protein", amountAud: 50),
            SpendingCategoryAmount(label: "Pantry", amountAud: 25),
        ])

        XCTAssertEqual(breakdown.slices.map(\.label), ["Protein", "Pantry", "Produce"])
        XCTAssertEqual(breakdown.totalAud, 100, accuracy: 0.001)
        XCTAssertEqual(breakdown.slices.reduce(0) { $0 + $1.fraction }, 1, accuracy: 0.001)
        XCTAssertEqual(breakdown.slices[0].fraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(breakdown.slices[0].angleRange.lowerBound, 0, accuracy: 0.001)
        XCTAssertEqual(breakdown.slices[0].angleRange.upperBound, 180, accuracy: 0.001)
        XCTAssertEqual(breakdown.slices.last?.angleRange.upperBound ?? 0, 360, accuracy: 0.001)
    }

    func testSpendCategoryBreakdownDropsUnavailableAmounts() {
        let breakdown = SpendCategoryBreakdown(categories: [
            SpendingCategoryAmount(label: "Produce", amountAud: 0),
            SpendingCategoryAmount(label: "Protein", amountAud: -4),
        ])

        XCTAssertTrue(breakdown.slices.isEmpty)
        XCTAssertEqual(breakdown.totalAud, 0)
        XCTAssertNil(breakdown.slice(atCumulativeValue: 1))
    }

    func testSpendCategoryBreakdownUsesStableCategoryColours() {
        let first = SpendCategoryBreakdown(categories: [
            SpendingCategoryAmount(label: "Produce", amountAud: 10),
            SpendingCategoryAmount(label: "Protein", amountAud: 20),
        ])
        let second = SpendCategoryBreakdown(categories: [
            SpendingCategoryAmount(label: "Protein", amountAud: 5),
            SpendingCategoryAmount(label: "Produce", amountAud: 50),
        ])

        XCTAssertEqual(first.slices.first(where: { $0.label == "Produce" })?.colorRole, .produce)
        XCTAssertEqual(second.slices.first(where: { $0.label == "Produce" })?.colorRole, .produce)
        XCTAssertEqual(first.slices.first(where: { $0.label == "Protein" })?.colorRole, .protein)
        XCTAssertEqual(second.slices.first(where: { $0.label == "Protein" })?.colorRole, .protein)
    }

    func testSpendCategoryBreakdownResolvesChartSelection() {
        let breakdown = SpendCategoryBreakdown(categories: [
            SpendingCategoryAmount(label: "Protein", amountAud: 60),
            SpendingCategoryAmount(label: "Produce", amountAud: 40),
        ])

        XCTAssertEqual(breakdown.slice(atCumulativeValue: 30)?.label, "Protein")
        XCTAssertEqual(breakdown.slice(atCumulativeValue: 80)?.label, "Produce")
        XCTAssertNil(breakdown.slice(atCumulativeValue: nil))
        XCTAssertNil(breakdown.slice(atCumulativeValue: 101))
    }

    func testSpendCategorySelectionStaysWithStableCategoryAfterReordering() {
        let original = SpendCategoryBreakdown(categories: [
            SpendingCategoryAmount(label: "Protein", amountAud: 60),
            SpendingCategoryAmount(label: "Produce", amountAud: 40),
        ])
        let selectedID = original.slices.first(where: { $0.label == "Produce" })?.id

        let refreshed = SpendCategoryBreakdown(categories: [
            SpendingCategoryAmount(label: "Protein", amountAud: 35),
            SpendingCategoryAmount(label: "Produce", amountAud: 65),
        ])

        XCTAssertEqual(refreshed.slice(id: selectedID)?.label, "Produce")
        XCTAssertEqual(refreshed.slice(id: selectedID)?.amountAud ?? 0, 65, accuracy: 0.001)
    }

    func testSpendingTripDetailUsesConfirmedTotalAndKeepsCheckoutDifference() throws {
        let data = Data(#"""
        {
          "trip": {
            "id": "trip-1",
            "shoppingListId": "list-1",
            "storeId": "top_ryde",
            "storeName": "Coles Top Ryde",
            "completedAt": "2026-09-02T08:00:00.000Z",
            "knownBasketTotalAud": 42,
            "confirmedTotalAud": 45,
            "checkedItems": 4,
            "pricedCheckedItems": 3,
            "trackedTotalAud": 42,
            "effectiveTotalAud": 45,
            "checkoutDifferenceAud": 3,
            "priceCoverage": 0.75,
            "weeklyBudgetAud": 100,
            "weeklySpendAud": 45,
            "weeklyBudgetRemainingAud": 55
          },
          "categories": [{"label":"Protein","amountAud":20}],
          "plannedSpendAud": 30,
          "addedSpendAud": 12,
          "insightStatus": "pending",
          "insightCards": [],
          "items": []
        }
        """#.utf8)

        let detail = try JSONDecoder().decode(SpendingTripDetail.self, from: data)
        XCTAssertEqual(detail.trip.effectiveTotalAud, 45)
        XCTAssertEqual(detail.trip.checkoutDifferenceAud, 3)
        XCTAssertEqual(detail.trip.priceCoverage, 0.75)
    }

    func testLegacyOnboardingPreferencesDefaultToSupportiveSpendingCoach() throws {
        let data = Data(#"""
        {
          "purpose": null,
          "purposePriorities": [],
          "household": "two",
          "foodStyles": [],
          "selectedStoreId": "top_ryde",
          "completedAt": null
        }
        """#.utf8)

        let preferences = try JSONDecoder().decode(OnboardingPreferences.self, from: data)
        XCTAssertEqual(preferences.spendingCoachTone, .supportive)
        XCTAssertNil(preferences.weeklyGroceryBudgetAud)
    }

    func testProductSnapshotPreservesCatalogCategoryForTripAnalytics() {
        var candidate = fixtureProduct(name: "Greek yoghurt", price: 6.50)
        candidate.categoryGroup = "Dairy, Eggs & Fridge"
        candidate.category = "Yoghurt"
        candidate.subCategory = "Greek yoghurt"

        let snapshot = ProductSnapshot(candidate: candidate)
        XCTAssertEqual(snapshot.categoryGroup, "Dairy, Eggs & Fridge")
        XCTAssertEqual(snapshot.category, "Yoghurt")
        XCTAssertEqual(snapshot.subCategory, "Greek yoghurt")
    }

    func testSpendingCacheRestoresPerUserWithoutCrossAccountLeakage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reasi-spending-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = SpendingLocalCache(directoryURL: directory)
        cache.saveDashboard(.uiTestFixture, userId: "user-a")
        cache.saveTrip(.uiTestFixture, userId: "user-a")

        XCTAssertEqual(cache.loadDashboard(userId: "user-a", period: .week), .uiTestFixture)
        XCTAssertEqual(cache.loadTrip(userId: "user-a", tripId: "ui-test-trip"), .uiTestFixture)
        XCTAssertNil(cache.loadDashboard(userId: "user-b", period: .week))
        XCTAssertNil(cache.loadTrip(userId: "user-b", tripId: "ui-test-trip"))
    }

    func testProductSelectionPricesAllRequiredPacksAndPreservesPricingMetadata() throws {
        let candidate = fixtureProduct(name: "Chicken thigh fillets", price: 7, size: "500g")
        let item = ShoppingListItem(id: "chicken", name: "Chicken thigh fillets", quantity: "1100 g", checked: false, aisleLabel: nil, sectionType: .unknown, product: nil)
        let product = ProductPurchaseEstimate.snapshot(candidate: candidate, item: item)
        XCTAssertEqual(product.purchaseQuantity, 3)
        XCTAssertEqual(product.priceAud, 21)
        XCTAssertEqual(product.unitPriceAud, 7)
        let restored = try JSONDecoder().decode(ProductSnapshot.self, from: JSONEncoder().encode(product))
        XCTAssertEqual(restored.purchaseQuantity, 3)
        XCTAssertEqual(restored.requiredAmount, 1100)
    }

    func testProductSelectionDoesNotGuessQuantityOrMixWeightAndCount() {
        XCTAssertNil(ProductPurchaseEstimate(quantity: "a small knob"))
        let each = ProductPurchaseEstimate(quantity: "2 each")
        XCTAssertNil(each?.packCount(for: fixtureProduct(name: "Brown onions", price: 2.5, size: "1kg")))
        let weight = ProductPurchaseEstimate(quantity: "1 kg")
        XCTAssertEqual(weight?.packCount(for: fixtureProduct(name: "Tomatoes", price: 5, size: "2 x 400g")), 2)
    }

    func testProductSwapChecksWholeBasketAgainstBudget() {
        let item = ShoppingListItem(id: "rice", name: "Rice", quantity: "1000 g", checked: false, aisleLabel: nil, sectionType: .unknown, product: nil)
        let product = ProductPurchaseEstimate.snapshot(candidate: fixtureProduct(name: "Rice", price: 4, size: "500g"), item: item)
        let basket = BasketPriceSummary(items: [item])
        XCTAssertNotNil(basket.issueReplacing(item, with: product, budget: 7))
        XCTAssertNil(basket.issueReplacing(item, with: product, budget: 8))
        let unpriced = ProductPurchaseEstimate.snapshot(candidate: fixtureProduct(name: "Rice", price: nil, size: "500g"), item: item)
        XCTAssertNotNil(basket.issueReplacing(item, with: unpriced, budget: 8))
    }

    func testLegacyShoppingQuantitiesUseExplicitMeasuresWithoutGuessing() {
        let labels: [(String, Double, String)] = [
            ("1 small pack, about 300g", 300, "g"), ("250ml bottle", 250, "ml"),
            ("1 small knob, about 80g", 80, "g"), ("2 x 400g", 800, "g"),
            ("2 medium", 2, "each"), ("1 large head", 1, "each"), ("1 bulb", 1, "each")
        ]
        for (label, amount, unit) in labels {
            let parsed = ProductPurchaseEstimate(shoppingQuantity: label, ingredientName: "Vegetables")
            XCTAssertEqual(parsed?.amount, amount, label)
            XCTAssertEqual(parsed?.unit, unit, label)
        }
        for label in ["a handful", "2 cups", "200g or 400g", "200–300g", "2 400g cans", "500 g + 1 pack", "200g per person"] {
            XCTAssertNil(ProductPurchaseEstimate(shoppingQuantity: label, ingredientName: "Tomatoes"), label)
        }
    }

    func testAutomaticProductChoiceUsesRealRetailerIdentityAndWholePackCost() {
        let item = shoppingItem("soy", name: "Soy sauce", quantity: "250ml bottle")
        let small = catalogProduct(name: "Soy Sauce", price: 1.5, size: "100ml")
        let bottle = catalogProduct(name: "Soy Sauce", price: 2.8, size: "500ml")
        let otherRetailer = catalogProduct(name: "Soy Sauce", price: 1, size: "500ml", retailer: "woolworths")
        XCTAssertEqual(ShoppingProductMatcher.choose(for: item, candidates: [small, otherRetailer, bottle], storeId: .topRyde), bottle)
        XCTAssertEqual(ShoppingProductMatcher.choose(for: item, candidates: [bottle, otherRetailer], storeId: .woolworthsRhodes), otherRetailer)
        XCTAssertFalse(ShoppingProductMatcher.matches("Fresh ginger", candidate: catalogProduct(name: "Ginger Beer", price: 1, size: "375ml"), storeId: .topRyde))
        XCTAssertFalse(ShoppingProductMatcher.matches("Fresh ginger", candidate: catalogProduct(name: "Ginger Marmalade", price: 3.8, size: "375g"), storeId: .topRyde))
        XCTAssertTrue(ShoppingProductMatcher.matches("Fresh ginger", candidate: catalogProduct(name: "Ginger Loose", price: 4.29, size: "approx. 130g"), storeId: .topRyde))
        XCTAssertFalse(ShoppingProductMatcher.matches("Garlic", candidate: catalogProduct(name: "Crushed Garlic", price: 1, size: "200g"), storeId: .topRyde))
        XCTAssertFalse(ShoppingProductMatcher.matches("Pork mince", candidate: catalogProduct(name: "Pork & Beef Mince", price: 1, size: "500g"), storeId: .topRyde))
        XCTAssertNil(ShoppingProductMatcher.choose(for: item, candidates: [fixtureProduct(name: "Soy Sauce", price: 1, size: "500ml")], storeId: .topRyde))
    }

    @MainActor
    func testSavedListAutomaticallySelectsProductsPreservingChecksAndExistingChoices() async {
        let chosen = ProductSnapshot(candidate: catalogProduct(name: "Cornflour", price: 1.35, size: "300g"))
        let core = shoppingStore(items: [
            shoppingItem("pork", name: "Pork mince", quantity: "200g", checked: true),
            shoppingItem("corn", name: "Cornflour", quantity: "300g", product: chosen),
            shoppingItem("soy", name: "Soy sauce", quantity: "250ml bottle")
        ])
        var searches: [String] = []
        var saves: [AutomaticProductSelection] = []
        await core.resolveMissingShoppingProducts(search: { query, store in
            searches.append(query)
            XCTAssertEqual(store, .topRyde)
            return [self.catalogProduct(name: query, price: 3, size: query == "Pork mince" ? "500g" : "500ml")]
        }, save: { selection in saves.append(selection); return true })
        XCTAssertEqual(searches, ["Pork mince", "Soy sauce"])
        XCTAssertEqual(saves.count, 2)
        XCTAssertTrue(saves[0].item.checked)
        XCTAssertEqual(core.checkedItemIDs, ["pork"])
        XCTAssertEqual(core.allShoppingItems.map(\.id), ["pork", "corn", "soy"])
        XCTAssertEqual(core.allShoppingItems[1].product, chosen)
        XCTAssertTrue(core.allShoppingItems.allSatisfy { $0.product?.imageUrl != nil })
        XCTAssertEqual(core.allShoppingItems[0].product?.purchaseQuantity, 1)
        XCTAssertEqual(core.allShoppingItems[0].product?.priceAud, 3)
        await core.resolveMissingShoppingProducts(search: { _, _ in XCTFail("Already resolved"); return [] }, save: { _ in XCTFail(); return true })
    }

    @MainActor
    func testAutomaticSelectionDoesNotOverwriteAChoiceMadeDuringSearch() async {
        let item = shoppingItem("soy", name: "Soy sauce", quantity: "250ml bottle")
        let core = shoppingStore(items: [item])
        let manual = ProductSnapshot(candidate: catalogProduct(name: "Kikkoman Soy Sauce", price: 7.9, size: "600ml"))
        await core.resolveMissingShoppingProducts(search: { _, _ in
            core.plan.shoppingList.sections[0].items[0] = self.shoppingItem("soy", name: "Soy sauce", quantity: "250ml bottle", checked: true, product: manual)
            return [self.catalogProduct(name: "Soy Sauce", price: 1.9, size: "500ml")]
        }, save: { _ in XCTFail("Must preserve the customer's choice"); return true })
        XCTAssertEqual(core.allShoppingItems.first?.product, manual)
        XCTAssertEqual(core.allShoppingItems.first?.checked, true)
    }

    @MainActor
    func testAutomaticSelectionCannotApplyToAReplacedListOrFailedSave() async {
        let core = shoppingStore(items: [shoppingItem("soy", name: "Soy sauce", quantity: "250ml bottle")])
        let candidate = catalogProduct(name: "Soy Sauce", price: 1.9, size: "500ml")
        await core.resolveMissingShoppingProducts(search: { _, _ in
            core.plan = FixtureWeekPlan.plan(for: .init(id: .woolworthsRhodes, retailer: "woolworths", name: "Woolworths", shortName: "Woolies"))
            return [candidate]
        }, save: { _ in XCTFail("The store changed"); return true })
        XCTAssertFalse(core.isMatchingShoppingProducts)

        let failed = shoppingStore(items: [shoppingItem("soy", name: "Soy sauce", quantity: "250ml bottle")])
        await failed.resolveMissingShoppingProducts(search: { _, _ in [candidate] }, save: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertNil(failed.allShoppingItems.first?.product)
        XCTAssertNotNil(failed.shoppingProductMessage)
        await failed.resolveMissingShoppingProducts(search: { _, _ in [candidate] }, save: { _ in true })
        XCTAssertEqual(failed.allShoppingItems.first?.product?.sku, candidate.sku)
        XCTAssertNil(failed.shoppingProductMessage)
    }

    @MainActor
    func testAutomaticSelectionKeepsCheckChangesMadeWhileSaving() async {
        let core = shoppingStore(items: [shoppingItem("soy", name: "Soy sauce", quantity: "250ml bottle")])
        await core.resolveMissingShoppingProducts(search: { _, _ in
            [self.catalogProduct(name: "Soy Sauce", price: 1.9, size: "500ml")]
        }, save: { _ in
            core.plan.shoppingList.sections[0].items[0].checked = true
            core.checkedItemIDs.insert("soy")
            return true
        })
        XCTAssertEqual(core.allShoppingItems.first?.checked, true)
        XCTAssertEqual(core.checkedItemIDs, ["soy"])
        XCTAssertNotNil(core.allShoppingItems.first?.product)
    }

    @MainActor
    func testCancelledProductSearchNeverSavesItsResult() async {
        let core = shoppingStore(items: [shoppingItem("soy", name: "Soy sauce", quantity: "250ml bottle")])
        let task = Task { @MainActor in
            await core.resolveMissingShoppingProducts(search: { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return [self.catalogProduct(name: "Soy Sauce", price: 1.9, size: "500ml")]
            }, save: { _ in XCTFail("Cancelled search must not save"); return true })
        }
        await task.value
        XCTAssertNil(core.allShoppingItems.first?.product)
        XCTAssertFalse(core.isMatchingShoppingProducts)
        XCTAssertNil(core.shoppingProductMessage)
    }

    @MainActor
    func testAutomaticSelectionRespectsBudgetAndDoesNotInventUnmatchedProducts() async {
        let core = shoppingStore(items: [shoppingItem("soy", name: "Soy sauce", quantity: "250ml bottle")])
        core.plan.budgetTargetAud = 2
        await core.resolveMissingShoppingProducts(search: { _, _ in [self.catalogProduct(name: "Soy Sauce", price: 3, size: "500ml")] }, save: { _ in XCTFail("Over budget"); return true })
        XCTAssertNil(core.allShoppingItems.first?.product)
        XCTAssertTrue(core.shoppingProductMessage?.contains("budget") == true)

        let unmatched = shoppingStore(items: [shoppingItem("ginger", name: "Fresh ginger", quantity: "80g")])
        await unmatched.resolveMissingShoppingProducts(search: { _, _ in [self.catalogProduct(name: "Ginger Beer", price: 1, size: "375ml")] }, save: { _ in XCTFail("Not the requested ingredient"); return true })
        XCTAssertNil(unmatched.allShoppingItems.first?.product)
        XCTAssertNotNil(unmatched.shoppingProductMessage)
    }

    private func shoppingItem(_ id: String, name: String, quantity: String, checked: Bool = false, product: ProductSnapshot? = nil) -> ShoppingListItem {
        ShoppingListItem(id: id, name: name, quantity: quantity, checked: checked, aisleLabel: nil, sectionType: .unknown, product: product)
    }

    @MainActor
    private func shoppingStore(items: [ShoppingListItem]) -> CoreLoopStore {
        var plan = FixtureWeekPlan.current
        plan.shoppingList.sections = [ShoppingListSection(label: "Groceries", sortKey: 1, type: .unknown, items: items)]
        return CoreLoopStore(plan: plan)
    }

    private func catalogProduct(name: String, price: Double, size: String, retailer: String = "coles") -> ProductCandidate {
        fixtureProduct(name: name, price: price, size: size, retailer: retailer)
    }

    private func fixtureProduct(name: String, price: Double?, size: String? = nil, retailer: String? = nil) -> ProductCandidate {
        ProductCandidate(
            observationId: UUID().uuidString,
            name: name,
            brand: nil,
            size: size,
            priceAud: price,
            unitPriceAud: nil,
            unitQuantity: nil,
            unitMeasure: nil,
            comparablePrice: nil,
            imageUrl: retailer == nil ? nil : URL(string: "https://example.com/product.jpg"),
            productUrl: nil,
            sourceName: retailer ?? "Test catalog",
            sourceUrl: nil,
            capturedAt: nil,
            freshnessLabel: "Test",
            confidence: .high,
            confidenceReason: "Test fixture",
            uncertaintyText: price == nil ? "Price not known" : "",
            sku: retailer == nil ? nil : UUID().uuidString,
            retailer: retailer
        )
    }
}
