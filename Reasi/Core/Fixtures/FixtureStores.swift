import Foundation

enum FixtureStores {
    static let topRyde = StoreSummary(
        id: .topRyde,
        retailer: "coles",
        name: "Coles Top Ryde",
        shortName: "Top Ryde"
    )

    static let eastVillage = StoreSummary(
        id: .eastVillage,
        retailer: "coles",
        name: "Coles East Village",
        shortName: "East Village"
    )

    static let rhodes = StoreSummary(
        id: .rhodes,
        retailer: "coles",
        name: "Coles Rhodes",
        shortName: "Rhodes"
    )

    static let surryHills = StoreSummary(
        id: .surryHills,
        retailer: "coles",
        name: "Coles Surry Hills",
        shortName: "Surry Hills"
    )

    static let woolworthsRhodes = StoreSummary(
        id: .woolworthsRhodes,
        retailer: "woolworths",
        name: "Woolworths Rhodes",
        shortName: "Woolies Rhodes"
    )

    static let launchStores = [topRyde, eastVillage, rhodes, surryHills, woolworthsRhodes]

    static func store(id: StoreID?) -> StoreSummary? {
        guard let id else { return nil }
        return launchStores.first { $0.id == id }
    }
}

enum FixtureWeekPlan {
    static let current = WeekPlan(
        id: "fixture-week-plan",
        source: .fixture,
        storeId: .topRyde,
        storeName: "Coles Top Ryde",
        weekLabel: "July 13 - 19",
        planningNotes: "A calm seven-dinner plan with shared herbs, greens, rice, pasta, and yoghurt so the shop stays efficient without feeling repetitive.",
        meals: [
            MealSummary(
                id: "meal-mon",
                day: "Mon",
                dish: "Miso salmon rice bowls",
                description: "Salmon with cucumber, rice, greens, and a quick miso dressing.",
                cuisine: "Japanese",
                cookTimeMin: 25,
                costAud: 18,
                estimatedProteinG: 38,
                estimatedCalories: 640,
                estimatedCarbsG: 72,
                tone: "#6f7250",
                recipe: RecipeInfo(
                    ingredients: [
                        RecipeIngredient(name: "Salmon fillets", quantity: "2 x 150 g", category: "Seafood"),
                        RecipeIngredient(name: "Microwave jasmine rice", quantity: "2 cups cooked", category: "Pantry"),
                        RecipeIngredient(name: "Baby spinach", quantity: "2 handfuls", category: "Fresh Produce"),
                        RecipeIngredient(name: "Lebanese cucumber", quantity: "1, sliced", category: "Fresh Produce"),
                        RecipeIngredient(name: "White miso paste", quantity: "1 tbsp", category: "Pantry"),
                        RecipeIngredient(name: "Soy sauce", quantity: "1 tbsp", category: "Pantry"),
                        RecipeIngredient(name: "Lime", quantity: "1/2, juiced", category: "Fresh Produce")
                    ],
                    instructionsBrief: "Bake salmon with miso, soy, and lime until just cooked. Warm rice, toss spinach through while hot, then top with cucumber and flaked salmon.",
                    prepTimeMin: 8,
                    cookTimeMin: 17,
                    method: [
                        "Whisk miso, soy, lime juice, and a splash of water, then brush over the salmon.",
                        "Bake at 200C for 12 to 15 minutes until the salmon flakes easily.",
                        "Warm rice, fold through baby spinach, then serve with cucumber and salmon."
                    ],
                    serves: 2
                )
            ),
            MealSummary(
                id: "meal-tue",
                day: "Tue",
                dish: "Charred broccoli orecchiette",
                description: "A quick pasta with broccoli, parmesan, lemon, and chilli.",
                cuisine: "Italian",
                cookTimeMin: 30,
                costAud: 12,
                estimatedProteinG: 21,
                estimatedCalories: 560,
                estimatedCarbsG: 82,
                tone: "#486b58",
                recipe: RecipeInfo(
                    ingredients: [
                        RecipeIngredient(name: "Orecchiette", quantity: "250 g", category: "Pantry"),
                        RecipeIngredient(name: "Broccoli", quantity: "1 large head", category: "Fresh Produce"),
                        RecipeIngredient(name: "Parmesan", quantity: "1/3 cup grated", category: "Dairy"),
                        RecipeIngredient(name: "Lemon", quantity: "1, zested and juiced", category: "Fresh Produce"),
                        RecipeIngredient(name: "Chilli flakes", quantity: "1/2 tsp", category: "Pantry"),
                        RecipeIngredient(name: "Garlic", quantity: "2 cloves", category: "Fresh Produce")
                    ],
                    instructionsBrief: "Cook pasta, char broccoli in a hot pan, then toss with garlic, lemon, chilli, parmesan, and enough pasta water to make it glossy.",
                    prepTimeMin: 10,
                    cookTimeMin: 20,
                    method: [
                        "Boil orecchiette in salted water and reserve half a cup of the pasta water.",
                        "Char chopped broccoli in olive oil until the edges are browned, then add garlic and chilli.",
                        "Toss pasta through the broccoli with lemon, parmesan, and pasta water until glossy."
                    ],
                    serves: 2
                )
            ),
            MealSummary(
                id: "meal-wed",
                day: "Wed",
                dish: "Harissa chickpea traybake",
                description: "Chickpeas and vegetables roasted with yoghurt and herbs.",
                cuisine: "Mediterranean",
                cookTimeMin: 35,
                costAud: 14,
                estimatedProteinG: 23,
                estimatedCalories: 590,
                estimatedCarbsG: 76,
                tone: "#805645",
                recipe: RecipeInfo(
                    ingredients: [
                        RecipeIngredient(name: "Canned chickpeas", quantity: "2 cans, drained", category: "Pantry"),
                        RecipeIngredient(name: "Sweet potato", quantity: "1 large, cubed", category: "Fresh Produce"),
                        RecipeIngredient(name: "Red onion", quantity: "1, wedges", category: "Fresh Produce"),
                        RecipeIngredient(name: "Harissa paste", quantity: "1 1/2 tbsp", category: "Pantry"),
                        RecipeIngredient(name: "Greek yoghurt", quantity: "1/2 cup", category: "Dairy"),
                        RecipeIngredient(name: "Coriander", quantity: "1/2 bunch", category: "Fresh Produce")
                    ],
                    instructionsBrief: "Roast chickpeas, sweet potato, and onion with harissa until crisp at the edges. Spoon over yoghurt and coriander to serve.",
                    prepTimeMin: 10,
                    cookTimeMin: 25,
                    method: [
                        "Toss chickpeas, sweet potato, and onion with harissa, olive oil, salt, and pepper.",
                        "Roast at 210C for 25 minutes, turning once, until sweet potato is tender.",
                        "Serve with Greek yoghurt, coriander, and a squeeze of lemon."
                    ],
                    serves: 2
                )
            ),
            MealSummary(
                id: "meal-thu",
                day: "Thu",
                dish: "Chicken souvlaki plates",
                description: "Lemon oregano chicken with pita, tomato salad, cucumber, and yoghurt sauce.",
                cuisine: "Greek",
                cookTimeMin: 30,
                costAud: 17,
                estimatedProteinG: 42,
                estimatedCalories: 620,
                estimatedCarbsG: 54,
                tone: "#757548",
                recipe: RecipeInfo(
                    ingredients: [
                        RecipeIngredient(name: "Chicken thigh fillets", quantity: "400 g", category: "Meat"),
                        RecipeIngredient(name: "Pita bread", quantity: "2 rounds", category: "Bakery"),
                        RecipeIngredient(name: "Cherry tomatoes", quantity: "200 g", category: "Fresh Produce"),
                        RecipeIngredient(name: "Greek yoghurt", quantity: "1/2 cup", category: "Dairy"),
                        RecipeIngredient(name: "Dried oregano", quantity: "1 tsp", category: "Pantry"),
                        RecipeIngredient(name: "Lemon", quantity: "1", category: "Fresh Produce")
                    ],
                    instructionsBrief: "Marinate chicken with lemon and oregano, grill until browned, then serve with warm pita, tomato salad, cucumber, and yoghurt sauce.",
                    prepTimeMin: 12,
                    cookTimeMin: 18,
                    method: [
                        "Slice chicken and coat with lemon zest, lemon juice, oregano, olive oil, salt, and pepper.",
                        "Cook in a hot pan for 5 to 6 minutes each side until browned and cooked through.",
                        "Warm pita and plate with tomato, cucumber, yoghurt sauce, and sliced chicken."
                    ],
                    serves: 2
                )
            ),
            MealSummary(
                id: "meal-fri",
                day: "Fri",
                dish: "Ginger tofu noodle stir-fry",
                description: "Crisp tofu, hokkien noodles, snow peas, carrot, ginger, and sesame soy.",
                cuisine: "Chinese-inspired",
                cookTimeMin: 22,
                costAud: 13,
                estimatedProteinG: 28,
                estimatedCalories: 570,
                estimatedCarbsG: 70,
                tone: "#5d5e6f",
                recipe: RecipeInfo(
                    ingredients: [
                        RecipeIngredient(name: "Firm tofu", quantity: "300 g, pressed", category: "Dairy"),
                        RecipeIngredient(name: "Hokkien noodles", quantity: "400 g", category: "Pantry"),
                        RecipeIngredient(name: "Snow peas", quantity: "150 g", category: "Fresh Produce"),
                        RecipeIngredient(name: "Carrot", quantity: "1, julienned", category: "Fresh Produce"),
                        RecipeIngredient(name: "Fresh ginger", quantity: "1 tbsp grated", category: "Fresh Produce"),
                        RecipeIngredient(name: "Sesame oil", quantity: "1 tsp", category: "Pantry")
                    ],
                    instructionsBrief: "Crisp tofu cubes, stir-fry vegetables with ginger, then toss through noodles with soy, sesame oil, and a splash of water.",
                    prepTimeMin: 10,
                    cookTimeMin: 12,
                    method: [
                        "Cube tofu, pat dry, and pan-fry until golden on two sides.",
                        "Stir-fry carrot, snow peas, and ginger for 2 minutes.",
                        "Add noodles, soy, sesame oil, tofu, and a splash of water, tossing until hot."
                    ],
                    serves: 2
                )
            ),
            MealSummary(
                id: "meal-sat",
                day: "Sat",
                dish: "Turkey pesto meatballs",
                description: "Lean turkey meatballs simmered in tomato passata with basil pesto and greens.",
                cuisine: "Italian",
                cookTimeMin: 35,
                costAud: 16,
                estimatedProteinG: 44,
                estimatedCalories: 610,
                estimatedCarbsG: 48,
                tone: "#78566f",
                recipe: RecipeInfo(
                    ingredients: [
                        RecipeIngredient(name: "Turkey mince", quantity: "500 g", category: "Meat"),
                        RecipeIngredient(name: "Passata", quantity: "500 ml", category: "Pantry"),
                        RecipeIngredient(name: "Basil pesto", quantity: "2 tbsp", category: "Deli"),
                        RecipeIngredient(name: "Breadcrumbs", quantity: "1/3 cup", category: "Pantry"),
                        RecipeIngredient(name: "Egg", quantity: "1", category: "Dairy"),
                        RecipeIngredient(name: "Baby spinach", quantity: "2 handfuls", category: "Fresh Produce")
                    ],
                    instructionsBrief: "Mix turkey with egg and breadcrumbs, brown meatballs, then simmer in passata with pesto and spinach until tender.",
                    prepTimeMin: 12,
                    cookTimeMin: 23,
                    method: [
                        "Combine turkey mince, egg, breadcrumbs, salt, and pepper, then roll into meatballs.",
                        "Brown meatballs in olive oil, add passata, and simmer gently for 18 minutes.",
                        "Stir through pesto and spinach, then serve with bread or leftover rice."
                    ],
                    serves: 3
                )
            ),
            MealSummary(
                id: "meal-sun",
                day: "Sun",
                dish: "Coconut pumpkin dal",
                description: "Red lentils simmered with pumpkin, coconut milk, tomato, spinach, and lime.",
                cuisine: "Indian-inspired",
                cookTimeMin: 38,
                costAud: 11,
                estimatedProteinG: 24,
                estimatedCalories: 540,
                estimatedCarbsG: 74,
                tone: "#4d7370",
                recipe: RecipeInfo(
                    ingredients: [
                        RecipeIngredient(name: "Red lentils", quantity: "1 cup", category: "Pantry"),
                        RecipeIngredient(name: "Pumpkin", quantity: "500 g, cubed", category: "Fresh Produce"),
                        RecipeIngredient(name: "Coconut milk", quantity: "400 ml can", category: "Pantry"),
                        RecipeIngredient(name: "Diced tomatoes", quantity: "400 g can", category: "Pantry"),
                        RecipeIngredient(name: "Baby spinach", quantity: "2 handfuls", category: "Fresh Produce"),
                        RecipeIngredient(name: "Curry powder", quantity: "1 tbsp", category: "Pantry")
                    ],
                    instructionsBrief: "Simmer lentils, pumpkin, tomatoes, coconut milk, and curry powder until soft. Finish with spinach and lime.",
                    prepTimeMin: 10,
                    cookTimeMin: 28,
                    method: [
                        "Rinse lentils, then add to a pot with pumpkin, tomatoes, coconut milk, curry powder, and two cups of water.",
                        "Simmer for 25 to 28 minutes, stirring often, until lentils are creamy and pumpkin is tender.",
                        "Fold through spinach and finish with lime juice."
                    ],
                    serves: 3
                )
            )
        ],
        shoppingList: ShoppingList(
            id: "fixture-shopping-list",
            storeId: .topRyde,
            storeName: "Coles Top Ryde",
            sections: [
                ShoppingListSection(
                    label: "Fresh Produce",
                    sortKey: 0,
                    type: .perimeter,
                    items: [
                        ShoppingListItem(
                            id: "item-spinach",
                            name: "Baby spinach",
                            quantity: "200 g",
                            checked: true,
                            aisleLabel: "Fresh Produce",
                            sectionType: .perimeter,
                            product: ProductSnapshot(
                                sku: "fixture-spinach",
                                productName: "Coles Baby Spinach",
                                brand: "Coles",
                                size: "200g",
                                priceAud: 4.5,
                                imageUrl: nil,
                                capturedAt: nil
                            )
                        ),
                        ShoppingListItem(
                            id: "item-lemons",
                            name: "Lemons",
                            quantity: "3",
                            checked: true,
                            aisleLabel: "Fresh Produce",
                            sectionType: .perimeter,
                            product: ProductSnapshot(
                                sku: "fixture-lemons",
                                productName: "Fresh Lemons",
                                brand: nil,
                                size: "Each",
                                priceAud: 1.2,
                                imageUrl: nil,
                                capturedAt: nil
                            )
                        ),
                        ShoppingListItem(
                            id: "item-broccoli",
                            name: "Broccoli",
                            quantity: "2 heads",
                            checked: false,
                            aisleLabel: "Fresh Produce",
                            sectionType: .perimeter,
                            product: nil
                        ),
                        ShoppingListItem(
                            id: "item-cucumber",
                            name: "Lebanese cucumber",
                            quantity: "2",
                            checked: false,
                            aisleLabel: "Fresh Produce",
                            sectionType: .perimeter,
                            product: nil
                        ),
                        ShoppingListItem(
                            id: "item-sweet-potato",
                            name: "Sweet potato",
                            quantity: "1 large",
                            checked: false,
                            aisleLabel: "Fresh Produce",
                            sectionType: .perimeter,
                            product: nil
                        ),
                        ShoppingListItem(
                            id: "item-pumpkin",
                            name: "Pumpkin",
                            quantity: "500 g",
                            checked: false,
                            aisleLabel: "Fresh Produce",
                            sectionType: .perimeter,
                            product: nil
                        ),
                        ShoppingListItem(
                            id: "item-herbs",
                            name: "Coriander and basil",
                            quantity: "1 bunch each",
                            checked: false,
                            aisleLabel: "Fresh Produce",
                            sectionType: .perimeter,
                            product: nil
                        )
                    ]
                ),
                ShoppingListSection(
                    label: "Meat and Seafood",
                    sortKey: 1,
                    type: .perimeter,
                    items: [
                        ShoppingListItem(
                            id: "item-salmon",
                            name: "Salmon fillets",
                            quantity: "2 x 150 g",
                            checked: false,
                            aisleLabel: "Seafood",
                            sectionType: .perimeter,
                            product: nil
                        ),
                        ShoppingListItem(
                            id: "item-chicken",
                            name: "Chicken thigh fillets",
                            quantity: "400 g",
                            checked: false,
                            aisleLabel: "Meat",
                            sectionType: .perimeter,
                            product: nil
                        ),
                        ShoppingListItem(
                            id: "item-turkey",
                            name: "Turkey mince",
                            quantity: "500 g",
                            checked: false,
                            aisleLabel: "Meat",
                            sectionType: .perimeter,
                            product: nil
                        )
                    ]
                ),
                ShoppingListSection(
                    label: "Dairy and Chilled",
                    sortKey: 2,
                    type: .perimeter,
                    items: [
                        ShoppingListItem(
                            id: "item-yoghurt",
                            name: "Greek yoghurt",
                            quantity: "1 tub",
                            checked: false,
                            aisleLabel: "Dairy",
                            sectionType: .perimeter,
                            product: nil
                        ),
                        ShoppingListItem(
                            id: "item-parmesan",
                            name: "Parmesan",
                            quantity: "1 wedge",
                            checked: false,
                            aisleLabel: "Dairy",
                            sectionType: .perimeter,
                            product: nil
                        ),
                        ShoppingListItem(
                            id: "item-tofu",
                            name: "Firm tofu",
                            quantity: "300 g",
                            checked: false,
                            aisleLabel: "Chilled",
                            sectionType: .perimeter,
                            product: nil
                        )
                    ]
                ),
                ShoppingListSection(
                    label: "Pantry and Aisles",
                    sortKey: 4,
                    type: .numbered,
                    items: [
                        ShoppingListItem(
                            id: "item-harissa",
                            name: "Harissa paste",
                            quantity: "1 jar",
                            checked: false,
                            aisleLabel: "Aisle 4",
                            sectionType: .numbered,
                            product: nil
                        ),
                        ShoppingListItem(
                            id: "item-pasta",
                            name: "Orecchiette",
                            quantity: "500 g",
                            checked: false,
                            aisleLabel: "Aisle 4",
                            sectionType: .numbered,
                            product: nil
                        ),
                        ShoppingListItem(
                            id: "item-lentils",
                            name: "Red lentils",
                            quantity: "1 bag",
                            checked: false,
                            aisleLabel: "Aisle 4",
                            sectionType: .numbered,
                            product: nil
                        ),
                        ShoppingListItem(
                            id: "item-coconut-milk",
                            name: "Coconut milk",
                            quantity: "400 ml can",
                            checked: false,
                            aisleLabel: "Aisle 5",
                            sectionType: .numbered,
                            product: nil
                        ),
                        ShoppingListItem(
                            id: "item-noodles",
                            name: "Hokkien noodles",
                            quantity: "400 g",
                            checked: false,
                            aisleLabel: "Aisle 5",
                            sectionType: .numbered,
                            product: nil
                        ),
                        ShoppingListItem(
                            id: "item-passata",
                            name: "Passata",
                            quantity: "500 ml",
                            checked: false,
                            aisleLabel: "Aisle 6",
                            sectionType: .numbered,
                            product: nil
                        )
                    ]
                ),
                ShoppingListSection(
                    label: "Bakery",
                    sortKey: 6,
                    type: .perimeter,
                    items: [
                        ShoppingListItem(
                            id: "item-pita",
                            name: "Pita bread",
                            quantity: "1 pack",
                            checked: false,
                            aisleLabel: "Bakery",
                            sectionType: .perimeter,
                            product: nil
                        )
                    ]
                )
            ]
        )
    )

