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
        actualPriceAud: Double? = nil
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

struct ShoppingList: Identifiable, Codable, Hashable {
    let id: String
    let storeId: StoreID
    let storeName: String
    var sections: [ShoppingListSection]
}

enum WeekPlanSource: String, Codable, Hashable {
    case fixture
    case supabase
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

    func withMeals(_ meals: [MealSummary]) -> WeekPlan {
        WeekPlan(
            id: id,
            source: source,
            storeId: storeId,
            storeName: storeName,
            weekLabel: weekLabel,
            planningNotes: planningNotes,
            meals: meals,
            shoppingList: shoppingList
        )
    }
}

struct GenerateWeekPlanInput: Codable, Hashable {
    let storeId: StoreID
    let weekStart: String?
    let idempotencyKey: String?
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
