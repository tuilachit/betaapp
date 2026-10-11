import Foundation

struct SmartBasketFlexibility: Codable, Hashable {
    var allowBrandChange = false
    var allowPackChange = false
}

struct SmartBasketPreviewInput: Encodable {
    let shoppingListId: String
    let expectedStoreId: StoreID
    let flexibility: SmartBasketFlexibility
}

struct SmartBasketApplyInput: Encodable, Equatable {
    let previewId: String
    let expectedStoreId: StoreID
    let selectedLineIds: [String]
}

struct SmartBasketApplyResponse: Codable, Equatable {
    let shoppingListId: String
    let mealPlanId: String
    let storeId: StoreID
    let appliedLineIds: [String]
}

struct SmartBasketChoice: Codable, Hashable {
    let sku: String
    let name: String
    let pack: String
    let packPriceCents: Int
    let purchasePackCount: Int
    let lineTotalCents: Int
    let surplusAmount: Double?
    let surplusUnit: String?
    let matchLabel: String
    let capturedAt: String
    let priceBasis: String
    let uncertainties: [String]
    let costType: String?

    var isWeightedEstimate: Bool {
        let indicators = [costType ?? "", priceBasis] + uncertainties
        return indicators.contains {
            $0.localizedCaseInsensitiveContains("weight") || $0.localizedCaseInsensitiveContains("variable")
        }
    }

    var purchaseLabel: String {
        if isWeightedEstimate { return "\(pack) · Weight-based estimate" }
        return "\(purchasePackCount) \(purchasePackCount == 1 ? "pack" : "packs") · \(pack)"
    }

    var trustDescription: String {
        switch priceBasis {
        case "ordinary": "Captured store price"
        case "unconditional_promotion": "Captured offer price"
        case "public_listing": "Publicly listed price; check in store"
        case "conditional": "Price has conditions; check in store"
        default: "Price conditions need checking"
        }
    }

    var isValid: Bool {
        !sku.isEmpty && !name.isEmpty && !pack.isEmpty
            && SmartBasketMoney.isValid(packPriceCents) && SmartBasketMoney.isValid(lineTotalCents)
            && purchasePackCount > 0 && purchasePackCount <= 1_000_000
            && SmartBasketDate.parse(capturedAt) != nil
            && (surplusAmount == nil || (surplusAmount!.isFinite && surplusAmount! >= 0))
            && ["exact", "substitute"].contains(matchLabel)
    }
}

struct SmartBasketRejection: Codable, Hashable {
    let sku: String
    let matchLabel: String
    let reasons: [String]
}

struct SmartBasketLine: Identifiable, Codable, Hashable {
    let id: String
    let needKey: String
    let quantity: String
    let status: String
    let baseline: SmartBasketChoice?
    let selected: SmartBasketChoice?
    let options: [SmartBasketChoice]
    let rejections: [SmartBasketRejection]
    let reasons: [String]

    var isSelectable: Bool {
        guard status == "ready",
              let baseline, let selected, baseline.isValid, selected.isValid,
              selected.sku != baseline.sku, selected.lineTotalCents < baseline.lineTotalCents,
              options.contains(selected) else { return false }
        return true
    }

    var displayName: String { baseline?.name ?? selected?.name ?? needKey }
}

struct SmartBasketCoverage: Codable, Hashable {
    let lineCount: Int
    let baselinePriced: Int
    let candidatePriced: Int
    let comparable: Int
}

struct SmartBasketPreview: Codable, Hashable {
    let previewId: String
    let shoppingListId: String
    let mealPlanId: String
    let storeId: StoreID
    let status: String
    let asOf: String
    let expiresAt: String
    let baselineTotalCents: Int?
    let candidateTotalCents: Int?
    let estimatedReductionCents: Int?
    let comparableBaselineSubtotalCents: Int?
    let comparableCandidateSubtotalCents: Int?
    let comparableReductionCents: Int?
    let coverage: SmartBasketCoverage
    let lines: [SmartBasketLine]

