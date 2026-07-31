import Foundation

enum StoreID: String, Codable, CaseIterable, Identifiable {
    case topRyde = "top_ryde"
    case eastVillage = "east_village"
    case rhodes = "rhodes"
    case surryHills = "surry_hills"
    case woolworthsRhodes = "woolworths_rhodes"

    var id: String { rawValue }
}

struct StoreSummary: Identifiable, Codable, Hashable {
    let id: StoreID
    let retailer: String
    let name: String
    let shortName: String

    var retailerDisplayName: String {
        switch retailer {
        case "woolworths":
            "Woolworths"
        default:
            "Coles"
        }
    }
}
