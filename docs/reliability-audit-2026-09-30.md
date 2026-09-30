# Feature Reliability Fixes

Date: 30 September 2026. Native work is paired with the backend branch
`codex/feature-reliability-audit`. Both branches build on the pending
`codex/list-photo-extraction` work. Neither is a production deployment.

## Scope

| Audit | Change |
| --- | --- |
| F01 | Use lowercase authenticated UUIDs for new photo uploads, matching existing ownership rules. |
| F02 | Backend entitlement refresh and account deletion handle both known UUID spellings used by RevenueCat. No arbitrary customer aliases are followed. |
| F03/F04 | Preferences and asynchronous screen data are scoped to the actual authenticated account, not a signed-in Boolean. |
| F05 | Pending imports, checks and explicit deletion intent survive opening another plan and restoring local state. |
| F06 | Finish-shopping responses apply only to the captured list and account. |
| F07 | Assistant list mutations require affirmative operation/target evidence; negations and ambiguous references cannot authorize unrelated deletion. |
| F08 | Cancellation requested before the generation-start response is retained. |
| F09 | Cross-retailer switches invalidate current product/price selection while preserving checked state and historical evidence. Late wrong-retailer saves are rejected by the backend. |
| F10 | Quantity edits clear outdated price calculations; delayed saves require the original quantity to remain unchanged. |
| F11 | Recipe-photo ideas retain structured ingredients, method, timing, confidence and upload provenance. Source-backed zero-cook recipes remain valid. |
| F12 | Failed product-link imports show an error and retry in the URL input branch. |
| F13/F14 | Pending preference fields merge over remote values; clearing a budget sends explicit null. |
| F15 | Spend revalidates cached advice against current deterministic facts; stale advice falls back and can be explicitly retried. |
| F16 | Reordering an aisle guide updates route positions sent to the backend. |

## Verification

The native CI now runs unit/UI tests as well as Release compilation. Host
regressions execute actual store/model code with controlled transport boundaries;
they are not a substitute for iOS lifecycle or production acceptance tests.

- Core state host suite: 19 tests passed, including lost-response import recovery,
  deletion tombstones, stale store restoration and account-switched history requests.
- Preference host suite: 14 cases passed; Spend identity suite: 3 cases passed.
- Storage/payload checks: 10 passed; conditional product-save checks: 12 passed, including null/empty legacy labels and a quantity edit between read and write.
- Guide reorder: 3 native-only cases passed; explicitly setting
  `REASI_BACKEND_PATH` to the paired checkout adds 2 passing roundtrip checks.
  Native CI does not require a private sibling checkout. Backend CI separately
  tests normalization against the native route contract.
- Backend Node suite: 212 tests passed in the paired checkout.
- Deno photo transport uses a mocked provider, not a paid recognition request.
- SQL regression fixtures execute the real RPCs and new migration in temporary databases, with both text and numeric legacy quantity columns.
- Final Debug build-for-testing compiled the app and registered test targets. This does not mean the iOS tests executed.
- Final Release compilation and built-bundle preflight passed, including debug-hook exclusion and server-secret pattern checks. Existing onboarding concurrency/unused-value warnings remain; no new build errors.
- Local simulator/UI execution is still awaiting approval; no physical-device acceptance is claimed.

Preference saves reconcile pending fields with the latest remote profile. This
protects previously changed remote fields and same-client request races; it is
not a cross-device database transaction. Simultaneous writes from a second device
after that read would require field-level writes or server versioning.

## Release And Acceptance

Deploy the paired backward-compatible backend migration/functions before the app
build. Do not use the test fixture schema as a production migration. No live RLS,
purchase, account deletion, or image-provider acceptance was performed in this
fix pass.

Still verify on a test account/device: photo upload and partial VLM extraction;
sign-out/sign-in and account switching; offline edits and relaunch; generation
cancellation; finish while another plan loads; every supported store switch;
RevenueCat restore and deletion; and corrected Spend facts/insight retry.

Legacy v1 completed preferences and pending edits lack an owner. Their bytes are
retained, but they are not automatically assigned to the next signed-in account.
Recovering unsynced legacy edits needs an explicit owner-confirmed migration.
Historical uppercase upload references are not rewritten. New uploads use the
canonical path without weakening storage ownership checks.

Catalog freshness and missing barcode coverage are data work, not repaired by
these code changes. No new crawl or claim of live prices is included.
