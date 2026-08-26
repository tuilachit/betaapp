import XCTest
@testable import Reasi

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

    @MainActor
    func testReasiProContractIdentifiersMatchBackendContract() {
        let entitlementId = RevenueCatService.entitlementId
        let offeringId = RevenueCatService.offeringId
        let monthlyProductId = RevenueCatService.monthlyProductId
        let annualProductId = RevenueCatService.annualProductId

        XCTAssertEqual(entitlementId, "reasi_pro")
        XCTAssertEqual(offeringId, "default")
        XCTAssertEqual(monthlyProductId, "ai.reasi.pro.monthly")
        XCTAssertEqual(annualProductId, "ai.reasi.pro.annual")
    }
}
