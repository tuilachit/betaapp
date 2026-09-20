import Foundation

enum ReasiUserFacingCopy {
    private static let internalSourceMarkers = [
        "supabase",
        "posthog",
        "revenuecat",
        "edge function",
        "edge-function",
        "fixture fallback",
    ]

    private static let technicalReplacements = [
        ("Supabase Edge Function", "Reasi"),
        ("Edge Function", "Reasi"),
        ("Fixture fallback", "Preview data"),
        ("ChatGPT", "Reasi"),
        ("OpenAI", "Reasi"),
        ("Supabase", "Reasi"),
        ("PostHog", "Reasi"),
        ("RevenueCat", "Reasi"),
    ]

    static func text(_ value: String) -> String {
        technicalReplacements.reduce(value) { result, replacement in
            result.replacingOccurrences(
                of: replacement.0,
                with: replacement.1,
                options: .caseInsensitive
            )
        }
    }

    static func sourceName(_ value: String, sourceURL: URL?) -> String {
        let normalized = value.lowercased()

        if normalized.contains("openai") || normalized.contains("chatgpt") || normalized.contains("gpt-") {
            return publicHost(from: sourceURL) ?? "Web result"
        }

        if internalSourceMarkers.contains(where: normalized.contains) {
            return "Reasi"
        }

        return text(value)
    }

    private static func publicHost(from url: URL?) -> String? {
        guard var host = url?.host?.lowercased(), !host.isEmpty else { return nil }
        guard !internalSourceMarkers.contains(where: host.contains),
              !host.contains("openai") else { return nil }

        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }
}

extension String {
    var reasiUserFacingCopy: String {
        ReasiUserFacingCopy.text(self)
    }
}

struct RecipeIngredient: Identifiable, Codable, Hashable {
    var id: String { "\(name)-\(quantity)-\(category)" }
    let name: String
    let quantity: String
    let category: String
}

struct RecipeInfo: Codable, Hashable {
    let ingredients: [RecipeIngredient]
    let instructionsBrief: String
    let prepTimeMin: Int?
    let cookTimeMin: Int?
    let method: [String]?
    let serves: Int?

    var steps: [String] {
        if let method, !method.isEmpty {
            return method
        }

        return instructionsBrief
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix(".") ? $0 : "\($0)." }
    }

    var totalTimeMin: Int? {
        switch (prepTimeMin, cookTimeMin) {
        case let (.some(prep), .some(cook)):
            prep + cook
        case let (.some(prep), .none):
            prep
        case let (.none, .some(cook)):
            cook
        case (.none, .none):
            nil
        }
    }

    func normalized(fallbackCookTimeMin: Int) -> RecipeInfo {
        RecipeInfo(
            ingredients: ingredients,
            instructionsBrief: instructionsBrief,
            prepTimeMin: prepTimeMin,
            cookTimeMin: cookTimeMin ?? fallbackCookTimeMin,
            method: method,
            serves: serves
        )
    }
}

struct MealSummary: Identifiable, Codable, Hashable {
    let id: String
    let day: String
    let dish: String
    let description: String
    let cuisine: String
    let cookTimeMin: Int
    let costAud: Double
    let estimatedProteinG: Int
    let estimatedCalories: Int
    let estimatedCarbsG: Int
    let tone: String
    var recipe: RecipeInfo? = nil
    var imageUrl: URL? = nil
    var imageSourceName: String? = nil
    var imageSourceUrl: URL? = nil
    var imagePhotographerName: String? = nil
    var imagePhotographerUrl: URL? = nil

    func withRecipe(_ recipe: RecipeInfo?) -> MealSummary {
        MealSummary(
            id: id,
            day: day,
            dish: dish,
            description: description,
            cuisine: cuisine,
            cookTimeMin: cookTimeMin,
            costAud: costAud,
            estimatedProteinG: estimatedProteinG,
            estimatedCalories: estimatedCalories,
            estimatedCarbsG: estimatedCarbsG,
            tone: tone,
            recipe: recipe,
            imageUrl: imageUrl,
            imageSourceName: imageSourceName,
            imageSourceUrl: imageSourceUrl,
            imagePhotographerName: imagePhotographerName,
            imagePhotographerUrl: imagePhotographerUrl
        )
    }

    func withImageMetadata(from refreshed: MealSummary) -> MealSummary {
        MealSummary(
            id: id,
            day: day,
            dish: dish,
            description: description,
            cuisine: cuisine,
            cookTimeMin: cookTimeMin,
            costAud: costAud,
            estimatedProteinG: estimatedProteinG,
            estimatedCalories: estimatedCalories,
            estimatedCarbsG: estimatedCarbsG,
            tone: tone,
            recipe: recipe,
            imageUrl: refreshed.imageUrl ?? imageUrl,
            imageSourceName: refreshed.imageSourceName ?? imageSourceName,
            imageSourceUrl: refreshed.imageSourceUrl ?? imageSourceUrl,
            imagePhotographerName: refreshed.imagePhotographerName ?? imagePhotographerName,
            imagePhotographerUrl: refreshed.imagePhotographerUrl ?? imagePhotographerUrl
        )
    }
}

