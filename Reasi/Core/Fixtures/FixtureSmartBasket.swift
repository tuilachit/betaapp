import Foundation

#if DEBUG
enum FixtureSmartBasket {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-ReasiSmartBasketFixture")
    }
    static let context = SmartBasketContext(
        identity: .init(userId: "fixture-user", revision: 1), shoppingListId: "fixture-list",
        mealPlanId: "fixture-plan", storeId: .eastVillage, listRevision: Data("fixture-list-v1".utf8),
        quantities: ["bananas": "1 kg", "rice": "1 kg"], checkedLineIDs: []
    )

    // Synthetic display-only fixture. These are not retailer prices or savings evidence.
    static func preview(now: Date = Date(), partial: Bool = false, status: String = "ready", storeId: StoreID = .eastVillage, expiresIn: TimeInterval = 900) -> SmartBasketPreview {
        let formatter = ISO8601DateFormatter()
        let asOf = formatter.string(from: now)
        let expires = formatter.string(from: now.addingTimeInterval(expiresIn))
        let payload = """
        {"previewId":"fixture-preview","shoppingListId":"fixture-list","mealPlanId":"fixture-plan","storeId":"\(storeId.rawValue)",
         "status":"\(status)","asOf":"\(asOf)","expiresAt":"\(expires)",
         "baselineTotalCents":\(partial ? "null" : "1480"),"candidateTotalCents":\(partial ? "null" : "1120"),"estimatedReductionCents":\(partial ? "null" : "360"),
         "comparableBaselineSubtotalCents":1480,"comparableCandidateSubtotalCents":1120,"comparableReductionCents":360,
         "coverage":{"lineCount":2,"baselinePriced":2,"candidatePriced":2,"comparable":2},
         "lines":[
          {"id":"bananas","needKey":"bananas","quantity":"1 kg","status":"ready",
           "baseline":\(choice(sku: "banana-a", name: "Bananas", pack: "1 kg", cents: 280, count: 1, weighted: true, capturedAt: asOf)),
           "selected":\(choice(sku: "banana-b", name: "Loose bananas", pack: "1 kg", cents: 220, count: 1, weighted: true, capturedAt: asOf)),
           "options":[\(choice(sku: "banana-b", name: "Loose bananas", pack: "1 kg", cents: 220, count: 1, weighted: true, capturedAt: asOf))],"rejections":[],"reasons":[]},
          {"id":"rice","needKey":"rice","quantity":"1 kg","status":"ready",
           "baseline":\(choice(sku: "rice-a", name: "White rice", pack: "500 g", cents: 600, count: 2, capturedAt: asOf)),
           "selected":\(choice(sku: "rice-b", name: "Long grain white rice", pack: "500 g", cents: 450, count: 2, capturedAt: asOf)),
           "options":[\(choice(sku: "rice-b", name: "Long grain white rice", pack: "500 g", cents: 450, count: 2, capturedAt: asOf))],"rejections":[],"reasons":[]}
         ]}
        """
        return try! JSONDecoder().decode(SmartBasketPreview.self, from: Data(payload.utf8))
    }

    @MainActor
    static func operations(storeId: StoreID, isOnline: @escaping () -> Bool) -> SmartBasketOperations {
        var expected = context
        expected.storeId = storeId
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ReasiSmartBasketUnsupportedFixture") {
            expected.quantities = Dictionary(uniqueKeysWithValues: (0..<10).map { ("item-\($0)", "1") })
        }
        return SmartBasketOperations(
            context: {
                guard isOnline() else { throw SmartBasketError.offline }
                return expected
            },
            confirmationContext: { expected },
            flush: {},
            preview: { _ in
                if arguments.contains("-ReasiSmartBasketErrorFixture") { throw SmartBasketError.unavailable }
                if arguments.contains("-ReasiSmartBasketUnsupportedFixture") { return unsupportedPreview(storeId: storeId) }
                if arguments.contains("-ReasiSmartBasketLoadingFixture") { try await Task.sleep(for: .seconds(3)) }
                let status = arguments.contains("-ReasiSmartBasketNoChangeFixture") ? "no_change"
                    : arguments.contains("-ReasiSmartBasketPartialFixture") ? "partial" : "ready"
                let result = preview(partial: status == "partial", status: status, storeId: storeId,
                                     expiresIn: arguments.contains("-ReasiSmartBasketExpiryFixture") ? 3 : 900)
                if arguments.contains("-ReasiSmartBasketEmptyFixture") {
                    return SmartBasketPreview(
                        previewId: result.previewId, shoppingListId: result.shoppingListId, mealPlanId: result.mealPlanId,
                        storeId: storeId, status: "no_change", asOf: result.asOf, expiresAt: result.expiresAt,
                        baselineTotalCents: nil, candidateTotalCents: nil, estimatedReductionCents: nil,
                        comparableBaselineSubtotalCents: nil, comparableCandidateSubtotalCents: nil, comparableReductionCents: nil,
                        coverage: .init(lineCount: 0, baselinePriced: 0, candidatePriced: 0, comparable: 0), lines: []
                    )
                }
                return result
            },
            apply: { input in
                SmartBasketApplyResponse(shoppingListId: expected.shoppingListId, mealPlanId: expected.mealPlanId,
                                         storeId: storeId, appliedLineIds: input.selectedLineIds)
            },
            reload: { _ in }
        )
    }

    static func unsupportedPreview(storeId: StoreID = .eastVillage) -> SmartBasketPreview {
        let original = preview(storeId: storeId)
        return SmartBasketPreview(
            previewId: original.previewId, shoppingListId: original.shoppingListId, mealPlanId: original.mealPlanId,
            storeId: storeId, status: "unavailable", asOf: original.asOf, expiresAt: original.expiresAt,
            baselineTotalCents: nil, candidateTotalCents: nil, estimatedReductionCents: nil,
            comparableBaselineSubtotalCents: nil, comparableCandidateSubtotalCents: nil, comparableReductionCents: nil,
            coverage: .init(lineCount: 10, baselinePriced: 0, candidatePriced: 0, comparable: 0),
            lines: (0..<10).map { index in
                SmartBasketLine(id: "item-\(index)", needKey: "Item \(index + 1)", quantity: "1", status: "unavailable",
                                baseline: nil, selected: nil, options: [], rejections: [], reasons: ["baseline_unavailable"])
            }
        )
    }

    private static func choice(sku: String, name: String, pack: String, cents: Int, count: Int, weighted: Bool = false, capturedAt: String) -> String {
        """
        {"sku":"\(sku)","name":"\(name)","pack":"\(pack)","packPriceCents":\(cents),"purchasePackCount":\(count),"lineTotalCents":\(cents * count),
         "surplusAmount":0,"surplusUnit":"g","matchLabel":"substitute","capturedAt":"\(capturedAt)","priceBasis":"ordinary","uncertainties":[],"matchPolicy":"catalog-food-signature-v1","matchEvidence":[]\(weighted ? ",\"costType\":\"variable_weight_display_estimate\"" : "")}
        """
    }
}
#endif