    static func plan(for store: StoreSummary) -> WeekPlan {
        let locations = locations(for: store.id)
        let sections = current.shoppingList.sections.map { section in
            ShoppingListSection(
                label: section.label,
                sortKey: section.sortKey,
                type: section.type,
                items: section.items.map { item in
                    ShoppingListItem(
                        id: item.id,
                        name: item.name,
                        quantity: item.quantity,
                        checked: item.checked,
                        aisleLabel: locations[item.id] ?? item.aisleLabel,
                        sectionType: item.sectionType,
                        product: item.product,
                        importedCandidate: item.importedCandidate,
                        locationUncertaintyText: item.locationUncertaintyText
                    )
                }
            )
        }

        return WeekPlan(
            id: "fixture-week-plan-\(store.id.rawValue)",
            source: .fixture,
            storeId: store.id,
            storeName: store.name,
            weekLabel: current.weekLabel,
            planningNotes: current.planningNotes,
            meals: current.meals,
            shoppingList: ShoppingList(
                id: "fixture-shopping-list-\(store.id.rawValue)",
                storeId: store.id,
                storeName: store.name,
                sections: sections
            )
        )
    }

    private static let topRydeLocations: [String: String] = [
        "item-spinach": "Fresh Produce",
        "item-lemons": "Fresh Produce",
        "item-broccoli": "Fresh Produce",
        "item-cucumber": "Fresh Produce",
        "item-sweet-potato": "Fresh Produce",
        "item-pumpkin": "Fresh Produce",
        "item-herbs": "Fresh Produce",
        "item-salmon": "Meat",
        "item-chicken": "Meat",
        "item-turkey": "Meat",
        "item-yoghurt": "Back of Store - Dairy",
        "item-parmesan": "Back of Store - Dairy",
        "item-tofu": "Location not certain",
        "item-harissa": "Aisle 8",
        "item-pasta": "Aisle 10",
        "item-lentils": "Aisle 8",
        "item-coconut-milk": "Aisle 8",
        "item-noodles": "Aisle 10",
        "item-passata": "Aisle 10",
        "item-pita": "Bakery"
    ]

