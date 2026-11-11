# Reasi 1.0 launch readiness, 11 Nov 2026

Branch: `codex/app-store-launch`, from `origin/main` at 0b37702 (TestFlight build 12). Build number is now 13.

## What this branch changes in the app

- **Weekly budget in onboarding.** A new step after household size, with a starting amount based on household size, ± $10 steps and four quick picks. Skip leaves no target. The amount is saved to `user_preferences.weekly_grocery_budget_aud`, which `generate-week-plan` already uses when a plan has no budget of its own, so the first plan is built to fit it.
- **Plan Builder starts from the profile.** A new draft takes the saved household size. A new week draft also takes the weekly budget; occasion drafts don't. An existing draft is never overwritten. Switching a draft to an occasion clears a budget that came from the weekly one.
- **Price age on the shopping list.** Under the total, a line reads "Coles prices checked 9 Oct". After 10 days it turns amber and reads "Coles prices last checked 9 Oct. They may have changed." It always uses the oldest price on the list.
- **Spend track record.**
  - Month view: "3 of 4 weeks on target · $86 under in total".
  - Week view: "On target 3 weeks running", shown from 2 weeks.
  - These figures count only finished weeks with a completed shop, compared with the current weekly target. They are not claimed savings.
  - The weekly trend chart now has a dashed target line, slim bars, the amount for each week, and over-target weeks in amber.
- **Home leads with money.** A "This week" card shows spent against the target, how much is left, and the current list total, with how many items are priced. Tapping it opens Spend. The subtitle is now today's date.
- **New intro screens.**
  - Screen 1 shows a receipt-style sample week with the line "Groceries that fit your budget."
  - Screen 2 is a numbered "Three steps, every week" list in place of three icon cards.
- **Detail fixes.**
  - Removed the sparkles icons from buttons.
  - Each household size has its own icon.
  - On meal cards without a photo, the fork-and-knife icon moved to a corner.
- **UI test fix.** `testPlanBuilderPickerPreservesDraftAndOpensProductSearch` now puts the keyboard away before tapping Add. With the keyboard up on a 6.3" screen, the floating Create plan button covers Add and takes the tap. On the Smart Basket branch it failed one step earlier, because Add couldn't be reached with the keyboard up. I didn't check it on `main`.
- **Release tooling.** `scripts/testflight-release-preflight.sh` now uses `grep -E` instead of `rg`, so it runs on a stock Mac. It passes all 11 checks on the Release build.
- **Docs.** The TestFlight checklist says build 13 and no longer mentions a free-preview plan, which doesn't exist on `main`.

## Only you can do these

### 1. Price data (most important)

**Decision, 12 Nov 2026: launch 1.0 with dated prices.** Position Reasi as a budget planner and spend tracker. The list shows when prices were last checked and turns amber after 10 days. The App Store description says prices are estimates.

Every Wednesday price refresh since 14 Oct has failed. Since 28 Oct, Coles has answered every request with HTTP 403. The prices in the app are from **9 Oct**, and the scraper only runs on this Mac.

- The app now says how old the prices are, so users aren't misled. But a grocery-savings app with 5-week-old prices will lose trust quickly.
- Do not work around the 403. Bypassing a retailer's bot protection is a terms-of-service and legal risk.
- Options:
  1. A retailer-approved or licensed data feed.
  2. Prices users enter or confirm from their receipts.
  3. Launch with dated prices and position Reasi as a budget planner and spend tracker first.

### 2. Apple

- Paid Developer Program membership.
- Explicit App ID `ai.reasi.ios` with Sign in with Apple enabled.
- App Store Connect app record.
- Agreements, banking and tax.
- Subscription group "Reasi Pro" with weekly, monthly and annual products, priced at A$7.99, A$17.99 and A$79.99:
  - weekly: no trial
  - monthly: 3-day trial
  - annual: 14-day trial
- **App Review needs a working login.** The app has a hard paywall, so review notes need a demo account and must say purchases can be tested with a sandbox account. Never put passwords in the repo.

### 3. RevenueCat

- Entitlement `reasi_pro` and offering `default` with all three products.
- The public iOS SDK key.
- Signed webhook to Supabase, with the secret kept server-side.

### 4. Supabase production

- Anonymous sign-ins off.
- Leaked-password protection on (needs the Pro plan).
- Minimum password length of 10.
- Apple provider set up with client ID `ai.reasi.ios`.
- Security advisor shows zero findings.
- Confirm migration `20260828073000_assistant_list_mutations.sql` is applied. The shopping assistant depends on it, but it's missing from `release/testflight-backend.json`.

### 5. Open pull requests

- **iOS #46 (Smart Basket)** ships without an on/off switch, and its backend (reasi-backend #29–#33) isn't deployed. Keep it out of 1.0, or deploy that backend first.
- **iOS #45 (reliability fixes)** needs its paired backend deployed. It also conflicts with #46.
- **iOS #42** is a stale draft that #44 has largely replaced.

### 6. App Store listing

- Screenshots at 6.9" and 6.5".
- Description, keywords, support URL (`https://www.reasiai.com/support` is live), and age rating.
- Privacy labels: account details, purchases, product interaction analytics (PostHog), and user content (photos, lists).
- Brand sign-off on the icon. The current icon passes Apple's technical checks.

### 7. Final build

**Archived on 12 Nov 2026.** Build `1.0.0 (13)` is in Xcode Organizer as `Reasi-1.0.0-13.xcarchive`. It's signed for team Y57R7X3G78, carries the Sign in with Apple entitlement, and passes the release preflight as a device build. In Organizer, choose Validate App, then Distribute App > App Store Connect, once the App Store Connect record and agreements are in place.

CI note: PR #47's `iOS Release build` run stayed queued with no job created, because GitHub never assigned a `macos-26` hosted runner. The same workflow ran on 11 Oct. If it is still queued, re-run it from the Actions tab.

- Run the Release configuration on a physical iPhone.
- Archive with Any iOS Device selected, then Validate and Upload in Organizer.

## Not verified on this branch

- Sign-in, purchases and plan generation against production. There were no test accounts, and creating real accounts was out of scope.
- The price-age line with real catalogue dates. The sample data has no capture dates, so the line is covered by unit tests only.
