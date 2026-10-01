import { readFileSync, writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { execFileSync } from "node:child_process";

// Compile the actual checked-in method/payload declarations, not a rewritten
// model of their behavior. The SDK boundary is a local recording transport.
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
const structs = ["SpendingPreferencesUpsert", "OnboardingPreferencesUpsert"].map((name) => declaration(`struct ${name}:`)).join("\n");
const program = `import Foundation
enum AuthFlowError: Error { case notSignedIn }
${declaration("enum UploadKind:")}
struct FileOptions { let cacheControl: String; let contentType: String; let upsert: Bool }
final class RecordingClient {
  var path: String?
  var storage: RecordingClient { self }
  func from(_ bucket: String) -> RecordingClient { self }
  func upload(_ path: String, data: Data, options: FileOptions) async throws { self.path = path }
}
@MainActor final class SupabaseService {
  struct Config { let hasSupabase = true }
  let config = Config()
  var currentUserId: String? = "ABCDEF12-1234-4567-89AB-ABCDEF123456"
  var authenticatedUserId: String? { currentUserId }
  let client = RecordingClient()
  let authIdentityRevision = 0
  func requireCurrentIdentity(_ userId: String, revision: Int) throws {
    guard currentUserId == userId else { throw CancellationError() }
  }
  func authenticatedClientOrNil() throws -> RecordingClient? { client }
  ${declaration("static func userImageUploadPath(")}
  ${declaration("func uploadUserImage(")}
}
${structs}
@main struct IdentityRunner {
  @MainActor static func main() async throws {
    var failures = 0
    func check(_ pass: Bool, _ name: String) { print("\\(pass ? "PASS" : "FAIL") \\(name)"); if !pass { failures += 1 } }
    let service = SupabaseService()
    for kind in [UploadKind.shoppingListPhoto, .productPhoto, .storeGuidePhoto] {
      let path = try await service.uploadUserImage(Data(), kind: kind)
      check(path.split(separator: "/").first.map(String.init) == service.currentUserId!.lowercased(), "storage UUID \\(kind.rawValue)")
      check(service.currentUserId == "ABCDEF12-1234-4567-89AB-ABCDEF123456", "cache UUID preserved")
    }
    for budget: Double? in [120, nil] {
      let spend = SpendingPreferencesUpsert(userId: "A", weeklyGroceryBudgetAud: budget, spendingCoachTone: "supportive", updatedAt: "now")
      let onboarding = OnboardingPreferencesUpsert(userId: "A", purposeTags: [], primaryPurpose: nil, householdChoice: nil, householdSize: 2, cuisines: [], favoriteCuisines: [], foodStyles: [], dietaryConstraints: [], dietaryRestrictions: [], preferredStore: "top_ryde", onboardingCompletedAt: nil, weeklyGroceryBudgetAud: budget, spendingCoachTone: "supportive", updatedAt: "now")
      for (name, data) in [("spending", try JSONEncoder().encode(spend)), ("onboarding", try JSONEncoder().encode(onboarding))] {
        let payload = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        check(budget == nil ? payload["weekly_grocery_budget_aud"] is NSNull : payload["weekly_grocery_budget_aud"] as? Double == budget, "\\(name) budget \\(String(describing: budget))")
      }
    }
    if failures > 0 { exit(1) }
  }
}`;
const dir = mkdtempSync(join(tmpdir(), "reasi-identity-"));
try {
  writeFileSync(join(dir, "Identity.swift"), program);
  execFileSync("xcrun", ["swiftc", "-parse-as-library", join(dir, "Identity.swift"), "-o", join(dir, "identity")], { stdio: "inherit" });
  execFileSync(join(dir, "identity"), [], { stdio: "inherit" });
} finally { rmSync(dir, { recursive: true }); }