struct ProductSnapshot: Codable, Hashable {
    let sku: String?
    let productName: String?
    let brand: String?
    let size: String?
    let priceAud: Double?
    let imageUrl: URL?
    let capturedAt: String?
    var barcode: String? = nil
    var sourceName: String? = nil
    var observationId: String? = nil
    var actualPriceAud: Double? = nil
    var categoryGroup: String? = nil
    var category: String? = nil
    var subCategory: String? = nil
    var unitPriceAud: Double? = nil
    var purchaseQuantity: Int? = nil
    var requiredAmount: Double? = nil
    var requiredUnit: String? = nil
    var confidence: String? = nil
    var uncertaintyText: String? = nil

    init(
        sku: String?,
        productName: String?,
        brand: String?,
        size: String?,
        priceAud: Double?,
        imageUrl: URL?,
        capturedAt: String?,
        barcode: String? = nil,
        sourceName: String? = nil,
        observationId: String? = nil,
        actualPriceAud: Double? = nil,
        categoryGroup: String? = nil,
        category: String? = nil,
        subCategory: String? = nil,
        unitPriceAud: Double? = nil,
        purchaseQuantity: Int? = nil,
        requiredAmount: Double? = nil,
        requiredUnit: String? = nil,
        confidence: String? = nil,
        uncertaintyText: String? = nil
    ) {
        self.sku = sku
        self.productName = productName
        self.brand = brand
        self.size = size
        self.priceAud = priceAud
        self.imageUrl = imageUrl
        self.capturedAt = capturedAt
        self.barcode = barcode
        self.sourceName = sourceName
        self.observationId = observationId
        self.actualPriceAud = actualPriceAud
        self.categoryGroup = categoryGroup
        self.category = category
        self.subCategory = subCategory
        self.unitPriceAud = unitPriceAud
        self.purchaseQuantity = purchaseQuantity
        self.requiredAmount = requiredAmount
        self.requiredUnit = requiredUnit
        self.confidence = confidence
        self.uncertaintyText = uncertaintyText
    }

    init(candidate: ProductCandidate, actualPriceAud: Double? = nil) {
        sku = candidate.sku
        productName = candidate.displayName
        brand = candidate.brand
        size = candidate.size
        priceAud = actualPriceAud ?? candidate.priceAud
        imageUrl = candidate.imageUrl
        capturedAt = candidate.capturedAt
        barcode = candidate.barcode
        sourceName = candidate.sourceName
        observationId = candidate.observationId
        self.actualPriceAud = actualPriceAud
        categoryGroup = candidate.categoryGroup
        category = candidate.category
        subCategory = candidate.subCategory
        confidence = candidate.confidence.rawValue
        uncertaintyText = candidate.uncertaintyText
    }
}

/// Catalog prices are per sold pack. Basket totals account for every required pack.
struct ProductPurchaseEstimate {
    let amount: Double
    let unit: String

    private init(amount: Double, unit: String) {
        self.amount = amount
        self.unit = unit
    }

