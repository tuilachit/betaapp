import Foundation

enum SpendCategoryColorRole: String, Equatable {
    case produce
    case protein
    case pantry
    case dairy
    case bakery
    case frozen
    case drinks
    case baby
    case personalCare
    case household
    case other
    case accentA
    case accentB
    case accentC

    static func role(for label: String) -> SpendCategoryColorRole {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "produce", "fresh produce": return .produce
        case "protein", "meat & seafood", "meat and seafood": return .protein
        case "pantry": return .pantry
        case "dairy", "dairy & eggs", "dairy and eggs": return .dairy
        case "bakery": return .bakery
        case "frozen": return .frozen
        case "drinks", "beverages": return .drinks
        case "baby": return .baby
        case "personal care": return .personalCare
        case "household": return .household
        case "other": return .other
        default: break
        }

        let hash = normalized.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return [.accentA, .accentB, .accentC][Int(hash % 3)]
    }
}

struct SpendCategorySlice: Identifiable, Equatable {
    let id: String
    let label: String
    let amountAud: Double
    let fraction: Double
    let colorRole: SpendCategoryColorRole
    let angleRange: Range<Double>
}

struct SpendCategoryBreakdown: Equatable {
    let slices: [SpendCategorySlice]
    let totalAud: Double

    init(categories: [SpendingCategoryAmount]) {
        var combined: [String: (label: String, amount: Double)] = [:]

        for category in categories where category.amountAud.isFinite && category.amountAud > 0 {
            let label = category.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }
            let key = label.lowercased()
            let current = combined[key]
            combined[key] = (current?.label ?? label, (current?.amount ?? 0) + category.amountAud)
        }

        let ordered = combined.values.sorted { lhs, rhs in
            if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }

        var visible = Array(ordered.prefix(4))
        let remainder = ordered.dropFirst(4).reduce(0) { $0 + $1.amount }
        if remainder > 0 {
            if let otherIndex = visible.firstIndex(where: { $0.label.caseInsensitiveCompare("Other") == .orderedSame }) {
                visible[otherIndex].amount += remainder
            } else {
                visible.append((label: "Other", amount: remainder))
            }
            visible.sort { lhs, rhs in
                if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
        }

        let total = visible.reduce(0) { $0 + $1.amount }
        totalAud = total
        guard total > 0 else {
            slices = []
            return
        }

        var cumulativeAngle = 0.0
        slices = visible.map { category in
            let fraction = category.amount / total
            let start = cumulativeAngle
            cumulativeAngle += fraction * 360
            return SpendCategorySlice(
                id: category.label.lowercased(),
                label: category.label,
                amountAud: category.amount,
                fraction: fraction,
                colorRole: .role(for: category.label),
                angleRange: start..<cumulativeAngle
            )
        }
    }

    func slice(id: String?) -> SpendCategorySlice? {
        guard let id else { return nil }
        return slices.first { $0.id == id }
    }

    func slice(atCumulativeValue value: Double?) -> SpendCategorySlice? {
        guard let value, value >= 0, value <= totalAud, totalAud > 0 else { return nil }
        var upperBound = 0.0
        for slice in slices {
            upperBound += slice.amountAud
            if value <= upperBound { return slice }
        }
        return slices.last
    }
}
