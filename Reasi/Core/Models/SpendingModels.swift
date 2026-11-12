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
        case .supportive: "Gentle, practical tips"
        case .direct: "Short and to the point"
        case .celebratory: "Points out the weeks you do well"
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
        case .context: "Context"
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
        startDate: SampleDates.dayKey(SampleDates.weekStart()),
        endDateExclusive: SampleDates.dayKey(SampleDates.day(7, from: SampleDates.weekStart())),
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
                completedAt: SampleDates.timestamp(SampleDates.day(1, from: SampleDates.weekStart())),
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
            startDate: SampleDates.dayKey(SampleDates.weekStart(weeksAgo: 4)),
            endDateExclusive: SampleDates.dayKey(SampleDates.weekStart()),
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
                SpendingTrendPoint(weekStart: SampleDates.dayKey(SampleDates.weekStart(weeksAgo: 4)), amountAud: 62),
                SpendingTrendPoint(weekStart: SampleDates.dayKey(SampleDates.weekStart(weeksAgo: 3)), amountAud: 74),
                SpendingTrendPoint(weekStart: SampleDates.dayKey(SampleDates.weekStart(weeksAgo: 2)), amountAud: 63),
                SpendingTrendPoint(weekStart: SampleDates.dayKey(SampleDates.weekStart(weeksAgo: 1)), amountAud: 87.40),
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
            completedAt: SampleDates.timestamp(SampleDates.day(1, from: SampleDates.weekStart())),
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
                title: "Protein was the biggest cost",
                body: "A$36.50 of this shop went on protein.",
                evidenceKeys: ["top_category"]
            ),
            SpendingInsightCard(
                kind: .context,
                title: "A$20.40 wasn't on the plan",
                body: "That's what the items you added yourself came to.",
                evidenceKeys: ["added_spend"]
            ),
            SpendingInsightCard(
                kind: .nextAction,
                title: "A$33.60 left this week",
                body: "Keep top-up shops under that to finish on target.",
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

/// How the user's finished weeks compare with their current weekly target.
/// Only weeks that are over and had a completed shop count; the week in progress never does.
struct BudgetTrackRecord: Equatable {
    let target: Double
    let completedWeeks: Int
    let weeksOnTarget: Int
    /// Positive when the user spent less than the target in total across completed weeks.
    let netUnderTargetAud: Double
    /// Consecutive most recent completed weeks at or under the target.
    let currentStreak: Int

    init?(trend: [SpendingTrendPoint], weeklyTarget: Double?, today: Date = Date(), calendar: Calendar = .current) {
        guard let weeklyTarget, weeklyTarget.isFinite, weeklyTarget > 0 else { return nil }
        let todayKey = Self.dayKey(today, calendar: calendar)
        let finished = trend
            .filter { $0.amountAud.isFinite && $0.amountAud > 0 }
            .filter { point in
                guard let end = Self.weekEndKey(point.weekStart) else { return false }
                return end <= todayKey
            }
            .sorted { $0.weekStart < $1.weekStart }
        guard !finished.isEmpty else { return nil }

        target = weeklyTarget
        completedWeeks = finished.count
        weeksOnTarget = finished.filter { Self.cents($0.amountAud) <= Self.cents(weeklyTarget) }.count
        netUnderTargetAud = (Double(Self.cents(weeklyTarget) * finished.count) - Double(finished.reduce(0) { $0 + Self.cents($1.amountAud) })) / 100
        currentStreak = finished.reversed().prefix { Self.cents($0.amountAud) <= Self.cents(weeklyTarget) }.count
    }

    /// e.g. "3 of 4 weeks on target · A$86 under in total"
    var summary: String {
        let weeks = "\(weeksOnTarget) of \(completedWeeks) \(completedWeeks == 1 ? "week" : "weeks") on target"
        let net = abs(netUnderTargetAud).formatted(.currency(code: "AUD").locale(Locale(identifier: "en_AU")).precision(.fractionLength(0)))
        if Self.cents(abs(netUnderTargetAud)) < 100 { return "\(weeks) · right on target overall" }
        return netUnderTargetAud > 0 ? "\(weeks) · \(net) under in total" : "\(weeks) · \(net) over in total"
    }

    private static func cents(_ value: Double) -> Int { Int((value * 100).rounded()) }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The first day after the week, as yyyy-MM-dd, computed in UTC so the result never shifts with the device time zone.
    private static func weekEndKey(_ weekStart: String) -> String? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_AU_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: weekStart) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let end = utc.date(byAdding: .day, value: 7, to: start) else { return nil }
        return formatter.string(from: end)
    }
}

