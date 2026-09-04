import Foundation

enum SpendingPeriod: String, Codable, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        }
    }
}

enum SpendingCoachTone: String, Codable, CaseIterable, Identifiable {
    case supportive
    case direct
    case celebratory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supportive: "Supportive"
        case .direct: "Direct"
        case .celebratory: "Celebratory"
        }
    }

    var detail: String {
        switch self {
        case .supportive: "Calm, practical guidance"
        case .direct: "Clear and straight to the point"
        case .celebratory: "Encouraging progress highlights"
        }
    }

    var symbolName: String {
        switch self {
        case .supportive: "heart"
        case .direct: "scope"
        case .celebratory: "sparkles"
        }
    }
}

enum SpendingInsightKind: String, Codable, CaseIterable {
    case pattern
    case context
    case nextAction = "next_action"

    var label: String {
        switch self {
        case .pattern: "Pattern"
        case .context: "Why it matters"
        case .nextAction: "Next shop"
        }
    }

    var symbolName: String {
        switch self {
        case .pattern: "chart.line.uptrend.xyaxis"
        case .context: "circle.lefthalf.filled"
        case .nextAction: "arrow.right"
        }
    }
}

struct SpendingInsightCard: Codable, Hashable, Identifiable {
    var id: String { "\(kind.rawValue)-\(title)" }
    let kind: SpendingInsightKind
    let title: String
    let body: String
    let evidenceKeys: [String]
}

struct SpendingCategoryAmount: Codable, Hashable, Identifiable {
    var id: String { label }
    let label: String
    let amountAud: Double
}

struct SpendingTrendPoint: Codable, Hashable, Identifiable {
    var id: String { weekStart }
    let weekStart: String
    let amountAud: Double
}

struct ActiveBasketProjection: Codable, Hashable {
    let shoppingListId: String
    let projectedTotalAud: Double
    let pricedItems: Int
    let totalItems: Int

    var priceCoverage: Double {
        guard totalItems > 0 else { return 0 }
        return Double(pricedItems) / Double(totalItems)
    }
}

struct SpendingRecentTrip: Codable, Hashable, Identifiable {
    var id: String { tripId }
    let tripId: String
    let shoppingListId: String
    let storeId: StoreID
    let storeName: String
    let completedAt: String
    let effectiveTotalAud: Double
    let checkedItems: Int
    let pricedCheckedItems: Int
    let priceCoverage: Double
}

struct SpendingDashboard: Codable, Hashable {
    let period: SpendingPeriod
    let startDate: String
    let endDateExclusive: String
    let currency: String
    let completedSpendAud: Double
    let trackedItemSpendAud: Double
    let checkoutDifferenceAud: Double
    let weeklyBudgetAud: Double?
    let budgetRemainingAud: Double?
    let priceCoverage: Double
    let checkedItems: Int
    let pricedCheckedItems: Int
    let plannedSpendAud: Double
    let addedSpendAud: Double
    let categories: [SpendingCategoryAmount]
    let trend: [SpendingTrendPoint]
    let averageWeeklySpendAud: Double?
    let activeBasket: ActiveBasketProjection?
    let recentTrips: [SpendingRecentTrip]
    let insightStatus: String?
    let insightCards: [SpendingInsightCard]
    let timezone: String
    let coachTone: SpendingCoachTone

    var hasCompletedShops: Bool { !recentTrips.isEmpty }
    var isOverBudget: Bool { (budgetRemainingAud ?? 0) < 0 }
    var budgetProgress: Double? {
        guard let weeklyBudgetAud, weeklyBudgetAud > 0 else { return nil }
        return min(max(completedSpendAud / weeklyBudgetAud, 0), 1)
    }
}

struct SpendingTrip: Codable, Hashable, Identifiable {
    let id: String
    let shoppingListId: String
    let storeId: StoreID
    let storeName: String
    let completedAt: String
    let knownBasketTotalAud: Double
    let confirmedTotalAud: Double?
    let checkedItems: Int
    let pricedCheckedItems: Int
    let trackedTotalAud: Double
    let effectiveTotalAud: Double
    let checkoutDifferenceAud: Double
    let priceCoverage: Double
    let weeklyBudgetAud: Double?
    let weeklySpendAud: Double
    let weeklyBudgetRemainingAud: Double?
}