    private static let eastVillageLocations: [String: String] = [
        "item-spinach": "Fresh Produce",
        "item-lemons": "Fresh Produce",
        "item-broccoli": "Fresh Produce",
        "item-cucumber": "Fresh Produce",
        "item-sweet-potato": "Fresh Produce",
        "item-pumpkin": "Fresh Produce",
        "item-herbs": "Fresh Produce",
        "item-salmon": "Meat & Seafood",
        "item-chicken": "Meat & Seafood",
        "item-turkey": "Meat & Seafood",
        "item-yoghurt": "Right of Store",
        "item-parmesan": "Right of Store",
        "item-tofu": "Location not certain",
        "item-harissa": "Aisle 7",
        "item-pasta": "Aisle 7",
        "item-lentils": "Aisle 7",
        "item-coconut-milk": "Aisle 7",
        "item-noodles": "Aisle 7",
        "item-passata": "Aisle 7",
        "item-pita": "Bakery"
    ]

    private static func locations(for storeId: StoreID) -> [String: String] {
        switch storeId {
        case .topRyde:
            topRydeLocations
        case .eastVillage:
            eastVillageLocations
        case .rhodes, .surryHills, .woolworthsRhodes:
            // Fixture rows retain only locations already backed by the store guides.
            // Real generated lists use the Supabase store walkthrough contract.
            [
                "item-spinach": "Fresh Produce",
                "item-lemons": "Fresh Produce",
                "item-broccoli": "Fresh Produce",
                "item-cucumber": "Fresh Produce",
                "item-sweet-potato": "Fresh Produce",
                "item-pumpkin": "Fresh Produce",
                "item-herbs": "Fresh Produce",
                "item-salmon": "Meat & Seafood",
                "item-chicken": "Meat & Seafood",
                "item-turkey": "Meat & Seafood",
                "item-yoghurt": storeId == .woolworthsRhodes ? "Chilled Wall" : "Dairy",
                "item-parmesan": storeId == .woolworthsRhodes ? "Chilled Wall" : "Dairy",
                "item-tofu": "Location not certain",
                "item-harissa": "Location not certain",
                "item-pasta": "Location not certain",
                "item-lentils": "Location not certain",
                "item-coconut-milk": "Location not certain",
                "item-noodles": "Location not certain",
                "item-passata": "Location not certain",
                "item-pita": "Bakery"
            ]
        }
    }
}

