# Reasi 1.0 launch readiness, 11 Nov 2026

Branch: `codex/app-store-launch`, from `origin/main` at 0b37702 (TestFlight build 12). Build number is now 14. Build 13 was archived but never uploaded, and it doesn't have the 12 Nov design changes.

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
- **Your usuals (12 Nov).** The shopping list now learns from finished shops. Items ticked in at least 2 of the last 6 shops show in a "Your usuals" row of small tiles you swipe sideways, each with the size, the price last time and how often it was bought ("Every shop", "3 of 4 shops"). At the largest text sizes the row becomes a plain vertical list. One tap adds an item, or "Add all" adds every one. Items already on the list are hidden. Shop details come from `spending-trip-detail` and are kept on the device, so each shop is fetched once. Nothing shows until there are 2 finished shops.
- **Native iOS 26 navigation (12 Nov).**
  - The custom floating tab bar and its sideways slide are replaced by the system `TabView`, which gives the Liquid Glass tab bar and shrinks it while scrolling down.
  - Each tab has a native large title (in Inter) with the profile button, and on Plans and List a + button, in the system toolbar.
  - The List screen's "Swipe to finish" and assistant controls now sit just above the tab bar instead of behind a fixed 96-point gap.
  - Pushed screens such as Settings use the system back button, labelled with the screen you came from. UI tests now find it by its `BackButton` identifier.
  - In the plan builder, the keyboard's Done bar stopped appearing once the builder covered the system tab bar. While you type, Done now sits in the top bar in place of the ••• menu, as in Notes. The keyboard Done bars in sheets (budget, list photo review) still work.
- **Design and copy pass (12 Nov).**
  - Spend: the five-colour donut is now one bar in shades of the text colour, biggest category darkest, with a ranked list showing percent and amount. The bar under the total uses the same black as Home, and both screens say "$33.60 left of your $120 target".
  - Spend explains its two totals: "From the 8 of 10 items that had a price" and "$4.00 of your checkout total isn't in a category", in grey rather than amber.
  - All-caps labels removed from Spend and the Home week card ("THIS WEEK", "TRACKED", "PATTERN").
  - Insight text from the backend shows "$" instead of "A$", like the rest of the app. The backend's own fallback copy ("Added items shaped spend") still needs rewording in `spending-insights.ts`.
  - Dates read the Australian way: "9–15 Nov".
  - Plans no longer shows the AI-written week label as its subtitle, since its format varies.
  - Home: once there's a plan, Create a plan moves to the + in the top bar. The second "This week" card and the separate store card are replaced by one grouped list: Your plan, and the store.
  - The list's "Tap the circle…" hint shows only until the first tick.
  - Cards on Home, List and Plans have a barely visible edge in light mode, like iOS grouped lists.
  - Sample data and coaching tones rewritten in plain words.
  - A sweep of every screen's text replaced the last vague or padded lines: "Three takeaways" is now "Notes on this shop", "What shaped the shop" is now "Planned or added", "Why it matters" is now "Context", "Working securely..." is now "Signing in…". The aisle-guide step now says what the photo is for ("Reasi uses it to put your list in aisle order"). The shop recap shows "$" too.
- **No empty picture frames (12 Nov).** Meal photos and product photos load when the backend has them; the sample data has none, and a new plan's meal photos arrive a few seconds after the plan.
  - Plans: a meal without a photo shows its day ("Mon") in a small tile, like Calendar, with today's tile filled. The muddy gradient boxes, coloured from the plan's AI-picked tone, are gone.
  - Home leads with tonight's dinner ("Tonight · Chicken souvlaki plates") when the week plan has today's day, otherwise the first meal. Without a photo it's a light card, not an empty dark one.
  - The meal detail header without a photo is a plain dark panel, like Home.
  - List rows without a product photo show an aisle symbol from the item's name, then its aisle: leaf for spinach, fish for salmon, fridge for milk, snowflake for frozen, and a basket when nothing matches. Keywords must start a word, so "steak" isn't tea and "foil" isn't oil. Unit tests cover this.
- **Fewer words (12 Nov).** Screens keep numbers and names and drop the explanations.
  - List: the summary is the total, "2 of 20" and one short line ("3 unpriced", "Prices from 9 Oct"). The label above the total and the "Tap the circle…" hint are gone; VoiceOver still names the total. Usuals tiles show name, size and price only.
  - Home: "$33.60 left of $120", "Current list", "7 dinners · 20 items", and the store row is just the store name.
  - Spend: one line under the categories ("8 of 10 items priced · $4.00 not itemised"), tips show their title only, and "Projected basket" is now "Current list".
  - Plans: the "At a glance" card and its AI-written paragraph are replaced by one subtitle ("7 dinners · $101 · Coles Top Ryde"); each meal row has one line ("25 min · $18").
  - Onboarding and empty states are cut to one short line each.
  - The stale-price warning stays, as "Prices from 9 Oct, may have changed".
- **+ in the bottom bar (12 Nov).** The + is a separate round button at the end of the tab bar (a system `Tab` with the search role whose selection is intercepted, so it acts without switching tabs). On List it opens Add item, which now pops up just above the button; elsewhere it opens the plan builder. The top bar keeps only the profile button.
- **Real photos in the sample data (12 Nov).**
  - In the production catalogue, 21,908 of 22,107 products have a Coles photo and 176 of the 204 meals created since 24 Aug have a Pexels photo. The app shows them; icons and day tiles are only the fallback.
  - The sample shopping list now uses 17 real Coles products (name, size, price, photo) and the seven sample meals have Pexels photos with photographer credit, so the simulator and App Store screenshots show pictures. Three items stay unmatched to show an unpriced row.
  - About 19,300 catalogue photo links are stored without the `/productimages/` folder and fail if requested as is. The backend's product search already adds it; the app now does too (`ProductImageURL.normalized`, unit tested).
- **Copy fixes (12 Nov).** Spend no longer shows a wifi icon and "Try again" when nobody is signed in. Home says "Nothing spent yet · $170 target" instead of "$170.00 left of your $170 target".
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

**Archived on 12 Nov 2026.** Build `1.0.0 (14)` is in Xcode Organizer as `Reasi-1.0.0-14.xcarchive` and passes the release preflight. Upload this one, not `Reasi-1.0.0-13.xcarchive`, which predates the 12 Nov design changes. In Organizer, choose Validate App, then Distribute App > App Store Connect, once the App Store Connect record and agreements are in place. The App Store screenshots in `docs/app-store-screenshots/` were recaptured from this design on the same day.

CI note: PR #47's `iOS Release build` run stayed queued with no job created, because GitHub never assigned a `macos-26` hosted runner. The same workflow ran on 11 Oct. If it is still queued, re-run it from the Actions tab.

- Run the Release configuration on a physical iPhone.
- Archive with Any iOS Device selected, then Validate and Upload in Organizer.

## Not verified on this branch

- Sign-in, purchases and plan generation against production. There were no test accounts, and creating real accounts was out of scope.
- The price-age line with real catalogue dates. The sample data has no capture dates, so the line is covered by unit tests only.