struct SpendingTripItem: Codable, Hashable, Identifiable {
    let id: String
    let shoppingListItemId: String?
    let name: String
    let quantity: String
    let checked: Bool
    let sectionLabel: String?
    let aisleLabel: String?
    let sku: String?
    let barcode: String?
    let brand: String?
    let size: String?
    let priceAud: Double?
    let priceSource: String
    let priceCapturedAt: String?
    let origin: String
    let spendCategory: String
    let categorySource: String
}

struct SpendingTripDetail: Codable, Hashable {
    let trip: SpendingTrip
    let categories: [SpendingCategoryAmount]
    let plannedSpendAud: Double
    let addedSpendAud: Double
    let insightStatus: String?
    let insightCards: [SpendingInsightCard]
    let items: [SpendingTripItem]
}

struct SpendingTotalCorrection: Codable, Hashable {
    let tripId: String
    let confirmedTotalAud: Double
    let trackedTotalAud: Double
    let effectiveTotalAud: Double
    let confirmedAt: String
}

extension String {
    var reasiISODate: Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: self) ?? ISO8601DateFormatter().date(from: self)
    }
}

#if DEBUG
extension SpendingDashboard {
    static let uiTestFixture = SpendingDashboard(
        period: .week,
        startDate: "2026-08-31",
        endDateExclusive: "2026-09-07",
        currency: "AUD",
        completedSpendAud: 86.40,
        trackedItemSpendAud: 82.40,
        checkoutDifferenceAud: 4,
        weeklyBudgetAud: 120,
        budgetRemainingAud: 33.60,
        priceCoverage: 0.8,
        checkedItems: 10,
        pricedCheckedItems: 8,
        plannedSpendAud: 62,
        addedSpendAud: 20.40,
        categories: [
            SpendingCategoryAmount(label: "Protein", amountAud: 28.50),
            SpendingCategoryAmount(label: "Produce", amountAud: 20.20),
            SpendingCategoryAmount(label: "Pantry", amountAud: 13.70),
            SpendingCategoryAmount(label: "Dairy & eggs", amountAud: 7),
            SpendingCategoryAmount(label: "Bakery", amountAud: 5),
            SpendingCategoryAmount(label: "Frozen", amountAud: 4.50),
            SpendingCategoryAmount(label: "Drinks", amountAud: 3.50),
        ],
        trend: [],
        averageWeeklySpendAud: nil,
        activeBasket: ActiveBasketProjection(
            shoppingListId: "ui-test-active-list",
            projectedTotalAud: 31.50,
            pricedItems: 4,
            totalItems: 5
        ),
        recentTrips: [
            SpendingRecentTrip(
                tripId: "ui-test-trip",
                shoppingListId: "ui-test-list",
                storeId: .topRyde,
                storeName: "Coles Top Ryde",
                completedAt: "2026-09-01T08:30:00.000Z",
                effectiveTotalAud: 86.40,
                checkedItems: 10,
                pricedCheckedItems: 8,
                priceCoverage: 0.8
            ),
        ],
        insightStatus: "completed",
        insightCards: SpendingTripDetail.uiTestFixture.insightCards,
        timezone: "Australia/Sydney",
        coachTone: .supportive
    )

