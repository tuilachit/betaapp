import { readFileSync, writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { execFileSync } from "node:child_process";

// Executes the production query method against an in-memory conditional-update
// transport. This checks row effects/results, not source text or query spelling.
const root = resolve(import.meta.dirname, "..");
const source = readFileSync(join(root, "Reasi/Core/Services/SupabaseService.swift"), "utf8");
function declaration(marker) {
  const start = source.indexOf(marker);
  if (start < 0) throw new Error(`Missing declaration: ${marker}`);
  let end = source.indexOf("{", start), depth = 1;
  for (end++; depth; end++) {
    if (source[end] === "{") depth++;
    if (source[end] === "}") depth--;
  }
  return source.slice(start, end).replaceAll("#if canImport(Supabase)", "#if true");
}
const program = `import Foundation
enum AuthFlowError: Error { case notSignedIn, notConfigured }
enum ReasiServiceError: Error { case invalidResponse }
enum ShoppingSectionType: String { case aisle }
struct ShoppingListItem { let id = "item"; var quantity = "500 g"; let aisleLabel: String? = nil }
struct ProductSnapshot: Encodable { let priceAud: Double? = 5 }
struct ProductCandidate {
  let sectionLabel: String? = nil; let sectionSortKey: Int? = nil; let sectionType: ShoppingSectionType? = nil
  let aisleLabel: String? = nil; let sku: String? = "sku"; let retailer: String? = "coles"
  let observationId: String? = nil; let barcode: String? = nil; let priceAud: Double? = 5
  let sourceName = "Fixture"; let sourceUrl: URL? = nil; let capturedAt: String? = nil; let freshnessLabel = "Fixture"
}
struct ImportedShoppingListItemResponse: Decodable { let id: String }
${declaration("struct ProductSelectionQuantity:")}
${declaration("struct ShoppingListProductSelectionUpdate:")}
${declaration("struct CatalogPriceSnapshot:")}
final class ConditionalUpdate {
  var row = ["id": "item", "shopping_list_id": "list", "user_id": "A", "quantity_label": "1 kg"]
  var filters: [String: String] = [:]
  var price: Double?
  var encoded: [String: Any] = [:]
  var mustBeUnselected = false
  var nullFilters: Set<String> = []
  var isUpdating = false
  var beforeUpdate: (() -> Void)?
  struct Result<Value> { let value: Value }
  func from(_ table: String) -> ConditionalUpdate {
    filters = [:]; nullFilters = []; isUpdating = false; mustBeUnselected = false
    return self
  }
  func update<T: Encodable>(_ value: T) throws -> ConditionalUpdate {
    isUpdating = true
    encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    return self
  }
  func eq(_ column: String, value: String) -> ConditionalUpdate { filters[column] = value; return self }
  func eq(_ column: String, value: Double) -> ConditionalUpdate { filters[column] = String(value); return self }
  func \`is\`(_ column: String, value: String?) -> ConditionalUpdate {
    if column == "product_snapshot" { mustBeUnselected = true } else { nullFilters.insert(column) }
    return self
  }
  func select(_ columns: String) -> ConditionalUpdate { self }
  func limit(_ count: Int) -> ConditionalUpdate { self }
  func execute<Value: Decodable>() async throws -> Result<Value> {
    if isUpdating { beforeUpdate?() }
    let matches = filters.allSatisfy { column, value in
      if column == "quantity" { return row[column].flatMap(Double.init) == Double(value) }
      return row[column] == value
    } && nullFilters.allSatisfy { row[$0] == nil } && (!mustBeUnselected || price == nil)
    let rows: [[String: Any]]
    if !matches { rows = [] }
    else if isUpdating {
      price = (encoded["product_snapshot"] as? [String: Any])?["priceAud"] as? Double
      rows = [["id": row["id"]!]]
    } else {
      rows = [["quantity": row["quantity"].flatMap(Double.init).map { $0 as Any } ?? NSNull(),
               "quantity_label": row["quantity_label"].map { $0 as Any } ?? NSNull()]]
    }
    return Result(value: try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: rows)))
  }
}
@MainActor final class SupabaseService {
  let currentUserId: String? = "A"
  let authIdentityRevision = 0
  let client = ConditionalUpdate()
  func authenticatedClientOrNil() throws -> ConditionalUpdate? { client }
  func requireCurrentIdentity(_ userId: String, revision: Int) throws {}
  static func isoTimestamp(_ date: Date) -> String { "now" }
  ${declaration("func selectProduct(")}
}
@main struct ProductSelectionRunner {
  @MainActor static func main() async throws {
    var failures = 0
    for onlyIfUnselected in [false, true] {
      for changed in [true, false] {
        let service = SupabaseService()
        if !changed { service.client.row["quantity_label"] = "500 g" }
        do {
          let saved = try await service.selectProduct(ProductCandidate(), for: ShoppingListItem(), shoppingListId: "list", sectionLabel: "Aisle", sectionSortKey: 1, sectionType: .aisle, actualPriceAud: nil, productSnapshot: ProductSnapshot(), onlyIfUnselected: onlyIfUnselected)
          let pass = saved == !changed && (changed ? service.client.price == nil : service.client.price == 5)
          print("\\(pass ? "PASS" : "FAIL") quantity changed=\\(changed), automatic=\\(onlyIfUnselected)")
          if !pass { failures += 1 }
        } catch { print("FAIL expected false, not error: \\(error)"); failures += 1 }
      }
      for label: String? in [nil, ""] {
        let service = SupabaseService()
        service.client.row["quantity"] = "1"
        service.client.row["quantity_label"] = label
        var item = ShoppingListItem(); item.quantity = "1"
        let saved = try await service.selectProduct(ProductCandidate(), for: item, shoppingListId: "list", sectionLabel: "Aisle", sectionSortKey: 1, sectionType: .aisle, actualPriceAud: nil, productSnapshot: ProductSnapshot(), onlyIfUnselected: onlyIfUnselected)
        let pass = saved && service.client.price == 5
        print("\\(pass ? "PASS" : "FAIL") legacy label=\\(String(describing: label)), automatic=\\(onlyIfUnselected)")
        if !pass { failures += 1 }
      }
      for mutateLabel in [false, true] {
        let service = SupabaseService()
        service.client.row["quantity"] = "1"
        service.client.row["quantity_label"] = nil
        service.client.beforeUpdate = {
          if mutateLabel { service.client.row["quantity_label"] = "2 packs" }
          else { service.client.row["quantity"] = "2" }
        }
        var item = ShoppingListItem(); item.quantity = "1"
        let saved = try await service.selectProduct(ProductCandidate(), for: item, shoppingListId: "list", sectionLabel: "Aisle", sectionSortKey: 1, sectionType: .aisle, actualPriceAud: nil, productSnapshot: ProductSnapshot(), onlyIfUnselected: onlyIfUnselected)
        let pass = !saved && service.client.price == nil
        print("\\(pass ? "PASS" : "FAIL") changed after read, label=\\(mutateLabel), automatic=\\(onlyIfUnselected)")
        if !pass { failures += 1 }
      }
    }
    if failures > 0 { exit(1) }
  }
}`;
const dir = mkdtempSync(join(tmpdir(), "reasi-product-guard-"));
try {
  writeFileSync(join(dir, "Selection.swift"), program);
  execFileSync("xcrun", ["swiftc", "-parse-as-library", join(dir, "Selection.swift"), "-o", join(dir, "selection")], { stdio: "inherit" });
  execFileSync(join(dir, "selection"), [], { stdio: "inherit" });
} finally { rmSync(dir, { recursive: true }); }