/// Something the user has bought in more than one recent finished shop.
struct UsualItem: Codable, Hashable, Identifiable {
    /// `sku:`, `barcode:` or `name:` followed by the matching value.
    let key: String
    let name: String
    let brand: String?
    let size: String?
    let sku: String?
    let barcode: String?
    let sectionLabel: String?
    let aisleLabel: String?
    /// The shelf price recorded the last time it was bought.
    let lastPaidAud: Double?
    let lastPriceCapturedAt: String?
    let lastBoughtAt: String
    let timesBought: Int
    let shopsConsidered: Int

    var id: String { key }

    var displayName: String {
        if let brand, !brand.isEmpty, !name.localizedCaseInsensitiveContains(brand) {
            return "\(brand) \(name)"
        }
        return name
    }

    /// The list item this usual becomes when added. The price is the last one paid, so the
    /// price-age line on the list stays honest about how old it is.
    /// Pass the list section it should join, or nil to place it like any other added item.
    func candidate(joining section: ShoppingListSection?) -> ProductCandidate {
        var candidate = ProductCandidate(
            observationId: nil,
            name: name,
            brand: brand,
            size: size,
            priceAud: lastPaidAud,
            unitPriceAud: nil,
            unitQuantity: nil,
            unitMeasure: nil,
            comparablePrice: nil,
            imageUrl: nil,
            productUrl: nil,
            sourceName: "Your past shops",
            sourceUrl: nil,
            capturedAt: lastPriceCapturedAt,
            freshnessLabel: "Last bought \(ShoppingHabits.shortDate(lastBoughtAt))",
            confidence: sku == nil && barcode == nil ? .low : .medium,
            confidenceReason: "You bought this in \(timesBought) of your last \(shopsConsidered) shops.",
            uncertaintyText: "The price is what it cost last time and may have changed."
        )
        candidate.sku = sku
        candidate.barcode = barcode
        candidate.aisleLabel = aisleLabel
        candidate.sectionLabel = section?.label
        candidate.sectionSortKey = section?.sortKey
        candidate.sectionType = section?.type
        return candidate
    }
}

/// Learns what a household buys week after week from its finished shops.
enum ShoppingHabits {
    /// How many of the most recent finished shops are read.
    static let shopsToConsider = 6
    /// An item has to be bought in at least this many of those shops to count as a usual.
    static let minimumTimesBought = 2
    static let maximumUsuals = 12

    /// Items bought in at least `minimumTimesBought` of the most recent shops, most regular first.
    /// Only ticked items count, and an item counts once per shop however many times it was listed.
    static func usuals(from trips: [SpendingTripDetail]) -> [UsualItem] {
        let recent = Array(
            trips
                .reduce(into: [String: SpendingTripDetail]()) { $0[$1.trip.id] = $1 }
                .values
                .sorted { completedDate($0.trip.completedAt) > completedDate($1.trip.completedAt) }
                .prefix(shopsToConsider)
        )
        guard recent.count >= minimumTimesBought else { return [] }

        var tripCounts: [String: Int] = [:]
        // The newest purchase of each item, used for its name, price and aisle.
        var latest: [String: (item: SpendingTripItem, completedAt: String)] = [:]

        for trip in recent {
            var seenInTrip = Set<String>()
            for item in trip.items where item.checked {
                guard let key = key(for: item), seenInTrip.insert(key).inserted else { continue }
                tripCounts[key, default: 0] += 1
                if latest[key] == nil {
                    latest[key] = (item, trip.trip.completedAt)
                }
            }
        }

        return tripCounts
            .filter { $0.value >= minimumTimesBought }
            .compactMap { key, count -> UsualItem? in
                guard let newest = latest[key] else { return nil }
                let item = newest.item
                return UsualItem(
                    key: key,
                    name: item.name,
                    brand: item.brand,
                    size: item.size,
                    sku: item.sku,
                    barcode: item.barcode,
                    sectionLabel: item.sectionLabel,
                    aisleLabel: item.aisleLabel,
                    lastPaidAud: item.priceAud.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
                    lastPriceCapturedAt: item.priceCapturedAt,
                    lastBoughtAt: newest.completedAt,
                    timesBought: count,
                    shopsConsidered: recent.count
                )
            }
            .sorted {
                if $0.timesBought != $1.timesBought { return $0.timesBought > $1.timesBought }
                let first = completedDate($0.lastBoughtAt), second = completedDate($1.lastBoughtAt)
                if first != second { return first > second }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            .prefix(maximumUsuals)
            .map { $0 }
    }

    /// The usuals that aren't on the list yet, matched by product code first and then by name.
    static func notOnList(_ usuals: [UsualItem], items: [ShoppingListItem]) -> [UsualItem] {
        var skus = Set<String>()
        var barcodes = Set<String>()
        var names = Set<String>()
        for item in items {
            if let sku = item.product?.sku ?? item.importedCandidate?.sku { skus.insert(sku) }
            if let barcode = item.product?.barcode ?? item.importedCandidate?.barcode { barcodes.insert(barcode) }
            names.insert(normalizedName(item.name))
            if let productName = item.product?.productName { names.insert(normalizedName(productName)) }
            if let candidate = item.importedCandidate { names.insert(normalizedName(candidate.displayName)) }
        }
        return usuals.filter { usual in
            if let sku = usual.sku, skus.contains(sku) { return false }
            if let barcode = usual.barcode, barcodes.contains(barcode) { return false }
            return !names.contains(normalizedName(usual.name)) && !names.contains(normalizedName(usual.displayName))
        }
    }

    static func key(for item: SpendingTripItem) -> String? {
        if let sku = item.sku?.trimmingCharacters(in: .whitespaces), !sku.isEmpty { return "sku:\(sku)" }
        if let barcode = item.barcode?.trimmingCharacters(in: .whitespaces), !barcode.isEmpty { return "barcode:\(barcode)" }
        let name = normalizedName(item.name)
        return name.isEmpty ? nil : "name:\(name)"
    }

    static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_AU"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func completedDate(_ value: String) -> Date {
        PriceFreshness.parse(value) ?? .distantPast
    }

