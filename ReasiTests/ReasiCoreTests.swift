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
        let monthlyProductId = RevenueCatService.monthlyProductId
        let annualProductId = RevenueCatService.annualProductId

        XCTAssertEqual(entitlementId, "reasi_pro")
        XCTAssertEqual(offeringId, "default")
        XCTAssertEqual(monthlyProductId, "ai.reasi.pro.monthly")
        XCTAssertEqual(annualProductId, "ai.reasi.pro.annual")
    }

    func testRevenueCatKeyValidationRejectsUnsafeReleaseKeys() {
        XCTAssertFalse(ReasiConfig.isValidRevenueCatPublicKey("", allowTestStore: false))
        XCTAssertFalse(ReasiConfig.isValidRevenueCatPublicKey("test_example", allowTestStore: false))
        XCTAssertFalse(ReasiConfig.isValidRevenueCatPublicKey("sk_example", allowTestStore: false))
        XCTAssertTrue(ReasiConfig.isValidRevenueCatPublicKey("appl_example", allowTestStore: false))
        XCTAssertTrue(ReasiConfig.isValidRevenueCatPublicKey("test_example", allowTestStore: true))
    }

    private func fixtureProduct(name: String, price: Double?) -> ProductCandidate {
        ProductCandidate(
            observationId: UUID().uuidString,
            name: name,
            brand: nil,
            size: nil,
            priceAud: price,
            unitPriceAud: nil,
            unitQuantity: nil,
            unitMeasure: nil,
            comparablePrice: nil,
            imageUrl: nil,
            productUrl: nil,
            sourceName: "Test catalog",
            sourceUrl: nil,
            capturedAt: nil,
            freshnessLabel: "Test",
            confidence: .high,
            confidenceReason: "Test fixture",
            uncertaintyText: price == nil ? "Price not known" : ""
        )
    }
}