    /// Older plans use labels such as “1 small pack, about 300g”. Prefer their
    /// explicit weight/volume, without converting cups or handfuls into guesses.
    init?(shoppingQuantity: String, ingredientName: String) {
        let text = shoppingQuantity.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = Self(quantity: text) { self = exact; return }
        let weightPattern = #"(\d+(?:\.\d+)?)\s*(kg|g|ml|l)\b"#
        let weights = text.matches(of: try! Regex(weightPattern))
        if weights.count == 1,
           !text.contains(" or "), !text.contains("–"), !text.contains("-"),
           let match = weights.first,
           let measured = Self(quantity: String(text[match.range])) {
            let prefix = String(text[..<match.range.lowerBound])
            let suffix = String(text[match.range.upperBound...])
            guard !text.contains("+"), !text.contains(" per "),
                  suffix.range(of: #"^\s*(?:pack|bottle|jar|can|tub|total)?\s*\)?$"#, options: .regularExpression) != nil else { return nil }
            if let multiplierMatch = prefix.range(of: #"^\d+\s*[x×]\s*$"#, options: .regularExpression),
               let multiplier = Double(prefix[multiplierMatch].replacingOccurrences(of: #"[^\d]"#, with: "", options: .regularExpression)) {
                self.init(amount: measured.amount * multiplier, unit: measured.unit)
                return
            }
            // A second number is only safe when the label explicitly states the total.
            if prefix.rangeOfCharacter(from: .decimalDigits) != nil,
               !prefix.contains("about"), !prefix.contains("approx"), !prefix.contains("total") { return nil }
            self = measured
            return
        }
        let words = text.split(separator: " ").map(String.init)
        guard let first = words.first, let count = Double(first), count.isFinite, count > 0 else { return nil }
        let qualifiers: Set<String> = ["small", "medium", "large", "whole"]
        let ingredientWords = Set(ShoppingProductMatcher.tokens(ingredientName))
        let remainder = words.dropFirst().filter { !qualifiers.contains($0) }
        if remainder.isEmpty || Set(ShoppingProductMatcher.tokens(remainder.joined(separator: " "))).isSubset(of: ingredientWords) {
            self.init(amount: count, unit: "each")
        } else if let measure = Self(quantity: "\(first) \(remainder.joined(separator: " "))") {
            self = measure
        } else {
            return nil
        }
    }

    init?(quantity: String) {
        let pattern = #"^(\d+(?:\.\d+)?)\s*(kg|g|grams?|kilograms?|ml|l|litres?|each|ea|units?|pieces?|bulbs?|heads?|packs?|packets?|bottles?|jars?|cans?|tubs?|bunch(?:es)?|punnets?)$"#
        let text = quantity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[numberRange]), value.isFinite, value > 0 else { return nil }
        let parsedUnit = String(text[unitRange])
        switch parsedUnit {
        case "kg", "kilogram", "kilograms": amount = value * 1_000; unit = "g"
        case "g", "gram", "grams": amount = value; unit = "g"
        case "l", "litre", "litres": amount = value * 1_000; unit = "ml"
        case "ml": amount = value; unit = "ml"
        case "each", "ea", "unit", "units", "piece", "pieces", "bulb", "bulbs", "head", "heads": amount = value; unit = "each"
        default: amount = value; unit = "pack"
        }
    }

    func packCount(for candidate: ProductCandidate) -> Int? {
        if unit == "pack" { return boundedCount(amount) }
        let size = (candidate.size ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if unit == "each", candidate.displayName.lowercased().contains("loose") || size.contains("each") {
            return boundedCount(amount)
        }
        let cleanSize = size.replacingOccurrences(of: #"^approx\.?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+each$"#, with: "", options: .regularExpression)
        let components = cleanSize.components(separatedBy: CharacterSet(charactersIn: "x×"))
        let multiplier = components.count == 2 ? Double(components[0].trimmingCharacters(in: .whitespaces)) : 1
        guard let multiplier, multiplier.isFinite, multiplier > 0,
              let pack = ProductPurchaseEstimate(quantity: components.last ?? cleanSize),
              pack.unit == unit || (unit == "each" && pack.unit == "pack") else { return nil }
        return boundedCount(amount / (pack.amount * multiplier))
    }

    private func boundedCount(_ value: Double) -> Int? {
        guard value.isFinite, value > 0, value <= 100 else { return nil }
        return Int(ceil(value))
    }

    static func snapshot(candidate: ProductCandidate, item: ShoppingListItem, actualUnitPrice: Double? = nil) -> ProductSnapshot {
        let requirement = ProductPurchaseEstimate(shoppingQuantity: item.quantity, ingredientName: item.name)
        let count = requirement?.packCount(for: candidate)
        let unitPrice = actualUnitPrice ?? candidate.priceAud
        let validPrice = unitPrice.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let total = count.flatMap { count in validPrice.map { ($0 * 100).rounded() * Double(count) / 100 } }
        var snapshot = ProductSnapshot(candidate: candidate)
        snapshot = ProductSnapshot(
            sku: snapshot.sku, productName: snapshot.productName, brand: snapshot.brand, size: snapshot.size,
            priceAud: total, imageUrl: snapshot.imageUrl, capturedAt: snapshot.capturedAt,
            barcode: snapshot.barcode, sourceName: snapshot.sourceName, observationId: snapshot.observationId,
            actualPriceAud: actualUnitPrice == nil ? nil : total,
            categoryGroup: snapshot.categoryGroup, category: snapshot.category, subCategory: snapshot.subCategory,
            unitPriceAud: validPrice, purchaseQuantity: count, requiredAmount: requirement?.amount, requiredUnit: requirement?.unit,
            confidence: snapshot.confidence, uncertaintyText: snapshot.uncertaintyText
        )
        return snapshot
    }
}

/// A search hit is not necessarily the ingredient requested (ginger beer, for
/// example). Only choose actual retailer SKUs whose identity matches the list.
enum ShoppingProductMatcher {
    static func tokens(_ value: String) -> [String] {
        value.lowercased().replacingOccurrences(of: "corn flour", with: "cornflour")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0 != "fresh" }
            .map { word in
                if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
                return word
            }
    }

    static func matches(_ ingredient: String, candidate: ProductCandidate, storeId: StoreID) -> Bool {
        let retailer = storeId == .woolworthsRhodes ? "woolworths" : "coles"
        guard candidate.sku?.isEmpty == false, candidate.imageUrl?.scheme == "https",
              candidate.confidence != .low,
              (candidate.retailer ?? candidate.sourceName).lowercased().contains(retailer) else { return false }
        let name = Set(tokens(candidate.name))
        let alternatives = ingredient.components(separatedBy: "/").map { Set(tokens($0)) }
        guard let requested = alternatives.first(where: { !$0.isEmpty && $0.isSubset(of: name) }) else { return false }
        let forms: Set<String> = ["sauce", "paste", "powder", "ground", "dried", "soup", "stock", "juice", "drink", "beer", "gin", "flavoured", "seasoning", "marinated", "crumbed", "salt", "butter", "oil", "bread", "chip", "cracker", "spread", "dip", "pesto", "pickled", "crushed", "grated", "chopped", "jam", "marmalade", "conserve", "syrup", "biscuit", "chocolate", "candy"]
        guard name.intersection(forms).subtracting(requested).isEmpty else { return false }
        let proteins: Set<String> = ["beef", "pork", "chicken", "turkey", "lamb", "duck", "fish", "salmon", "tuna", "prawn", "tofu"]
        guard name.intersection(proteins).subtracting(requested).isEmpty else { return false }
        if requested.contains("onion"), !requested.contains("shallot"), name.contains("shallot") { return false }
        if ingredient.localizedCaseInsensitiveContains("fresh"), !name.intersection(["frozen", "dried", "grated", "paste"]).isEmpty { return false }
        return true
    }

    static func choose(for item: ShoppingListItem, candidates: [ProductCandidate], storeId: StoreID) -> ProductCandidate? {
        candidates.filter { matches(item.name, candidate: $0, storeId: storeId) }
            .sorted { left, right in
                let a = ProductPurchaseEstimate.snapshot(candidate: left, item: item)
                let b = ProductPurchaseEstimate.snapshot(candidate: right, item: item)
                // Compare the full number of packs, not the cheapest shelf ticket.
                if a.priceAud != b.priceAud { return (a.priceAud ?? .infinity) < (b.priceAud ?? .infinity) }
                if a.purchaseQuantity != b.purchaseQuantity { return (a.purchaseQuantity ?? 101) < (b.purchaseQuantity ?? 101) }
                return (left.priceAud ?? .infinity) < (right.priceAud ?? .infinity)
            }.first
    }
}

struct AutomaticProductSelection {
    let item: ShoppingListItem
    let candidate: ProductCandidate
    let snapshot: ProductSnapshot
    let shoppingListId: String
    let sectionLabel: String
    let sectionSortKey: Int
    let sectionType: ShoppingSectionType
}

enum ProductSelectionIssue: LocalizedError {
    case quantityOrPriceUnknown
    case overBudget(Double)

    var errorDescription: String? {
        switch self {
        case .quantityOrPriceUnknown: "We can’t confirm the price for the quantity you need. Choose a product with a matching pack size and price."
        case .overBudget(let amount): "This change would put your estimated basket \(amount.formatted(.currency(code: "AUD"))) over budget. Choose a lower-cost product."
        }
    }
}

enum ProductConfidence: String, Codable, Hashable, CaseIterable {
    case high
    case medium
    case low

    var label: String {
        switch self {
        case .high:
            "High confidence"
        case .medium:
            "Medium confidence"
        case .low:
            "Low confidence"
        }
    }
}

struct ProductCandidate: Identifiable, Codable, Hashable {
    var id: String { observationId ?? sku ?? barcode ?? "\(name)-\(sourceName)-\(size ?? "")" }
    let observationId: String?
    let name: String
    let brand: String?
    let size: String?
    let priceAud: Double?
    let unitPriceAud: Double?
    let unitQuantity: Double?
    let unitMeasure: String?
    let comparablePrice: String?
    let imageUrl: URL?
    let productUrl: URL?
    let sourceName: String
    let sourceUrl: URL?
    let capturedAt: String?
    let freshnessLabel: String
    let confidence: ProductConfidence
    let confidenceReason: String
    let uncertaintyText: String
    var sku: String? = nil
    var barcode: String? = nil
    var retailer: String? = nil
    var aisleLabel: String? = nil
    var sectionLabel: String? = nil
    var sectionSortKey: Int? = nil
    var sectionType: ShoppingSectionType? = nil
    var categoryGroup: String? = nil
    var category: String? = nil
    var subCategory: String? = nil

    var displayName: String {
        if let brand, !brand.isEmpty, !name.localizedCaseInsensitiveContains(brand) {
            return "\(brand) \(name)"
        }
        return name
    }

    var userFacingSourceName: String {
        ReasiUserFacingCopy.sourceName(sourceName, sourceURL: sourceUrl)
    }
}

struct ProductImportResult: Codable, Hashable {
    let batchId: String?
    let candidates: [ProductCandidate]
}

enum ListExtractionGroup: String, Codable, Hashable {
    case matched
    case needsReview = "needs_review"
    case uncertain
}

struct ListExtractionCandidate: Identifiable, Codable, Hashable {
    var id: String { productCandidate?.id ?? "\(extractedName)-\(quantity ?? "")-\(group.rawValue)" }
    let extractedName: String
    let quantity: String?
    let group: ListExtractionGroup
    let confidence: ProductConfidence
    let confidenceReason: String
    let productCandidate: ProductCandidate?
}

struct ListExtractionResult: Codable, Hashable {
    let batchId: String?
    let matched: [ListExtractionCandidate]
    let needsReview: [ListExtractionCandidate]
    let uncertain: [ListExtractionCandidate]
    let items: [ListExtractionCandidate]
}

struct ProductComparisonRow: Identifiable, Codable, Hashable {
    var id: String { observationId }
    let observationId: String
    let name: String
    let brand: String?
    let size: String?
    let priceAud: Double?
    let unitPriceAud: Double?
    let unitMeasure: String?
    let unitValueText: String
    let sourceName: String
    let sourceUrl: URL?
    let freshnessLabel: String
    let confidence: ProductConfidence
    let caveat: String

    var userFacingSourceName: String {
        ReasiUserFacingCopy.sourceName(sourceName, sourceURL: sourceUrl)
    }
}

struct ProductComparisonResult: Codable, Hashable {
    let rows: [ProductComparisonRow]
    let bestUnitValueObservationId: String?
    let caveats: [String]
}

enum AssistantMessageRole: String, Codable, Hashable {
    case user
    case assistant
}

struct AssistantMessage: Identifiable, Codable, Hashable {
    let id: String
    let role: AssistantMessageRole
    let content: String
    let cards: [AssistantCard]
    let caveats: [String]
    let createdAt: String?
}

struct AssistantCard: Identifiable, Codable, Hashable {
    var id: String { "\(type)-\(title)-\(sourceName ?? "")" }
    let type: String
    let title: String
    let body: String?
    let confidence: ProductConfidence?
    let sourceName: String?
    let freshnessLabel: String?
}

struct AssistantResponse: Codable, Hashable {
    let threadId: String
    let message: AssistantMessage
    let mutations: [AssistantListMutation]?

    var appliedMutations: [AssistantListMutation] { mutations ?? [] }
}

struct AssistantListMutation: Codable, Hashable {
    let operation: String
    let itemId: String
    let name: String
    let quantity: String?
    let checked: Bool?
    let sectionLabel: String?
    let sectionSortKey: Int?
    let sectionType: ShoppingSectionType?
    let aisleLabel: String?
}

enum ShoppingSectionType: String, Codable, Hashable {
    case numbered
    case perimeter
    case unknown
}

struct ShoppingListItem: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let quantity: String
    var checked: Bool
    let aisleLabel: String?
    let sectionType: ShoppingSectionType
    let product: ProductSnapshot?
    var importedCandidate: ProductCandidate? = nil
    var locationUncertaintyText: String? = nil
    var clientId: String? = nil
}

struct ShoppingListSection: Identifiable, Codable, Hashable {
    var id: String { "\(sortKey)-\(label)" }
    let label: String
    let sortKey: Int
    let type: ShoppingSectionType
    var items: [ShoppingListItem]
}

enum ShoppingListStatus: String, Codable, Hashable {
    case active
    case completed
    case archived
}

struct ShoppingList: Identifiable, Codable, Hashable {
    let id: String
    let storeId: StoreID
    let storeName: String
    var sections: [ShoppingListSection]
    var status: ShoppingListStatus = .active
    var completedAt: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, storeId, storeName, sections, status, completedAt
    }

    init(
        id: String,
        storeId: StoreID,
        storeName: String,
        sections: [ShoppingListSection],
        status: ShoppingListStatus = .active,
        completedAt: String? = nil
    ) {
        self.id = id
        self.storeId = storeId
        self.storeName = storeName
        self.sections = sections
        self.status = status
        self.completedAt = completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        storeId = try container.decode(StoreID.self, forKey: .storeId)
        storeName = try container.decode(String.self, forKey: .storeName)
        sections = try container.decode([ShoppingListSection].self, forKey: .sections)
        status = try container.decodeIfPresent(ShoppingListStatus.self, forKey: .status) ?? .active
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
    }
}

struct BasketPriceSummary: Equatable {
    let inBasketTotalAud: Double
    let plannedTotalAud: Double
    let pricedItemCount: Int
    let totalItemCount: Int
    let pricedCheckedItemCount: Int
    let checkedItemCount: Int

