import SwiftUI

enum PlanInputAction: String, CaseIterable, Identifiable {
    case mealPhoto, findProduct, productPhoto, listPhoto

    var id: Self { self }

    var title: String {
        switch self {
        case .mealPhoto: "Meal photo"
        case .findProduct: "Find product"
        case .productPhoto: "Product photo"
        case .listPhoto: "List photo"
        }
    }

    var symbol: String {
        switch self {
        case .mealPhoto: "fork.knife.circle"
        case .findProduct: "magnifyingglass"
        case .productPhoto: "shippingbox"
        case .listPhoto: "text.viewfinder"
        }
    }

    var hint: String {
        switch self {
        case .mealPhoto: "Choose a meal photo or recipe screenshot from your library"
        case .findProduct: "Search groceries, paste a product link, or scan a barcode"
        case .productPhoto: "Choose a photo of an ingredient or package from your library"
        case .listPhoto: "Choose a photographed shopping list from your library"
        }
    }
}
