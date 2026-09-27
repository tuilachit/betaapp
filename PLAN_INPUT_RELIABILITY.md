# Plan input reliability

## Scope and dependencies

This change builds on the native input picker in betaapp PR #41. Its PR is stacked
on `codex/plan-input-picker`; merge the picker first, then retarget this change to
`main` if GitHub has not done so automatically.

Backend counterpart: https://github.com/tuilachit/reasi-backend/pull/24

Deploy the additive backend changes before releasing this iOS build. Older
backend versions discard the new input metadata. The backend also depends on the
existing product-first migration from its current main; see its release notes.
This work does not merge, deploy, archive, or upload either repository.

## Behavior

- Untouched form defaults no longer override people, budget, date or course count
  stated in the user's text. An explicitly edited field still wins.
- Selected catalog products retain SKU and retailer through interpretation. The
  server verifies price and store context; client snapshots are not trusted facts.
- Recipe screenshots retain supported ingredients and method, not just a short
  ingredient-name summary. Food photos remain meal inspiration, not a source recipe.
- Photo imports open a native review sheet. Names and quantities are editable;
  uncertain rows start unchecked. Product alternatives are mutually exclusive.
- Handwritten grocery rows default to Just buy, not recipe requirements. Users can
  change a row to Use in plan or Already have before adding it.
- Cancelling the review does not change the plan. Repeated confirmation is guarded.

## Additive contract

- `PlanBrief.explicitFields` lists edited form constraints; `[]` lets interpretation
  replace defaults. Missing values preserve legacy behavior for saved drafts.
- `ideas[].selectedProduct` carries SKU, retailer and name separately from the
  existing optional full `product` snapshot.
- `ideas[].quantity`, `recipe`, `confidence`, and `confidenceReason` preserve bounded
  source evidence. Editing a product name clears its selected catalog identity.

## Verification: 2026-09-27

- Full Debug simulator suite: **79 passed, 2 failed, 81 total** on iPhone 17e,
  iOS 26.5. All 59 unit tests passed; 20 of 22 UI tests passed.
- All new input tests passed, including quantity/evidence round trips, selected
  product identity, review cancellation, uncertain-row opt-in and large-text controls.
- Existing input picker UI tests passed. Review screenshots were inspected at
  390-point width and accessibility text size; text-clipping audits passed.
- Unsigned Release build for a generic iOS device passed. This is not a signed
  archive, physical-device validation, or TestFlight upload.
- Backend counterpart: 115 tests and affected Deno entrypoint type checks passed.

The two UI failures were also observed before these reliability changes:

1. `testAppearanceSwitchesAcrossScreensAndPersistsAfterRelaunch`: Settings navigation
   cannot reveal the List behavior target.
2. `testProductPickerPreservesBudgetReviewAndRecalculatesShelfPrice`: typing into
   Shelf price per pack fails because the field has no keyboard focus.

These remain unresolved. The full suite is not green.

## Live acceptance still required

After the backend deploy, use a signed-in test account and the new app build:

1. Enter a dinner for four with a budget and time; leave the form untouched. Check
   interpretation preserves that intent. Edit a form field and verify it takes precedence.
2. Select a specific store product; generate and verify the same SKU, correct store,
   quantity and catalog price snapshot. Verify unavailable selections fail clearly.
3. Import a handwritten list with quantities and an unclear row. Cancel once, then
   confirm selected rows. Verify Just buy items and Already have behavior in the list.
4. Import a recipe screenshot with more than eight ingredients and a long method.
   Compare the reviewed and generated recipe with the source. A food-only photo
   must not claim to have recovered a recipe.
5. Test unreadable images, expired auth, offline import and provider failure. Each
   should preserve the draft and show a retryable error without adding fake results.

No paid AI calls or production mutations were used in local verification. Fixture
UI tests and packaged-catalog tests do not establish live end-to-end acceptance.
