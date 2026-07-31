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