    /// e.g. "3 Nov"
    static func shortDate(_ isoTimestamp: String) -> String {
        guard let date = PriceFreshness.parse(isoTimestamp) else { return "recently" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_AU")))
    }
}

#if DEBUG
extension SpendingTripDetail {
    /// Four weekly shops with a realistic mix of regular and one-off items, for the usuals card.
    static var usualsFixture: [SpendingTripDetail] {
        // (name, brand, size, sku, section, aisle, price, weeks it was bought in)
        let catalogue: [(String, String?, String?, String?, String, String, Double, Set<Int>)] = [
            ("Full Cream Milk", "Coles", "2L", "fixture-milk", "Dairy and Chilled", "Aisle 12", 3.10, [0, 1, 2, 3]),
            ("Cavendish Bananas", nil, "per kg", "fixture-bananas", "Fresh Produce", "Fresh produce", 4.00, [0, 1, 2, 3]),
            ("Australian Free Range Eggs", "Coles", "12 pack", "fixture-eggs", "Dairy and Chilled", "Aisle 12", 6.20, [0, 1, 3]),
            ("Wholemeal Bread", "Helga's", "750g", "fixture-bread", "Bakery", "Bakery", 5.00, [0, 2, 3]),
            ("Greek yoghurt", "Chobani", "907g", "fixture-yoghurt", "Dairy and Chilled", "Aisle 12", 7.50, [0, 1, 2]),
            ("Espresso Coffee Beans", "Vittoria", "1kg", "fixture-coffee", "Pantry and Aisles", "Aisle 7", 26.00, [1, 3]),
            ("Paper Towel", "Viva", "4 pack", "fixture-towel", "Pantry and Aisles", "Aisle 15", 6.50, [0, 2]),
            ("Dark Chocolate Block", "Lindt", "100g", "fixture-chocolate", "Pantry and Aisles", "Aisle 9", 5.00, [2]),
        ]

        return (0..<4).map { weeksAgo in
            let completedAt = SampleDates.timestamp(SampleDates.day(1, from: SampleDates.weekStart(weeksAgo: weeksAgo)))
            let items = catalogue.enumerated().compactMap { index, entry -> SpendingTripItem? in
                guard entry.7.contains(weeksAgo) else { return nil }
                return SpendingTripItem(
                    id: "usuals-\(weeksAgo)-\(index)",
                    shoppingListItemId: nil,
                    name: entry.0,
                    quantity: "1",
                    checked: true,
                    sectionLabel: entry.4,
                    aisleLabel: entry.5,
                    sku: entry.3,
                    barcode: nil,
                    brand: entry.1,
                    size: entry.2,
                    priceAud: entry.6,
                    priceSource: "catalogue",
                    priceCapturedAt: completedAt,
                    origin: "manual",
                    spendCategory: "Other",
                    categorySource: "section"
                )
            }
            let total = items.compactMap(\.priceAud).reduce(0, +)
            return SpendingTripDetail(
                trip: SpendingTrip(
                    id: "usuals-trip-\(weeksAgo)",
                    shoppingListId: "usuals-list-\(weeksAgo)",
                    storeId: .topRyde,
                    storeName: "Coles Top Ryde",
                    completedAt: completedAt,
                    knownBasketTotalAud: total,
                    confirmedTotalAud: nil,
                    checkedItems: items.count,
                    pricedCheckedItems: items.count,
                    trackedTotalAud: total,
                    effectiveTotalAud: total,
                    checkoutDifferenceAud: 0,
                    priceCoverage: 1,
                    weeklyBudgetAud: 150,
                    weeklySpendAud: total,
                    weeklyBudgetRemainingAud: 150 - total
                ),
                categories: [],
                plannedSpendAud: 0,
                addedSpendAud: total,
                insightStatus: nil,
                insightCards: [],
                items: items
            )
        }
    }
}
#endif