    init(items: [ShoppingListItem]) {
        totalItemCount = items.count
        checkedItemCount = items.filter(\.checked).count

        let priced = items.compactMap { item -> (ShoppingListItem, Double)? in
            guard let price = item.product?.actualPriceAud ?? item.product?.priceAud,
                  price.isFinite,
                  price >= 0 else { return nil }
            return (item, price)
        }

        pricedItemCount = priced.count
        pricedCheckedItemCount = priced.filter { $0.0.checked }.count
        plannedTotalAud = priced.reduce(0) { $0 + $1.1 }
        inBasketTotalAud = priced.reduce(0) { total, entry in
            entry.0.checked ? total + entry.1 : total
        }
    }

    var unpricedCheckedItemCount: Int {
        max(0, checkedItemCount - pricedCheckedItemCount)
    }

    var coverageFraction: Double {
        guard totalItemCount > 0 else { return 0 }
        return Double(pricedItemCount) / Double(totalItemCount)
    }

    func issueReplacing(_ item: ShoppingListItem, with product: ProductSnapshot, budget: Double?) -> ProductSelectionIssue? {
        guard let budget, budget.isFinite, budget > 0 else { return nil }
        guard let price = product.priceAud, price.isFinite, price >= 0 else { return .quantityOrPriceUnknown }
        let previous = item.product?.actualPriceAud ?? item.product?.priceAud ?? 0
        let updatedCents = ((plannedTotalAud - previous + price) * 100).rounded()
        let budgetCents = (budget * 100).rounded()
        return updatedCents > budgetCents ? .overBudget((updatedCents - budgetCents) / 100) : nil
    }
}

struct ShoppingTripSummary: Codable, Hashable {
    let tripId: String
    let shoppingListId: String
    let storeId: StoreID
    let storeName: String
    let totalItems: Int
    let checkedItems: Int
    let pricedItems: Int
    let pricedCheckedItems: Int
    let knownPlannedTotalAud: Double
    let knownBasketTotalAud: Double
    let completedAt: String
    let alreadyCompleted: Bool
}

enum WeekPlanSource: String, Codable, Hashable {
    case fixture
    case supabase
}

enum PlanKind: String, Codable, Hashable, CaseIterable {
    case week
    case occasion