    func isExpired(at now: Date = Date()) -> Bool {
        guard let expiry = SmartBasketDate.parse(expiresAt) else { return true }
        return now >= expiry
    }

    func selectableLineIDs(in context: SmartBasketContext) -> Set<String> {
        guard ["ready", "partial"].contains(status) else { return [] }
        return Set(lines.filter { $0.isSelectable && !context.checkedLineIDs.contains($0.id) }.map(\.id))
    }

    func isValid(for context: SmartBasketContext, at now: Date = Date()) -> Bool {
        guard !previewId.isEmpty, context.matches(shoppingListId: shoppingListId, mealPlanId: mealPlanId, storeId: storeId),
              let capture = SmartBasketDate.parse(asOf), let expiry = SmartBasketDate.parse(expiresAt),
              capture < expiry, !isExpired(at: now),
              coverage.lineCount == lines.count,
              [coverage.baselinePriced, coverage.candidatePriced, coverage.comparable].allSatisfy({ 0...lines.count ~= $0 }),
              Set(lines.map(\.id)).count == lines.count,
              Set(lines.map(\.id)).isSubset(of: Set(context.quantities.keys)) else { return false }
        let amounts = [baselineTotalCents, candidateTotalCents, estimatedReductionCents,
                       comparableBaselineSubtotalCents, comparableCandidateSubtotalCents, comparableReductionCents]
        guard amounts.compactMap({ $0 }).allSatisfy(SmartBasketMoney.isValid) else { return false }
        return lines.allSatisfy { line in
            context.quantities[line.id] == line.quantity
                && [line.baseline, line.selected].compactMap { $0 }.allSatisfy(\.isValid)
                && line.options.allSatisfy(\.isValid)
        }
    }

    func costs(selectedLineIDs: Set<String>) -> SmartBasketCosts {
        let reductions = lines.filter { selectedLineIDs.contains($0.id) && $0.isSelectable }.map {
            $0.baseline!.lineTotalCents - $0.selected!.lineTotalCents
        }
        let reduction = SmartBasketMoney.sum(reductions)
        let proposed = baselineTotalCents.flatMap { baseline in
            guard candidateTotalCents != nil, let reduction, reduction <= baseline else { return nil as Int? }
            return baseline - reduction
        }
        let comparableProposed = comparableBaselineSubtotalCents.flatMap { baseline in
            guard coverage.comparable > 0, comparableCandidateSubtotalCents != nil,
                  let reduction, reduction <= baseline else { return nil as Int? }
            return baseline - reduction
        }
        return SmartBasketCosts(
            currentTotalCents: baselineTotalCents, proposedTotalCents: proposed,
            comparableCurrentCents: coverage.comparable > 0 ? comparableBaselineSubtotalCents : nil,
            comparableProposedCents: comparableProposed,
            estimatedReductionCents: proposed != nil || comparableProposed != nil ? reduction : nil
        )
    }
}

struct SmartBasketCosts: Equatable {
    let currentTotalCents: Int?
    let proposedTotalCents: Int?
    let comparableCurrentCents: Int?
    let comparableProposedCents: Int?
    let estimatedReductionCents: Int?
}

struct SmartBasketIdentity: Hashable {
    var userId: String
    var revision: UInt64
}

struct SmartBasketContext: Equatable {
    var identity: SmartBasketIdentity
    var shoppingListId: String
    var mealPlanId: String
    var storeId: StoreID
    var listRevision: Data
    var quantities: [String: String]
    var checkedLineIDs: Set<String>

    static func ownedQuantities(_ items: [(id: String, quantity: String)]) throws -> [String: String] {
        var result: [String: String] = [:]
        for item in items {
            guard !item.id.isEmpty, result[item.id] == nil else { throw SmartBasketError.invalidResponse }
            result[item.id] = item.quantity
        }
        return result
    }

    static func hasUniqueOwnedIDs(_ ids: [String]) -> Bool {
        !ids.contains(where: \.isEmpty) && Set(ids).count == ids.count
    }

