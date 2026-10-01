import Foundation
import XCTest
#if canImport(Reasi)
@testable import Reasi
#endif

final class ReasiInputReliabilityTests: XCTestCase {
    static var recipePayload: [String: Any] {
        [
            "ingredients": (1...60).map {
                ["name": "Ingredient \($0)", "quantity": "\($0 * 10) g", "category": "Recipe"]
            },
            "method": (1...40).map { "Step \($0): follow the photographed instruction." },
            "instructionsBrief": "Prepare every ingredient, then follow all forty steps.",
            "prepTimeMin": 0, "cookTimeMin": 35, "serves": 6,
        ]
    }

    private func briefPayload(includeRecipe: Bool = true) -> [String: Any] {
        var idea: [String: Any] = [
            "id": "photo-recipe", "type": "dish", "title": "Family recipe",
            "detail": "Short display summary", "mustKeep": true,
            "uploadPath": "user/product-photos/recipe.jpg",
            "sourceUrl": "https://example.com/recipe", "confidence": "medium",
            "confidenceReason": "Readable recipe text; one quantity needs review.",
        ]
        if includeRecipe { idea["recipe"] = Self.recipePayload }
        return ["kind": "week", "entryMethod": "build", "serves": 2, "ideas": [idea]]
    }

    private func decode(_ payload: [String: Any]) throws -> PlanBrief {
        try JSONDecoder().decode(PlanBrief.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    private func encodedIdea(_ brief: PlanBrief) throws -> [String: Any] {
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(brief)) as? [String: Any])
        return try XCTUnwrap((payload["ideas"] as? [[String: Any]])?.first)
    }

    func testPhotoRecipeSurvivesDraftAndGenerationEncoding() throws {
        let draft = try decode(briefPayload())
        let restored = try JSONDecoder().decode(PlanBrief.self, from: JSONEncoder().encode(draft))
        let input = GenerateWeekPlanInput(storeId: .topRyde, weekStart: nil, idempotencyKey: "test", planBrief: restored)
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        let brief = try XCTUnwrap(request["planBrief"] as? [String: Any])
        let idea = try XCTUnwrap((brief["ideas"] as? [[String: Any]])?.first)
        let recipe = try XCTUnwrap(idea["recipe"] as? NSDictionary, "Full source recipe must reach generation, not just a display summary")
        XCTAssertEqual(recipe, Self.recipePayload as NSDictionary)
        XCTAssertEqual(idea["uploadPath"] as? String, "user/product-photos/recipe.jpg")
        XCTAssertEqual(idea["confidence"] as? String, "medium")
        XCTAssertEqual(idea["confidenceReason"] as? String, "Readable recipe text; one quantity needs review.")
    }

    func testInterpretationMergeRetainsLocalRecipeEvidence() throws {
        let original = try decode(briefPayload())
        let interpreted = try decode(briefPayload(includeRecipe: false))
        let idea = try encodedIdea(interpreted.mergingClientMetadata(from: original))
        XCTAssertEqual(idea["recipe"] as? NSDictionary, Self.recipePayload as NSDictionary)
    }

    func testLegacyDishWithoutReadableRecipeDoesNotInventEvidence() throws {
        let idea = try encodedIdea(decode(briefPayload(includeRecipe: false)))
        XCTAssertNil(idea["recipe"])
    }

    func testResolvedPhotoConversionPreservesRecipeAndProvenance() throws {
        let recipe = try JSONDecoder().decode(RecipeInfo.self, from: JSONSerialization.data(withJSONObject: Self.recipePayload))
        let resolved = ResolvedMealIdea(
            title: "Family recipe", description: "Short display summary", cuisine: nil,
            sourceURL: URL(string: "https://example.com/recipe"), imageURL: nil,
            confidence: .medium, confidenceReason: "Readable recipe text; one quantity needs review.",
            recipe: recipe, product: nil
        )
        let idea = PlanIdea(resolvedMeal: resolved, uploadPath: "user/product-photos/recipe.jpg", detail: "Display-only summary")
        let encoded = try encodedIdea(PlanBrief(kind: .week, entryMethod: .build, ideas: [idea]))
        XCTAssertEqual(encoded["recipe"] as? NSDictionary, Self.recipePayload as NSDictionary)
        XCTAssertEqual(encoded["uploadPath"] as? String, "user/product-photos/recipe.jpg")
        XCTAssertEqual(encoded["sourceUrl"] as? String, "https://example.com/recipe")
        XCTAssertEqual(encoded["confidence"] as? String, "medium")
        XCTAssertEqual(encoded["detail"] as? String, "Display-only summary")
    }

    func testResolvedDishPhotoWithoutRecipeKeepsUncertainty() throws {
        let resolved = ResolvedMealIdea(
            title: "Possible curry", description: nil, cuisine: nil, sourceURL: nil, imageURL: nil,
            confidence: .low, confidenceReason: "No readable recipe text.", recipe: nil, product: nil
        )
        let idea = PlanIdea(resolvedMeal: resolved, uploadPath: "user/product-photos/dish.jpg")
        let encoded = try encodedIdea(PlanBrief(kind: .week, entryMethod: .build, ideas: [idea]))
        XCTAssertNil(encoded["recipe"])
        XCTAssertEqual(encoded["confidence"] as? String, "low")
        XCTAssertEqual(encoded["confidenceReason"] as? String, "No readable recipe text.")
        XCTAssertEqual(encoded["uploadPath"] as? String, "user/product-photos/dish.jpg")
    }
}