    var title: String { self == .week ? "Week" : "Occasion" }
    var planHeading: String { self == .week ? "Your week" : "Your evening" }
    var defaultDesiredCount: Int { self == .week ? 7 : 3 }
}

enum EntryMethod: String, Codable, Hashable {
    case describe
    case build
}

enum IdeaType: String, Codable, Hashable {
    case dish
    case product
    case listItem = "list_item"
}

enum ProductRole: String, Codable, Hashable, CaseIterable {
    case useInPlan = "use_in_plan"
    case alreadyHave = "already_have"
    case addToList = "add_to_list"

    var title: String {
        switch self {
        case .useInPlan: "Use in plan"
        case .alreadyHave: "Already have"
        case .addToList: "Add to shopping list"
        }
    }
}

struct PlanIdea: Identifiable, Codable, Hashable {
    let id: String
    var type: IdeaType
    var title: String
    var detail: String?
    var sourceURL: URL?
    var imageUploadPath: String?
    var product: ProductCandidate?
    var productRole: ProductRole?
    var isRequired: Bool
    var courseHint: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, detail, product, productRole, courseHint
        case sourceURL = "sourceUrl"
        case legacySourceURL = "sourceURL"
        case imageUploadPath = "uploadPath"
        case legacyImageUploadPath = "imageUploadPath"
        case isRequired = "mustKeep"
        case legacyIsRequired = "isRequired"
    }

