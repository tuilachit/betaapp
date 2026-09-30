import XCTest
@testable import Reasi

@MainActor
final class ReasiAccountIdentityTests: XCTestCase {
    func testLegacyStoredQuantityUsesNumericFallbackForNullAndEmptyLabels() throws {
        for label in ["null", "\"\""] {
            let json = "{\"quantity\":1,\"quantity_label\":\(label)}"
            let row = try JSONDecoder().decode(ProductSelectionQuantity.self, from: Data(json.utf8))
            XCTAssertEqual(row.displayQuantity, "1")
            XCTAssertEqual(row.quantity, 1)
            XCTAssertEqual(row.quantityLabel, label == "null" ? nil : "")
        }
    }

    func testStoredQuantityKeepsRawNumericAndLabelValuesForAtomicComparison() throws {
        let json = "{\"quantity\":1.25,\"quantity_label\":\"2 packs\"}"
        let row = try JSONDecoder().decode(ProductSelectionQuantity.self, from: Data(json.utf8))
        XCTAssertEqual(row.displayQuantity, "2 packs")
        XCTAssertEqual(row.quantity, 1.25)
        XCTAssertEqual(row.quantityLabel, "2 packs")
        XCTAssertEqual(ProductSelectionQuantity(quantity: 1.25, quantityLabel: nil).displayQuantity, "1.25")
        XCTAssertNotEqual(ProductSelectionQuantity(quantity: 2, quantityLabel: nil).displayQuantity, "1")
    }

    func testAllPhotoKindsUseRLSCompatibleUUIDWithoutChangingSDKIdentity() throws {
        let account = "ABCDEF12-1234-4567-89AB-ABCDEF123456"
        let photo = UUID(uuidString: "FEDCBA12-1234-4567-89AB-ABCDEF123456")!
        for kind in [UploadKind.productPhoto, .shoppingListPhoto, .storeGuidePhoto] {
            let path = try SupabaseService.userImageUploadPath(userId: account, kind: kind, imageId: photo)
            XCTAssertEqual(path, "\(account.lowercased())/\(kind.rawValue)/\(photo.uuidString.lowercased()).jpg")
        }
        XCTAssertEqual(UUID(uuidString: account)?.uuidString, account)
        XCTAssertThrowsError(try SupabaseService.userImageUploadPath(userId: "../another-account", kind: .productPhoto))
    }

    func testSpendingBudgetPayloadEncodesAmountAndExplicitNull() throws {
        for budget: Double? in [120, nil] {
            let payload = SpendingPreferencesUpsert(userId: "A", weeklyGroceryBudgetAud: budget,
                                                   spendingCoachTone: "supportive", updatedAt: "now")
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
            if let budget { XCTAssertEqual(json["weekly_grocery_budget_aud"] as? Double, budget) }
            else { XCTAssertTrue(json["weekly_grocery_budget_aud"] is NSNull) }
        }
    }

    func testOnboardingBudgetRemovalEncodesExplicitNull() throws {
        let payload = OnboardingPreferencesUpsert(userId: "A", purposeTags: [], primaryPurpose: nil,
            householdChoice: nil, householdSize: 2, cuisines: [], favoriteCuisines: [], foodStyles: [],
            dietaryConstraints: [], dietaryRestrictions: [], preferredStore: "top_ryde",
            onboardingCompletedAt: nil, weeklyGroceryBudgetAud: nil, spendingCoachTone: "supportive", updatedAt: "now")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertTrue(json["weekly_grocery_budget_aud"] is NSNull)
    }
}
