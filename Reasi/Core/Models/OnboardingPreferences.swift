import Foundation

enum OnboardingPurpose: String, CaseIterable, Codable, Identifiable {
    case saveMoney = "save_money"
    case reduceDinnerStress = "reduce_dinner_stress"
    case eatHealthier = "eat_healthier"
    case reduceFoodWaste = "reduce_food_waste"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saveMoney:
            "Save money on groceries"
        case .reduceDinnerStress:
            "Stop the what's-for-dinner stress"
        case .eatHealthier:
            "Eat healthier"
        case .reduceFoodWaste:
            "Waste less food"
        }
    }

    var summary: String {
        switch self {
        case .saveMoney:
            "Value-led meals and ingredient overlap"
        case .reduceDinnerStress:
            "Simple dinners with fewer decisions"
        case .eatHealthier:
            "Balanced, vegetable-forward meals"
        case .reduceFoodWaste:
            "Smarter reuse across the week"
        }
    }

    var symbol: String {
        switch self {
        case .saveMoney: "dollarsign"
        case .reduceDinnerStress: "moon.stars"
        case .eatHealthier: "leaf"
        case .reduceFoodWaste: "arrow.3.trianglepath"
        }
    }
}

enum HouseholdChoice: String, CaseIterable, Codable, Identifiable {
    case justMe = "just_me"
    case two = "two"
    case familyThreeFour = "family_3_4"
    case fivePlus = "five_plus"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .justMe: "Just me"
        case .two: "Two of us"
        case .familyThreeFour: "Family of 3-4"
        case .fivePlus: "5 or more"
        }
    }

    var householdSize: Int {
        switch self {
        case .justMe: 1
        case .two: 2
        case .familyThreeFour: 4
        case .fivePlus: 5
        }
    }
}

enum FoodStyle: String, CaseIterable, Codable, Identifiable {
    case vietnamese
    case chinese
    case mediterranean
    case quickDinners = "quick_dinners"
    case vegetarian
    case highProtein = "high_protein"
    case batchCook = "batch_cook"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vietnamese: "Vietnamese"
        case .chinese: "Chinese"
        case .mediterranean: "Mediterranean"
        case .quickDinners: "Quick dinners"
        case .vegetarian: "Vegetarian"
        case .highProtein: "High-protein"
        case .batchCook: "Batch cook"
        }
    }

    var isCuisine: Bool {
        switch self {
        case .vietnamese, .chinese, .mediterranean: true
        default: false
        }
    }
}

struct OnboardingPreferences: Codable, Equatable {
    var purpose: OnboardingPurpose?
    var household: HouseholdChoice?
    var foodStyles: Set<FoodStyle>
    var selectedStoreId: StoreID?
    var completedAt: Date?

    static let empty = OnboardingPreferences(
        purpose: nil,
        household: nil,
        foodStyles: [],
        selectedStoreId: nil,
        completedAt: nil
    )

    var householdSize: Int {
        household?.householdSize ?? 2
    }

    var cuisines: [String] {
        foodStyles
            .filter(\.isCuisine)
            .map(\.rawValue)
            .sorted()
    }

    var dietaryConstraints: [String] {
        foodStyles.contains(.vegetarian) ? [FoodStyle.vegetarian.rawValue] : []
    }

    var sortedFoodStyleValues: [String] {
        foodStyles.map(\.rawValue).sorted()
    }

    var resolvedStore: StoreSummary {
        FixtureStores.store(id: selectedStoreId) ?? FixtureStores.topRyde
    }
}
