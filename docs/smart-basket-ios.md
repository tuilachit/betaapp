# Smart Basket Native Review

Task 3 only. No matching, costing, catalog publication, backend, or deployment changes.

## Entry And Review

Shopping List's basket overflow contains Price details and Smart Basket. The large
native sheet uses one scroll view and a bottom Apply action. Both flexibility
toggles default off; no swaps are selected automatically. Only the preferred
choice on each eligible line can be selected because Apply accepts line IDs,
not arbitrary product choices.

Costs are AUD integer cents for whole purchases. The proposal reflects only
selected swaps. Missing full totals stay Unconfirmed; comparable subtotals are
separately labeled. Weighted choices explicitly say Weight-based estimate.
Capture dates, expiry, price conditions, and uncertainty are disclosed without
displaying internal policy codes. Savings are estimates, never a checkout promise.

Partial, insufficient-data, no-change, empty, loading, offline, error, and expired
previews leave unsupported items unchanged. Checked lines cannot be selected.
Zero comparable coverage says Prices can't be compared yet; it does not report
zero-dollar totals or imply that unsupported prices are stale.
Completed lists, account restoration/sign-out, offline use, generation, plan
restoration, and mismatched/switching stores disable requests or Apply.

## Requests

```json
{"shoppingListId":"owned-list-id","expectedStoreId":"east_village","flexibility":{"allowBrandChange":false,"allowPackChange":false}}
```

```json
{"previewId":"owned-preview-id","expectedStoreId":"east_village","selectedLineIds":["owned-item-id"]}
```

`SmartBasketPreview`, `SmartBasketLine`, and `SmartBasketChoice` mirror the supplied
wire contract. Nullable totals stay optional. `costType` is optional and unknown
additive fields do not break decoding.
The weighted cost value is `variable_weight_display_estimate`; fixed choices may
include `fixed_pack_display_price`. Match policy/evidence additions are ignored
by the display decoder, not treated as human approvals.
`FixtureSmartBasket` contains a complete
synthetic JSON response, including legacy choices without `costType`. Its numbers
are display fixtures, not price or savings evidence.

## Write And Restore Boundary

Service calls reuse the existing authenticated-client and public session-auth
helpers. Account identity includes a revision that changes on sign-out or account
transition, not ordinary token refresh. Each awaited operation rechecks account,
list, plan, store, and applicable preview expiry. Local checks, imports, deletions,
and ongoing product matching are drained before Preview or Apply.
Owned `quantity_label` values already map verbatim to native item quantities when
present and nonempty. Context construction rejects duplicate IDs without a
dictionary trap. Exact-plan integration rejects duplicate IDs in the current,
refreshed, or merged rows before replacing visible state or updating caches.

Apply is single flight. Ownership checks for a confirmation are independent of
network availability, so an offline transition cannot erase a confirmed receipt.
Its successful receipt is retained before fetching the
exact returned meal plan ID. Reload uses CoreLoopStore's existing pending-import,
deletion, checked-state, and cache helpers. A failed reload offers Reload list
without resending Apply. Once the server confirms a mutation, expiry does not
erase that receipt or cause another mutation. New pending changes survive reload
and subsequent local-cache restoration. Reload captures the full list and pending
write revision before reading. A concurrent edit or acknowledgement discards that
read and retries once, then offers Reload list without overwriting newer state.

An uncertain Apply retains the immutable preview/store/selected-line payload.
Selection, flexibility and new previews stay locked until Check saved swaps
replays that exact request through the server's idempotency contract, including
after preview expiry. A later rejection cannot erase an earlier uncertain commit.
Only a definitive rejection of the first request permits a fresh preview.
Receipts and attempts are retained in the review store for the current session;
they are not a durable transaction journal across app termination.
Pending recovery is keyed by account identity/revision, shopping list, meal plan
and store. Opening a different valid context parks the old request or receipt and
allows a fresh preview. Returning restores the exact original recovery; sign-out
clears active and parked records. Offline or otherwise invalid contexts cannot
discard a confirmation or uncertain request.
Null comparison authority does not authorize inferred savings.

## Verification

`zsh scripts/test-smart-basket.sh` runs native Swift model/coordinator checks on
the host, with no credentials, app launch, simulator, or service calls.
`SmartBasketTests` adds XCTest decoding, money, context, expiry, single-flight,
offline confirmation, exact replay, receipt-retry, and pending-state
merge/cache/restore coverage. UI tests and DEBUG
fixtures cover normal/large text, explicit selection, partial/no-change/empty/error,
loading, expiry, and offline entry. The Apply footer uses the existing growing
multiline button style rather than the fixed 64-point variant.

The added `smart-basket-offline-tests` GitHub job runs the host probes and focused
XCTest/UI tests with an empty configuration and synthetic fixtures. It creates a
390-point iPhone simulator in CI only, tests the largest accessibility text size,
and uploads result bundles and screenshots. The existing Release job is unchanged.

Local verification is compile/build-for-testing only for the app and XCTest
targets. Simulator execution and screenshots belong to authorized GitHub CI;
they have not been run locally. No production snapshot is activated, and legacy
data without sufficient new evidence must remain partial/unoptimized.

Verified after the final context-scoped recovery fix: 98 host checks passed;
Debug app build, Debug build-for-testing (app/unit/UI targets), and arm64 Release
compilation all passed. Workflow YAML, embedded Ruby and shell syntax checks
passed. The controller reported no actionable findings in the final targeted
independent re-review of all five recovery corrections.
Existing onboarding and UI-test actor-isolation warnings remain outside this
change; no simulator/device app or XCTest bundle has been launched.

Local evidence logs:

- `/tmp/reasi-ios-smart-basket-context-host-final.log`
- `/tmp/reasi-ios-smart-basket-context-debug-build.log`
- `/tmp/reasi-ios-smart-basket-context-tests-build.log`
- `/tmp/reasi-ios-smart-basket-context-release-build.log`

## Intentional Files

- `Reasi/Core/Models/SmartBasketModels.swift`
- `Reasi/Core/Services/SmartBasketReviewStore.swift`
- `Reasi/Core/Services/CoreLoopStore.swift`
- `Reasi/Core/Services/SupabaseService.swift`
- `Reasi/Core/Fixtures/FixtureSmartBasket.swift`
- `Reasi/Features/ShoppingList/SmartBasketSheet.swift`
- `Reasi/Features/ShoppingList/ShoppingListPlaceholderView.swift`
- `Reasi.xcodeproj/project.pbxproj`
- `ReasiTests/ReasiCoreTests.swift`
- `ReasiUITests/ReasiOnboardingUITests.swift`
- `scripts/smart-basket/SmartBasketHarness.swift`
- `scripts/test-smart-basket.sh`
- `docs/smart-basket-ios.md`
- `.github/workflows/ios-release-build.yml`

Review worktree: `/Users/locnguyen/Documents/Reasi_iOS_smart_basket`, branch
`codex/smart-basket-preview`, base `0b37702`. The controller authorized a local-only
commit after the final re-review and builds; the controller opens the draft PR.
No push, merge, TestFlight upload, deployment, paid call, or real mutation occurred.
