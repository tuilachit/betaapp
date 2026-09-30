import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { after, test } from "node:test";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const scratch = mkdtempSync(join(tmpdir(), "reasi-store-guide-"));
after(() => rmSync(scratch, { recursive: true, force: true }));

// Compile the actual model and view mutation without loading SwiftUI or Supabase.
// Only haptic feedback is replaced; assertions below operate on encoded payloads.
function declaration(path, signature) {
  const text = readFileSync(join(root, path), "utf8");
  const start = text.indexOf(signature);
  if (start < 0) throw new Error(`Cannot compile production declaration: ${signature}`);
  const open = text.indexOf("{", start);
  let depth = 1;
  let end = open + 1;
  for (; depth && end < text.length; end++) {
    if (text[end] === "{") depth++;
    if (text[end] === "}") depth--;
  }
  if (depth) throw new Error(`Unclosed production declaration: ${signature}`);
  return text.slice(start, end);
}

const model = declaration("Reasi/Core/Services/SupabaseService.swift", "struct StoreGuideSection:");
const move = declaration("Reasi/Features/Onboarding/OnboardingPlaceholderView.swift", "private func moveGuideSection(");
const source = `
import Foundation
${model}
enum ReasiHaptics { static func selection() {} }
final class GuideHarness {
    var guideSections: [StoreGuideSection]
    init(_ sections: [StoreGuideSection]) { guideSections = sections }
    ${move}
    func run(_ index: Int, _ offset: Int) { moveGuideSection(index, offset: offset) }
}
let sections = [
    StoreGuideSection(code: "a", title: "Produce", sectionType: "perimeter", aisleNumber: nil, routeOrder: 10, confidence: "high"),
    StoreGuideSection(code: "b", title: "Baking", sectionType: "aisle", aisleNumber: 4, routeOrder: 20, confidence: "medium"),
    StoreGuideSection(code: "c", title: "Frozen", sectionType: "back_of_store", aisleNumber: nil, routeOrder: 30, confidence: "low")
]
let harness = GuideHarness(sections)
for pair in CommandLine.arguments.dropFirst() {
    let parts = pair.split(separator: ",").map { Int($0)! }
    harness.run(parts[0], parts[1])
}
FileHandle.standardOutput.write(try JSONEncoder().encode(harness.guideSections))
`;
const sourcePath = join(scratch, "main.swift");
const executable = join(scratch, "guide-route");
writeFileSync(sourcePath, source);
execFileSync("swiftc", [sourcePath, "-o", executable]);
const payload = (...moves) => JSON.parse(execFileSync(executable, moves, { encoding: "utf8" }));

test("a moved guide encodes displayed order and retains section evidence", () => {
  const sections = payload("1,-1");
  assert.deepEqual(sections.map(s => s.code), ["b", "a", "c"]);
  assert.deepEqual(sections.map(s => s.routeOrder), [0, 1, 2]);
  assert.equal(sections[0].aisleNumber, 4);
  assert.equal(sections[0].confidence, "medium");
  assert.equal(sections[1].sectionType, "perimeter");
  assert.equal(sections[2].confidence, "low");
});

test("repeated moves preserve all sections and route positions", () => {
  const sections = payload("1,-1", "1,1");
  assert.deepEqual(sections.map(s => s.code), ["b", "c", "a"]);
  assert.deepEqual(sections.map(s => s.routeOrder), [0, 1, 2]);
});

test("out-of-range moves leave the guide untouched", () => {
  assert.deepEqual(payload("0,-1", "2,1", "-1,1"), payload());
});

// Native CI checks its own payload contract. An explicit paired checkout adds
// real roundtrip checks; a supplied but invalid path must fail, not skip them.
if (process.env.REASI_BACKEND_PATH) {
  const backend = resolve(process.env.REASI_BACKEND_PATH);
  const { normalizeGuideSections } = await import(pathToFileURL(join(backend, "supabase/functions/_shared/store-guide.ts")));
  for (const [name, moves, expected] of [
    ["one move", ["1,-1"], ["b", "a", "c"]],
    ["repeated moves", ["1,-1", "1,1"], ["b", "c", "a"]],
  ]) {
    test(`paired backend retains displayed order after ${name}`, () => {
      const sections = payload(...moves);
      const normalized = normalizeGuideSections(sections);
      assert.deepEqual(normalized.map(s => s.code), expected);
      // Swift omits a nil aisle; the backend's normalized contract uses null.
      assert.deepEqual(normalized, sections.map(s => ({ ...s, aisleNumber: s.aisleNumber ?? null })));
    });
  }
}