#if DEBUG
extension FixtureWeekPlan {
    // Recorded retailer catalogue responses for UI verification. Never used as
    // a fallback for customer lists or written to a customer account.
    static var catalogueMatchingPlan: WeekPlan {
        var plan = current
        let ingredients = [
            ("Pork mince", "200g", "Meat"),
            ("Cornflour", "1 small pack, about 300g", "Aisle 7"),
            ("Soy sauce", "250ml bottle", "Aisle 8"),
            ("Fish sauce", "200ml bottle", "Aisle 8")
        ]
        plan.shoppingList.sections = []
        for (index, ingredient) in ingredients.enumerated() {
            let item = ShoppingListItem(id: "catalogue-\(index)", name: ingredient.0, quantity: ingredient.1,
                                        checked: index == 0, aisleLabel: ingredient.2, sectionType: .unknown, product: nil)
            if let existing = plan.shoppingList.sections.firstIndex(where: { $0.label == ingredient.2 }) {
                plan.shoppingList.sections[existing].items.append(item)
            } else {
                plan.shoppingList.sections.append(ShoppingListSection(label: ingredient.2, sortKey: index, type: .unknown, items: [item]))
            }
        }
        return plan
    }

    static var catalogueCandidates: [ProductCandidate] {
        try! JSONDecoder().decode([ProductCandidate].self, from: Data(#"""
[
    {
        "sku": "8781518",
        "barcode": null,
        "retailer": "coles",
        "categoryGroup": "PORK/HAMS/BACON",
        "category": "Pork",
        "subCategory": "Meat & Seafood",
        "name": "Regular Pork Mince",
        "brand": "Coles",
        "size": "500g",
        "priceAud": 7,
        "unitPriceAud": 14,
        "unitQuantity": 1,
        "unitMeasure": "kg",
        "comparablePrice": "$14.00/ 1kg",
        "imageUrl": "https://cdn.productimages.coles.com.au/productimages/8/8781518.jpg",
        "productUrl": "https://www.coles.com.au/product/regular-pork-mince-8781518",
        "sourceName": "Coles product catalog",
        "sourceUrl": "https://www.coles.com.au/product/regular-pork-mince-8781518",
        "capturedAt": "2026-05-21T18:06:10.443Z",
        "freshnessLabel": "Coles data captured 22 May 2026",
        "confidence": "high",
        "confidenceReason": "Matched against the packaged Coles product catalog with captured price data.",
        "uncertaintyText": "Price is from captured Coles data and may differ at checkout."
    },
    {
        "sku": "7352902",
        "barcode": null,
        "retailer": "coles",
        "categoryGroup": "MEAL SOLUTIONS",
        "category": "Baking",
        "subCategory": "Pantry",
        "name": "Cornflour",
        "brand": "Coles",
        "size": "300g",
        "priceAud": 1.35,
        "unitPriceAud": 4.5,
        "unitQuantity": 1,
        "unitMeasure": "kg",
        "comparablePrice": "$4.50/ 1kg",
        "imageUrl": "https://cdn.productimages.coles.com.au/productimages/7/7352902.jpg",
        "productUrl": "https://www.coles.com.au/product/cornflour-7352902",
        "sourceName": "Coles product catalog",
        "sourceUrl": "https://www.coles.com.au/product/cornflour-7352902",
        "capturedAt": "2026-05-21T14:50:22.326Z",
        "freshnessLabel": "Coles data captured 22 May 2026",
        "confidence": "high",
        "confidenceReason": "Matched against the packaged Coles product catalog with captured price data.",
        "uncertaintyText": "Price is from captured Coles data and may differ at checkout."
    },
    {
        "sku": "2579434",
        "barcode": null,
        "retailer": "coles",
        "categoryGroup": "MEAL SOLUTIONS",
        "category": "Sauces",
        "subCategory": "Pantry",
        "name": "Soy Sauce",
        "brand": "Coles",
        "size": "500mL",
        "priceAud": 1.9,
        "unitPriceAud": 0.38,
        "unitQuantity": 100,
        "unitMeasure": "ml",
        "comparablePrice": "$0.38/ 100mL",
        "imageUrl": "https://cdn.productimages.coles.com.au/productimages/2/2579434.jpg",
        "productUrl": "https://www.coles.com.au/product/soy-sauce-2579434",
        "sourceName": "Coles product catalog",
        "sourceUrl": "https://www.coles.com.au/product/soy-sauce-2579434",
        "capturedAt": "2026-05-21T13:19:02.549Z",
        "freshnessLabel": "Coles data captured 21 May 2026",
        "confidence": "high",
        "confidenceReason": "Matched against the packaged Coles product catalog with captured price data.",
        "uncertaintyText": "Price is from captured Coles data and may differ at checkout."
    },
    {
        "sku": "5420998",
        "barcode": null,
        "retailer": "coles",
        "categoryGroup": "MEAL SOLUTIONS",
        "category": "International Foods",
        "subCategory": "Pantry",
        "name": "Fish Sauce",
        "brand": "Squid",
        "size": "300mL",
        "priceAud": 2.85,
        "unitPriceAud": 0.95,
        "unitQuantity": 100,
        "unitMeasure": "ml",
        "comparablePrice": "$0.95/ 100mL",
        "imageUrl": "https://cdn.productimages.coles.com.au/productimages/5/5420998.jpg",
        "productUrl": "https://www.coles.com.au/product/fish-sauce-5420998",
        "sourceName": "Coles product catalog",
        "sourceUrl": "https://www.coles.com.au/product/fish-sauce-5420998",
        "capturedAt": "2026-05-21T14:06:13.397Z",
        "freshnessLabel": "Coles data captured 22 May 2026",
        "confidence": "high",
        "confidenceReason": "Matched against the packaged Coles product catalog with captured price data.",
        "uncertaintyText": "Price is from captured Coles data and may differ at checkout."
    }
]
"""#.utf8))
    }
}
#endif

#if DEBUG
extension FixtureWeekPlan {
    static func completedShop(unpriced: Bool) -> WeekPlan {
        var plan = catalogueMatchingPlan
        for section in plan.shoppingList.sections.indices {
            for index in plan.shoppingList.sections[section].items.indices {
                let item = plan.shoppingList.sections[section].items[index]
                let candidate = catalogueCandidates.first { $0.displayName.localizedCaseInsensitiveContains(item.name) }!
                plan.shoppingList.sections[section].items[index] = ShoppingListItem(
                    id: item.id, name: item.name, quantity: item.quantity, checked: true,
                    aisleLabel: item.aisleLabel, sectionType: item.sectionType,
                    product: unpriced ? nil : ProductPurchaseEstimate.snapshot(candidate: candidate, item: item),
                    importedCandidate: candidate
                )
            }
        }
        let originalOnion = productPickerPlan(budgeted: false).shoppingList.sections[0].items[0]
        let onion = ShoppingListItem(id: originalOnion.id, name: originalOnion.name, quantity: originalOnion.quantity,
                                     checked: true, aisleLabel: originalOnion.aisleLabel, sectionType: originalOnion.sectionType,
                                     product: unpriced ? nil : originalOnion.product, importedCandidate: originalOnion.importedCandidate)
        let produce = [onion] + ["Garlic", "Fresh ginger"].map {
            ShoppingListItem(id: "saved-\($0)", name: $0, quantity: "1", checked: true,
                             aisleLabel: "Fresh Produce", sectionType: .perimeter, product: nil)
        }
        plan.shoppingList = ShoppingList(
            id: unpriced ? "unpriced-ui-test-list" : "ui-test-list",
            storeId: plan.storeId, storeName: plan.storeName,
            sections: [ShoppingListSection(label: "Fresh Produce", sortKey: -1, type: .perimeter, items: produce)] + plan.shoppingList.sections,
            status: .completed, completedAt: "2026-09-20T10:54:00.000Z"
        )
        return plan
    }

    static func productPickerPlan(budgeted: Bool) -> WeekPlan {
        var plan = current
        let candidate = productPickerCandidates.first { $0.sku == "4239517" }!
        let ingredient = ShoppingListItem(id: "picker-onions", name: "Brown onions", quantity: budgeted ? "400g" : "2 medium", checked: false, aisleLabel: "Fresh Produce", sectionType: .perimeter, product: nil)
        let item = ShoppingListItem(id: ingredient.id, name: ingredient.name, quantity: ingredient.quantity,
                                   checked: false, aisleLabel: ingredient.aisleLabel, sectionType: ingredient.sectionType,
                                   product: ProductPurchaseEstimate.snapshot(candidate: candidate, item: ingredient), importedCandidate: candidate)
        plan.shoppingList.sections = [ShoppingListSection(label: "Fresh Produce", sortKey: 0, type: .perimeter, items: [item])]
        plan.budgetTargetAud = budgeted ? 2 : nil
        return plan
    }

    // Recorded search response, used only by the picker UI tests.
    static var productPickerCandidates: [ProductCandidate] {
        try! JSONDecoder().decode([ProductCandidate].self, from: Data(#"""
[
    {
        "sku": "4803991",
        "barcode": null,
        "retailer": "coles",
        "categoryGroup": "VEGETABLES/SALAD",
        "category": "Vegetables",
        "subCategory": "Fruit & Vegetables",
        "name": "Brown Onions",
        "brand": "Coles",
        "size": "1kg",
        "priceAud": 2.5,
        "unitPriceAud": 2.5,
        "unitQuantity": 1,
        "unitMeasure": "kg",
        "comparablePrice": "$2.50/ 1kg",
        "imageUrl": "https://cdn.productimages.coles.com.au/productimages/4/4803991.jpg",
        "productUrl": "https://www.coles.com.au/product/brown-onions-4803991",
        "sourceName": "Coles product catalog",
        "sourceUrl": "https://www.coles.com.au/product/brown-onions-4803991",
        "capturedAt": "2026-05-21T21:40:46.799Z",
        "freshnessLabel": "Coles data captured 22 May 2026",
        "confidence": "high",
        "confidenceReason": "Matched against the packaged Coles product catalog with captured price data.",
        "uncertaintyText": "Price is from captured Coles data and may differ at checkout."
    },
    {
        "sku": "5076305",
        "barcode": null,
        "retailer": "coles",
        "categoryGroup": "VEGETABLES/SALAD",
        "category": "Vegetables",
        "subCategory": "Fruit & Vegetables",
        "name": "Brown Onions",
        "brand": "Coles Organic",
        "size": "1Kg",
        "priceAud": 7.9,
        "unitPriceAud": 7.9,
        "unitQuantity": 1,
        "unitMeasure": "kg",
        "comparablePrice": "$7.90/ 1kg",
        "imageUrl": "https://cdn.productimages.coles.com.au/productimages/5/5076305.jpg",
        "productUrl": "https://www.coles.com.au/product/brown-onions-5076305",
        "sourceName": "Coles product catalog",
        "sourceUrl": "https://www.coles.com.au/product/brown-onions-5076305",
        "capturedAt": "2026-05-21T17:07:49.283Z",
        "freshnessLabel": "Coles data captured 22 May 2026",
        "confidence": "high",
        "confidenceReason": "Matched against the packaged Coles product catalog with captured price data.",
        "uncertaintyText": "Price is from captured Coles data and may differ at checkout."
    },
    {
        "sku": "5134809",
        "barcode": null,
        "retailer": "coles",
        "categoryGroup": "VEGETABLES/SALAD",
        "category": "Vegetables",
        "subCategory": "Fruit & Vegetables",
        "name": "Brown Onion Shallots Loose",
        "brand": "Coles",
        "size": "approx. 35g each",
        "priceAud": 0.46,
        "unitPriceAud": 13,
        "unitQuantity": 1,
        "unitMeasure": "g",
        "comparablePrice": "$13.00/ 1kg",
        "imageUrl": "https://cdn.productimages.coles.com.au/productimages/5/5134809.jpg",
        "productUrl": "https://www.coles.com.au/product/brown-onion-shallots-loose-5134809",
        "sourceName": "Coles product catalog",
        "sourceUrl": "https://www.coles.com.au/product/brown-onion-shallots-loose-5134809",
        "capturedAt": "2026-05-21T17:07:49.283Z",
        "freshnessLabel": "Coles data captured 22 May 2026",
        "confidence": "high",
        "confidenceReason": "Matched against the packaged Coles product catalog with captured price data.",
        "uncertaintyText": "Price is from captured Coles data and may differ at checkout."
    },
    {
        "sku": "4239517",
        "barcode": null,
        "retailer": "coles",
        "categoryGroup": "VEGETABLES/SALAD",
        "category": "Vegetables",
        "subCategory": "Fruit & Vegetables",
        "name": "Loose Brown Onions",
        "brand": "Coles",
        "size": "approx. 200g",
        "priceAud": 0.84,
        "unitPriceAud": 4.2,
        "unitQuantity": 1,
        "unitMeasure": "g",
        "comparablePrice": "$4.20/ 1kg",
        "imageUrl": "https://cdn.productimages.coles.com.au/productimages/4/4239517.jpg",
        "productUrl": "https://www.coles.com.au/product/loose-brown-onions-4239517",
        "sourceName": "Coles product catalog",
        "sourceUrl": "https://www.coles.com.au/product/loose-brown-onions-4239517",
        "capturedAt": "2026-05-21T17:07:49.283Z",
        "freshnessLabel": "Coles data captured 22 May 2026",
        "confidence": "high",
        "confidenceReason": "Matched against the packaged Coles product catalog with captured price data.",
        "uncertaintyText": "Price is from captured Coles data and may differ at checkout."
    },
    {
        "sku": "4443579",
        "barcode": null,
        "retailer": "coles",
        "categoryGroup": "MEAL SOLUTIONS",
        "category": "Stocks & Gravy",
        "subCategory": "Pantry",
        "name": "Brown Onion Liquid Gravy Pouch",
        "brand": "Gravox",
        "size": "165g",
        "priceAud": 2.5,
        "unitPriceAud": 1.52,
        "unitQuantity": 100,
        "unitMeasure": "g",
        "comparablePrice": "$1.52/ 100g",
        "imageUrl": "https://cdn.productimages.coles.com.au/productimages/4/4443579.jpg",
        "productUrl": "https://www.coles.com.au/product/brown-onion-liquid-gravy-pouch-4443579",
        "sourceName": "Coles product catalog",
        "sourceUrl": "https://www.coles.com.au/product/brown-onion-liquid-gravy-pouch-4443579",
        "capturedAt": "2026-05-21T18:06:15.513Z",
        "freshnessLabel": "Coles data captured 22 May 2026",
        "confidence": "high",
        "confidenceReason": "Matched against the packaged Coles product catalog with captured price data.",
        "uncertaintyText": "Price is from captured Coles data and may differ at checkout."
    },
    {
        "sku": "6046864",
        "barcode": "9300681163300",
        "retailer": "coles",
        "categoryGroup": "MEAL SOLUTIONS",
        "category": "Stocks & Gravy",
        "subCategory": "Pantry",
        "name": "Brown Onion Gravy Mix Tin",
        "brand": "Gravox",
        "size": "120g",
        "priceAud": 5,
        "unitPriceAud": 0.42,
        "unitQuantity": 10,
        "unitMeasure": "g",
        "comparablePrice": "$0.42/ 10g",
        "imageUrl": "https://cdn.productimages.coles.com.au/productimages/6/6046864.jpg",
        "productUrl": "https://www.coles.com.au/product/brown-onion-gravy-mix-tin-6046864",
        "sourceName": "Coles product catalog",
        "sourceUrl": "https://www.coles.com.au/product/brown-onion-gravy-mix-tin-6046864",
        "capturedAt": "2026-05-21T13:19:11.120Z",
        "freshnessLabel": "Coles data captured 21 May 2026",
        "confidence": "high",
        "confidenceReason": "Matched against the packaged Coles product catalog with captured price data.",
        "uncertaintyText": "Price is from captured Coles data and may differ at checkout."
    }
]
"""#.utf8))
    }
}
#endif