    func matches(shoppingListId: String, mealPlanId: String, storeId: StoreID) -> Bool {
        self.shoppingListId == shoppingListId && self.mealPlanId == mealPlanId && self.storeId == storeId
    }

    func hasSameOwnerAndList(as other: Self) -> Bool {
        identity == other.identity && matches(
            shoppingListId: other.shoppingListId, mealPlanId: other.mealPlanId, storeId: other.storeId
        )
    }

    func validateReload(afterRead other: Self) throws {
        guard self == other else { throw SmartBasketError.refreshRequired }
    }
}

struct SmartBasketRecoveryKey: Hashable {
    let identity: SmartBasketIdentity
    let shoppingListId: String
    let mealPlanId: String
    let storeId: StoreID

    init(_ context: SmartBasketContext) {
        identity = context.identity
        shoppingListId = context.shoppingListId
        mealPlanId = context.mealPlanId
        storeId = context.storeId
    }
}

struct SmartBasketApplyAttempt {
    let input: SmartBasketApplyInput
    let context: SmartBasketContext
}

struct SmartBasketAppliedReceipt {
    let previewId: String
    let context: SmartBasketContext
    let response: SmartBasketApplyResponse
}

struct SmartBasketApplyRejection: Error {
    let reason: SmartBasketError
}

enum SmartBasketMoney {
    static func isValid(_ cents: Int) -> Bool { cents >= 0 && cents <= 9_007_199_254_740_991 }

    static func sum(_ amounts: [Int]) -> Int? {
        var total = 0
        for amount in amounts {
            let result = total.addingReportingOverflow(amount)
            guard !result.overflow, isValid(result.partialValue) else { return nil }
            total = result.partialValue
        }
        return total
    }

    static func text(_ cents: Int?) -> String {
        guard let cents, isValid(cents) else { return "Unconfirmed" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.numberStyle = .currency
        formatter.currencyCode = "AUD"
        formatter.currencySymbol = "A$"
        return formatter.string(from: NSDecimalNumber(value: cents).dividing(by: 100)) ?? "Unconfirmed"
    }
}

enum SmartBasketDate {
    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func display(_ value: String) -> String {
        guard let date = parse(value) else { return "Date unconfirmed" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

enum SmartBasketError: LocalizedError, Equatable {
    case unavailable, offline, signedOut, subscriptionRequired, contextChanged, duplicateProducts, pendingChanges, expired, invalidResponse, refreshRequired, confirmationRequired

    static func fromHTTPResponse(statusCode: Int, body: Data) -> Self? {
        switch statusCode {
        case 401, 403: .signedOut
        case 402: .subscriptionRequired
        case 404: .contextChanged
        case 409:
            if let response = try? JSONDecoder().decode(HTTPErrorBody.self, from: body),
               response.error == "This list contains multiple lines for the same product. Resolve those lines before previewing; no items were changed." {
                .duplicateProducts
            } else {
                .contextChanged
            }
        case 503: .unavailable
        default: nil
        }
    }

    private struct HTTPErrorBody: Decodable {
        let error: String
    }

    var errorDescription: String? {
        switch self {
        case .unavailable: "Smart Basket is unavailable for this list right now."
        case .offline: "You're offline. Reconnect to review or apply swaps."
        case .signedOut: "Sign in to review this shopping list."
        case .subscriptionRequired: "Smart Basket is available with Reasi Pro."
        case .contextChanged: "Your list or store changed. Refresh the preview before applying swaps."
        case .duplicateProducts: "Resolve the duplicate product lines in your shopping list before checking prices again. No items were changed."
        case .pendingChanges: "Your latest list changes are still saving. Stay online and try again."
        case .expired: "This preview has expired. Refresh to check prices again."
        case .invalidResponse: "We couldn't confirm this preview for your list. Please try again."
        case .refreshRequired: "Your swaps were saved. Reload your list to see them."
        case .confirmationRequired: "We couldn't confirm whether your swaps were saved. Reconnect and check again before making more changes."
        }
    }
}