    init(
        id: String = UUID().uuidString,
        type: IdeaType,
        title: String,
        detail: String? = nil,
        sourceURL: URL? = nil,
        imageUploadPath: String? = nil,
        product: ProductCandidate? = nil,
        productRole: ProductRole? = nil,
        isRequired: Bool = true,
        courseHint: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.sourceURL = sourceURL
        self.imageUploadPath = imageUploadPath
        self.product = product
        self.productRole = type == .product ? (productRole ?? .useInPlan) : productRole
        self.isRequired = isRequired
        self.courseHint = courseHint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        type = try container.decode(IdeaType.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
            ?? container.decodeIfPresent(URL.self, forKey: .legacySourceURL)
        imageUploadPath = try container.decodeIfPresent(String.self, forKey: .imageUploadPath)
            ?? container.decodeIfPresent(String.self, forKey: .legacyImageUploadPath)
        product = try container.decodeIfPresent(ProductCandidate.self, forKey: .product)
        productRole = try container.decodeIfPresent(ProductRole.self, forKey: .productRole)
            ?? (type == .product ? .useInPlan : nil)
        isRequired = try container.decodeIfPresent(Bool.self, forKey: .isRequired)
            ?? container.decodeIfPresent(Bool.self, forKey: .legacyIsRequired)
            ?? true
        courseHint = try container.decodeIfPresent(String.self, forKey: .courseHint)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(imageUploadPath, forKey: .imageUploadPath)
        try container.encodeIfPresent(product, forKey: .product)
        try container.encodeIfPresent(productRole, forKey: .productRole)
        try container.encode(isRequired, forKey: .isRequired)
        try container.encodeIfPresent(courseHint, forKey: .courseHint)
    }
}

struct PlanBrief: Codable, Hashable {
    static let currentVersion = 1

    var version: Int = Self.currentVersion
    var kind: PlanKind
    var entryMethod: EntryMethod
    var briefText: String
    var serves: Int
    var occasionAt: Date?
    var budgetTargetAud: Double?
    var desiredCount: Int
    var ideas: [PlanIdea]

    enum CodingKeys: String, CodingKey {
        case version, kind, entryMethod, briefText, serves, occasionAt
        case budgetTargetAud, ideas
        case desiredCount = "desiredMealCount"
        case legacyDesiredCount = "desiredCount"
    }

    init(
        kind: PlanKind,
        entryMethod: EntryMethod,
        briefText: String = "",
        serves: Int = 2,
        occasionAt: Date? = nil,
        budgetTargetAud: Double? = nil,
        desiredCount: Int? = nil,
        ideas: [PlanIdea] = []
    ) {
        self.kind = kind
        self.entryMethod = entryMethod
        self.briefText = briefText
        self.serves = serves
        self.occasionAt = occasionAt
        self.budgetTargetAud = budgetTargetAud
        self.desiredCount = desiredCount ?? kind.defaultDesiredCount
        self.ideas = ideas
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        kind = try container.decode(PlanKind.self, forKey: .kind)
        entryMethod = try container.decode(EntryMethod.self, forKey: .entryMethod)
        briefText = try container.decodeIfPresent(String.self, forKey: .briefText) ?? ""
        serves = try container.decodeIfPresent(Int.self, forKey: .serves) ?? 2
        if let dateString = try? container.decode(String.self, forKey: .occasionAt) {
            occasionAt = Self.parseDate(dateString)
        } else {
            occasionAt = try container.decodeIfPresent(Date.self, forKey: .occasionAt)
        }
        budgetTargetAud = try container.decodeIfPresent(Double.self, forKey: .budgetTargetAud)
        desiredCount = try container.decodeIfPresent(Int.self, forKey: .desiredCount)
            ?? container.decodeIfPresent(Int.self, forKey: .legacyDesiredCount)
            ?? kind.defaultDesiredCount
        ideas = try container.decodeIfPresent([PlanIdea].self, forKey: .ideas) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(kind, forKey: .kind)
        try container.encode(entryMethod, forKey: .entryMethod)
        try container.encode(briefText, forKey: .briefText)
        try container.encode(serves, forKey: .serves)
        try container.encodeIfPresent(occasionAt.map(Self.formatDate), forKey: .occasionAt)
        try container.encodeIfPresent(budgetTargetAud, forKey: .budgetTargetAud)
        try container.encode(desiredCount, forKey: .desiredCount)
        try container.encode(ideas, forKey: .ideas)
    }