    static func uiTestFixture(for period: SpendingPeriod) -> SpendingDashboard {
        guard period == .month else { return uiTestFixture }

        return SpendingDashboard(
            period: .month,
            startDate: "2026-08-01",
            endDateExclusive: "2026-09-01",
            currency: uiTestFixture.currency,
            completedSpendAud: 286.40,
            trackedItemSpendAud: 275.20,
            checkoutDifferenceAud: 11.20,
            weeklyBudgetAud: uiTestFixture.weeklyBudgetAud,
            budgetRemainingAud: nil,
            priceCoverage: 0.82,
            checkedItems: 34,
            pricedCheckedItems: 28,
            plannedSpendAud: 214,
            addedSpendAud: 61.20,
            categories: [
                SpendingCategoryAmount(label: "Protein", amountAud: 94.50),
                SpendingCategoryAmount(label: "Produce", amountAud: 68.20),
                SpendingCategoryAmount(label: "Pantry", amountAud: 47.50),
                SpendingCategoryAmount(label: "Dairy & eggs", amountAud: 25),
                SpendingCategoryAmount(label: "Bakery", amountAud: 16),
                SpendingCategoryAmount(label: "Frozen", amountAud: 13),
                SpendingCategoryAmount(label: "Drinks", amountAud: 11),
            ],
            trend: [
                SpendingTrendPoint(weekStart: "2026-08-03", amountAud: 62),
                SpendingTrendPoint(weekStart: "2026-08-10", amountAud: 74),
                SpendingTrendPoint(weekStart: "2026-08-17", amountAud: 63),
                SpendingTrendPoint(weekStart: "2026-08-24", amountAud: 87.40),
            ],
            averageWeeklySpendAud: 71.60,
            activeBasket: uiTestFixture.activeBasket,
            recentTrips: uiTestFixture.recentTrips,
            insightStatus: uiTestFixture.insightStatus,
            insightCards: uiTestFixture.insightCards,
            timezone: uiTestFixture.timezone,
            coachTone: uiTestFixture.coachTone
        )
    }
}

extension SpendingTripDetail {
    static let uiTestFixture = SpendingTripDetail(
        trip: SpendingTrip(
            id: "ui-test-trip",
            shoppingListId: "ui-test-list",
            storeId: .topRyde,
            storeName: "Coles Top Ryde",
            completedAt: "2026-09-01T08:30:00.000Z",
            knownBasketTotalAud: 82.40,
            confirmedTotalAud: 86.40,
            checkedItems: 10,
            pricedCheckedItems: 8,
            trackedTotalAud: 82.40,
            effectiveTotalAud: 86.40,
            checkoutDifferenceAud: 4,
            priceCoverage: 0.8,
            weeklyBudgetAud: 120,
            weeklySpendAud: 86.40,
            weeklyBudgetRemainingAud: 33.60
        ),
        categories: [
            SpendingCategoryAmount(label: "Protein", amountAud: 36.50),
            SpendingCategoryAmount(label: "Produce", amountAud: 24.20),
            SpendingCategoryAmount(label: "Pantry", amountAud: 14.70),
            SpendingCategoryAmount(label: "Dairy & eggs", amountAud: 7),
        ],
        plannedSpendAud: 62,
        addedSpendAud: 20.40,
        insightStatus: "completed",
        insightCards: [
            SpendingInsightCard(
                kind: .pattern,
                title: "Protein led this shop",
                body: "A$36.50 of tracked spend went to protein.",
                evidenceKeys: ["top_category"]
            ),
            SpendingInsightCard(
                kind: .context,
                title: "Added items shaped spend",
                body: "A$20.40 came from items added after the original plan.",
                evidenceKeys: ["added_spend"]
            ),
            SpendingInsightCard(
                kind: .nextAction,
                title: "Keep this buffer",
                body: "A$33.60 remains in this week's grocery target.",
                evidenceKeys: ["budget_remaining"]
            ),
        ],
        items: [
            SpendingTripItem(
                id: "ui-test-item-1",
                shoppingListItemId: "ui-test-list-item-1",
                name: "Salmon portions",
                quantity: "2 packs",
                checked: true,
                sectionLabel: "Meat & Seafood",
                aisleLabel: "Seafood",
                sku: "ui-salmon",
                barcode: nil,
                brand: nil,
                size: "500g",
                priceAud: 24,
                priceSource: "captured",
                priceCapturedAt: "2026-09-01T08:00:00.000Z",
                origin: "planned",
                spendCategory: "Protein",
                categorySource: "catalog"
            ),
            SpendingTripItem(
                id: "ui-test-item-2",
                shoppingListItemId: "ui-test-list-item-2",
                name: "Baby spinach",
                quantity: "1 bag",
                checked: true,
                sectionLabel: "Fresh Produce",
                aisleLabel: "Fresh Produce",
                sku: "ui-spinach",
                barcode: nil,
                brand: nil,
                size: "120g",
                priceAud: 4.50,
                priceSource: "captured",
                priceCapturedAt: "2026-09-01T08:00:00.000Z",
                origin: "manual",
                spendCategory: "Produce",
                categorySource: "section"
            ),
        ]
    )
}
#endif
