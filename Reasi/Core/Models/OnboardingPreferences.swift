import Foundation

enum OnboardingPurpose: String, CaseIterable, Codable, Identifiable {
    case saveMoney = "save_money"
    case saveShoppingTime = "save_shopping_time"
    case findProductsFaster = "find_products_faster"
    case understandSpending = "understand_spending"
    case reduceDinnerStress = "reduce_dinner_stress"
    case reduceFoodWaste = "reduce_food_waste"
    case eatHealthier = "eat_healthier"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saveMoney:
            "Groceries cost too much"
        case .saveShoppingTime:
            "Shopping takes too long"
        case .findProductsFaster:
            "Finding products is frustrating"
        case .understandSpending:
            "I lose track of grocery spending"
        case .reduceDinnerStress:
            "Deciding what to cook is stressful"
        case .reduceFoodWaste:
            "Food gets wasted"
        case .eatHealthier:
            "Eating well takes too much effort"
        }
    }

    var summary: String {
        switch self {
        case .saveMoney:
            "Compare value and stretch your weekly budget"
        case .saveShoppingTime:
            "Follow one quick route through your store"
        case .findProductsFaster:
            "Know the aisle and choose the exact product"
        case .understandSpending:
            "See where your grocery money goes"
        case .reduceDinnerStress:
            "Get practical dinners without the daily decision"
        case .reduceFoodWaste:
            "Reuse ingredients before they disappear"
        case .eatHealthier:
            "Make balanced choices easier to keep"
        }
    }

    var compactTitle: String {
        switch self {
        case .saveMoney: "Save money"
        case .saveShoppingTime: "Shop faster"
        case .findProductsFaster: "Find products"
        case .understandSpending: "Track spending"
        case .reduceDinnerStress: "Reduce dinner stress"
        case .reduceFoodWaste: "Waste less"
        case .eatHealthier: "Eat healthier"
        }
    }

    var symbol: String {
        switch self {
        case .saveMoney: "dollarsign"
        case .saveShoppingTime: "clock"
        case .findProductsFaster: "location.magnifyingglass"
        case .understandSpending: "chart.bar"
        case .reduceDinnerStress: "fork.knife"
        case .reduceFoodWaste: "arrow.3.trianglepath"
        case .eatHealthier: "leaf"
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
    var purposePriorities: [OnboardingPurpose]?
    var household: HouseholdChoice?
    var foodStyles: Set<FoodStyle>
    var selectedStoreId: StoreID?
    var completedAt: Date?
    var weeklyGroceryBudgetAud: Double?
    var spendingCoachTone: SpendingCoachTone

    init(
        purpose: OnboardingPurpose?,
        purposePriorities: [OnboardingPurpose]?,
        household: HouseholdChoice?,
        foodStyles: Set<FoodStyle>,
        selectedStoreId: StoreID?,
        completedAt: Date?,
        weeklyGroceryBudgetAud: Double? = nil,
        spendingCoachTone: SpendingCoachTone = .supportive
    ) {
        self.purpose = purpose
        self.purposePriorities = purposePriorities
        self.household = household
        self.foodStyles = foodStyles
        self.selectedStoreId = selectedStoreId
        self.completedAt = completedAt
        self.weeklyGroceryBudgetAud = weeklyGroceryBudgetAud
        self.spendingCoachTone = spendingCoachTone
    }

    static let empty = OnboardingPreferences(
        purpose: nil,
        purposePriorities: [],
        household: nil,
        foodStyles: [],
        selectedStoreId: nil,
        completedAt: nil,
        weeklyGroceryBudgetAud: nil,
        spendingCoachTone: .supportive
    )

    static let maximumPurposeSelections = 3

    static func normalizedPurposeSelection(_ values: [OnboardingPurpose]) -> [OnboardingPurpose] {
        var ordered: [OnboardingPurpose] = []
        for value in values where !ordered.contains(value) {
            ordered.append(value)
            if ordered.count == maximumPurposeSelections { break }
        }
        return ordered
    }

    var selectedPurposes: [OnboardingPurpose] {
        get {
            var candidates: [OnboardingPurpose] = []
            if let purpose {
                candidates.append(purpose)
            }
            candidates.append(contentsOf: (purposePriorities ?? []).prefix(Self.maximumPurposeSelections))
            return Self.normalizedPurposeSelection(candidates)
        }
        set {
            let ordered = Self.normalizedPurposeSelection(Array(newValue.prefix(Self.maximumPurposeSelections)))
            purpose = ordered.first
            purposePriorities = ordered
        }
    }

    var primaryPurpose: OnboardingPurpose? {
        selectedPurposes.first
    }

    var purposeSummary: String {
        let labels = selectedPurposes.map(\.compactTitle)
        return labels.isEmpty ? "Not set" : labels.joined(separator: ", ")
    }

    mutating func togglePurpose(_ value: OnboardingPurpose) {
        var selection = selectedPurposes
        if let index = selection.firstIndex(of: value) {
            selection.remove(at: index)
        } else if selection.count < Self.maximumPurposeSelections {
            selection.append(value)
        }
        selectedPurposes = selection
    }

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

    private enum CodingKeys: String, CodingKey {
        case purpose
        case purposePriorities
        case household
        case foodStyles
        case selectedStoreId
        case completedAt
        case weeklyGroceryBudgetAud
        case spendingCoachTone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        purpose = try container.decodeIfPresent(OnboardingPurpose.self, forKey: .purpose)
        purposePriorities = try container.decodeIfPresent([OnboardingPurpose].self, forKey: .purposePriorities)
        household = try container.decodeIfPresent(HouseholdChoice.self, forKey: .household)
        foodStyles = try container.decodeIfPresent(Set<FoodStyle>.self, forKey: .foodStyles) ?? []
        selectedStoreId = try container.decodeIfPresent(StoreID.self, forKey: .selectedStoreId)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        weeklyGroceryBudgetAud = try container.decodeIfPresent(Double.self, forKey: .weeklyGroceryBudgetAud)
        spendingCoachTone = try container.decodeIfPresent(SpendingCoachTone.self, forKey: .spendingCoachTone)
            ?? .supportive
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(purpose, forKey: .purpose)
        try container.encodeIfPresent(purposePriorities, forKey: .purposePriorities)
        try container.encodeIfPresent(household, forKey: .household)
        try container.encode(foodStyles, forKey: .foodStyles)
        try container.encodeIfPresent(selectedStoreId, forKey: .selectedStoreId)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(weeklyGroceryBudgetAud, forKey: .weeklyGroceryBudgetAud)
        try container.encode(spendingCoachTone, forKey: .spendingCoachTone)
    }
}