    func mergingClientMetadata(from original: PlanBrief) -> PlanBrief {
        var merged = self
        let originalByID = Dictionary(uniqueKeysWithValues: original.ideas.map { ($0.id, $0) })
        merged.ideas = ideas.map { interpreted in
            guard let local = originalByID[interpreted.id] else { return interpreted }
            var value = interpreted
            value.detail = local.detail ?? interpreted.detail
            value.product = local.product
            value.sourceURL = local.sourceURL ?? interpreted.sourceURL
            value.imageUploadPath = local.imageUploadPath ?? interpreted.imageUploadPath
            value.courseHint = local.courseHint ?? interpreted.courseHint
            return value
        }
        return merged
    }

    private static func formatDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct PlanBudgetCoverage: Hashable {
    let knownSubtotalAud: Double
    let pricedProductCount: Int
    let eligibleProductCount: Int

    init(ideas: [PlanIdea]) {
        let eligible = ideas.filter { $0.type == .product && $0.productRole != .alreadyHave }
        let prices = eligible.compactMap { $0.product?.priceAud }
        knownSubtotalAud = prices.reduce(0, +)
        pricedProductCount = prices.count
        eligibleProductCount = eligible.count
    }

    var fraction: Double {
        guard eligibleProductCount > 0 else { return 0 }
        return Double(pricedProductCount) / Double(eligibleProductCount)
    }
}

struct PlanGapRecommendation: Identifiable, Codable, Hashable {
    var id: String { title }
    let title: String
    let reason: String
    let courseRole: String?

    enum CodingKeys: String, CodingKey {
        case title, reason, courseRole
        case snakeCourseRole = "course_role"
    }

    init(title: String, reason: String, courseRole: String?) {
        self.title = title
        self.reason = reason
        self.courseRole = courseRole
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        reason = try container.decode(String.self, forKey: .reason)
        courseRole = try container.decodeIfPresent(String.self, forKey: .courseRole)
            ?? container.decodeIfPresent(String.self, forKey: .snakeCourseRole)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(reason, forKey: .reason)
        try container.encodeIfPresent(courseRole, forKey: .courseRole)
    }
}

struct PlanInterpretation: Codable, Hashable {
    let normalizedBrief: PlanBrief?
    let clarification: String?
    let clarificationOptions: [String]
    let recommendation: PlanGapRecommendation?
    let swaps: [PlanGapRecommendation]
    let notes: [String]

    enum CodingKeys: String, CodingKey {
        case normalizedBrief
        case snakeNormalizedBrief = "normalized_brief"
        case clarification
        case recommendation
        case swaps
        case alternatives
        case notes
        case budgetNote
    }

    init(
        normalizedBrief: PlanBrief?,
        clarification: String?,
        clarificationOptions: [String] = [],
        recommendation: PlanGapRecommendation?,
        swaps: [PlanGapRecommendation],
        notes: [String]
    ) {
        self.normalizedBrief = normalizedBrief
        self.clarification = clarification
        self.clarificationOptions = clarificationOptions
        self.recommendation = recommendation
        self.swaps = Array(swaps.prefix(2))
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        normalizedBrief = try container.decodeIfPresent(PlanBrief.self, forKey: .normalizedBrief)
            ?? container.decodeIfPresent(PlanBrief.self, forKey: .snakeNormalizedBrief)
        if let value = try? container.decodeIfPresent(String.self, forKey: .clarification) {
            clarification = value
            clarificationOptions = []
        } else if let value = try container.decodeIfPresent(PlanClarification.self, forKey: .clarification) {
            clarification = value.question
            clarificationOptions = value.options
        } else {
            clarification = nil
            clarificationOptions = []
        }
        recommendation = try container.decodeIfPresent(PlanGapRecommendation.self, forKey: .recommendation)
        let decodedSwaps = try container.decodeIfPresent([PlanGapRecommendation].self, forKey: .swaps)
            ?? container.decodeIfPresent([PlanGapRecommendation].self, forKey: .alternatives)
            ?? []
        swaps = Array(decodedSwaps.prefix(2))
        if let decodedNotes = try container.decodeIfPresent([String].self, forKey: .notes) {
            notes = decodedNotes
        } else if let budgetNote = try container.decodeIfPresent(String.self, forKey: .budgetNote) {
            notes = [budgetNote]
        } else {
            notes = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(normalizedBrief, forKey: .normalizedBrief)
        try container.encodeIfPresent(clarification, forKey: .clarification)
        try container.encodeIfPresent(recommendation, forKey: .recommendation)
        try container.encode(swaps, forKey: .swaps)
        try container.encode(notes, forKey: .notes)
    }
}

private struct PlanClarification: Codable, Hashable {
    let question: String
    let options: [String]
}

struct ResolvedMealIdea: Codable, Hashable {
    let title: String
    let description: String?
    let cuisine: String?
    let sourceURL: URL?
    let imageURL: URL?
    let confidence: ProductConfidence
    let confidenceReason: String
    let recipe: RecipeInfo?
    let product: ProductCandidate?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case cuisine
        case sourceURL
        case imageURL
        case confidence
        case confidenceReason
        case recipe
        case product
        case snakeSourceURL = "source_url"
        case snakeImageURL = "image_url"
        case snakeConfidenceReason = "confidence_reason"
    }

    init(
        title: String,
        description: String?,
        cuisine: String?,
        sourceURL: URL?,
        imageURL: URL?,
        confidence: ProductConfidence,
        confidenceReason: String,
        recipe: RecipeInfo?,
        product: ProductCandidate?
    ) {
        self.title = title
        self.description = description
        self.cuisine = cuisine
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.confidence = confidence
        self.confidenceReason = confidenceReason
        self.recipe = recipe
        self.product = product
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        cuisine = try container.decodeIfPresent(String.self, forKey: .cuisine)
        sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
            ?? container.decodeIfPresent(URL.self, forKey: .snakeSourceURL)
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
            ?? container.decodeIfPresent(URL.self, forKey: .snakeImageURL)
        confidence = try container.decode(ProductConfidence.self, forKey: .confidence)
        confidenceReason = try container.decodeIfPresent(String.self, forKey: .confidenceReason)
            ?? container.decodeIfPresent(String.self, forKey: .snakeConfidenceReason)
            ?? "No confidence explanation was provided."
        recipe = try container.decodeIfPresent(RecipeInfo.self, forKey: .recipe)
        product = try container.decodeIfPresent(ProductCandidate.self, forKey: .product)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(cuisine, forKey: .cuisine)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(confidenceReason, forKey: .confidenceReason)
        try container.encodeIfPresent(recipe, forKey: .recipe)
        try container.encodeIfPresent(product, forKey: .product)
    }
}

struct RecentPlanSummary: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let kind: PlanKind
    let storeId: StoreID?
    let createdAt: String?
}

struct WeekPlan: Identifiable, Codable, Hashable {
    let id: String
    let source: WeekPlanSource
    let storeId: StoreID
    let storeName: String
    let weekLabel: String
    let planningNotes: String
    let meals: [MealSummary]
    var shoppingList: ShoppingList
    var kind: PlanKind = .week
    var entryMethod: EntryMethod? = nil
    var occasionAt: Date? = nil
    var budgetTargetAud: Double? = nil

    enum CodingKeys: String, CodingKey {
        case id, source, storeId, storeName, weekLabel, planningNotes, meals, shoppingList
        case kind, entryMethod, occasionAt, budgetTargetAud
    }

    init(
        id: String,
        source: WeekPlanSource,
        storeId: StoreID,
        storeName: String,
        weekLabel: String,
        planningNotes: String,
        meals: [MealSummary],
        shoppingList: ShoppingList,
        kind: PlanKind = .week,
        entryMethod: EntryMethod? = nil,
        occasionAt: Date? = nil,
        budgetTargetAud: Double? = nil
    ) {
        self.id = id
        self.source = source
        self.storeId = storeId
        self.storeName = storeName
        self.weekLabel = weekLabel
        self.planningNotes = planningNotes
        self.meals = meals
        self.shoppingList = shoppingList
        self.kind = kind
        self.entryMethod = entryMethod
        self.occasionAt = occasionAt
        self.budgetTargetAud = budgetTargetAud
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        source = try container.decode(WeekPlanSource.self, forKey: .source)
        storeId = try container.decode(StoreID.self, forKey: .storeId)
        storeName = try container.decode(String.self, forKey: .storeName)
        weekLabel = try container.decode(String.self, forKey: .weekLabel)
        planningNotes = try container.decode(String.self, forKey: .planningNotes)
        meals = try container.decode([MealSummary].self, forKey: .meals)
        shoppingList = try container.decode(ShoppingList.self, forKey: .shoppingList)
        kind = try container.decodeIfPresent(PlanKind.self, forKey: .kind) ?? .week
        entryMethod = try container.decodeIfPresent(EntryMethod.self, forKey: .entryMethod)
        occasionAt = try container.decodeIfPresent(Date.self, forKey: .occasionAt)
        budgetTargetAud = try container.decodeIfPresent(Double.self, forKey: .budgetTargetAud)
    }

    func withMeals(_ meals: [MealSummary]) -> WeekPlan {
        WeekPlan(
            id: id,
            source: source,
            storeId: storeId,
            storeName: storeName,
            weekLabel: weekLabel,
            planningNotes: planningNotes,
            meals: meals,
            shoppingList: shoppingList,
            kind: kind,
            entryMethod: entryMethod,
            occasionAt: occasionAt,
            budgetTargetAud: budgetTargetAud
        )
    }
}

struct GenerateWeekPlanInput: Codable, Hashable {
    let storeId: StoreID
    let weekStart: String?
    let idempotencyKey: String?
    var planBrief: PlanBrief? = nil
}

enum GenerationRequestStatus: String, Codable, Hashable {
    case queued
    case inProgress = "in_progress"
    case cancelRequested = "cancel_requested"
    case completed
    case failed
    case expired

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .expired:
            true
        case .queued, .inProgress, .cancelRequested:
            false
        }
    }
}

enum GenerationRequestStage: String, Codable, Hashable {
    case preparing
    case planningMeals = "planning_meals"
    case organizingStoreRoute = "organizing_store_route"
    case ready
    case cancelled
    case failed
    case expired
}

struct WeekPlanGenerationRequest: Codable, Hashable {
    let requestId: String
    let status: GenerationRequestStatus
    let stage: GenerationRequestStage
    let storeId: StoreID?
    let weekStart: String?
    let mealPlanId: String?
    let shoppingListId: String?
    let errorCode: String?
    let message: String?
    let expiresAt: String?
    let accessMode: String?
    let createdAt: String?
}

enum WeekPlanGenerationStartResult: Hashable {
    case request(WeekPlanGenerationRequest)
    case fixture(WeekPlan)
}
