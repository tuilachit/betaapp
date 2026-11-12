# Reasi App Store listing draft (1.0)

Paste these into App Store Connect. The character limits are Apple's, and every field below fits. The copy follows the Reasi voice: Australian English, sentence case, no emoji, no exclamation marks.

## App information

| Field | Value |
|---|---|
| Name (30) | Reasi: Grocery Budget Planner |
| Subtitle (30) | Plan meals. Spend less. |
| Primary category | Food & Drink |
| Secondary category | Finance |
| Bundle ID | ai.reasi.ios |
| SKU | reasi-ios-1 |
| Support URL | https://www.reasiai.com/support |
| Marketing URL | https://www.reasiai.com |
| Privacy policy URL | https://www.reasiai.com/privacy |
| Copyright | 2026 Reasi AI |
| Age rating | 4+ (no objectionable content; the assistant chat is limited to shopping help) |
| Availability | Australia only for 1.0 (prices and stores are Sydney Coles) |

## Promotional text (170)

Set a weekly grocery budget and Reasi plans dinners around Coles prices, builds one list in aisle order, and shows how each week compares.

## Description (4000)

Reasi plans your week of groceries around a budget you choose.

Tell Reasi what you want to spend, how many you cook for and what you like to eat. It plans the week's dinners around prices at your Coles store, keeps the basket within your budget, and turns everything into one list ordered the way you walk the shop.

SET YOUR NUMBER
Choose a weekly grocery budget in seconds. Every plan is built to fit it, and you can change it at any time.

SHOP ONE LIST
Meals become a single list matched to real products at your store, with pack sizes and prices. Swap any product, add your own items, or snap a photo of a handwritten list. Tick items off as they go in the trolley and watch the total update.

SEE WHERE IT WENT
Finish a shop and Reasi keeps the total. See this week against your target, where the money went by category, how many weeks you stayed on target, and one practical change for your next shop.

HONEST ABOUT PRICES
Reasi shows when prices were last checked. Prices are estimates and can differ in store.

Reasi Pro
Plan generation needs a Reasi Pro subscription: weekly, monthly (with a 3-day free trial) or annual (with a 14-day free trial). Payment is charged to your Apple ID at confirmation of purchase. The subscription renews automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel it in your App Store account settings.

Terms: https://www.reasiai.com/terms
Privacy: https://www.reasiai.com/privacy

## Keywords (100)

grocery,budget,meal plan,shopping list,coles,spending,dinner,savings,food,weekly,planner,receipt

(96 characters. Don't repeat words from the name or subtitle. Apple matches those anyway.)

## What's new (1.0)

First release.

## App Review information

- **Sign-in:** provide a review account in App Store Connect's Sign-In Information fields, never in these notes or the repo. The account should already have finished onboarding.
- **Notes for the reviewer** (paste as is):

> Reasi plans a week of dinners around a grocery budget and builds a shopping list matched to Coles products.
>
> 1. Sign in with the provided account, or create one with Sign in with Apple or email.
> 2. Reasi Pro is required to generate a plan. Use the monthly plan's 3-day free trial with a Sandbox Apple ID.
> 3. Tap Create a plan, then Create plan. A week takes about a minute to generate.
> 4. Open List, tick a few items, and swipe "Swipe to finish". The shop then appears in Spend.
>
> Account deletion: tap the profile button (top right), scroll to the bottom and tap Delete account.
> Prices are estimates from Coles online and show the date they were last checked.

- **Contact:** your name, phone and email (only in App Store Connect).

## App privacy (nutrition label)

Tracking: **No.** Reasi doesn't link data with third-party data for advertising and has no ad SDKs. `NSPrivacyTracking` is false.

| Data type | Collected | Linked to user | Purpose | Source in the app |
|---|---|---|---|---|
| Contact info: email address | Yes | Yes | App functionality | Email or Google sign-in, Apple relay address (Supabase Auth) |
| Contact info: name | Yes | Yes | App functionality | First-login name from Sign in with Apple |
| Identifiers: user ID | Yes | Yes | App functionality, analytics | Supabase user ID, PostHog `identify` |
| Purchases: purchase history | Yes | Yes | App functionality | RevenueCat entitlement `reasi_pro` |
| User content: photos | Yes | Yes | App functionality | List, product and aisle-guide photos uploaded for reading |
| User content: other | Yes | Yes | App functionality | Preferences, budget, plans, shopping lists, assistant messages |
| Usage data: product interaction | Yes | Yes | Analytics | 69 PostHog events, e.g. onboarding steps and plan created |
| Financial info: other | Yes | Yes | App functionality | Grocery spend totals and the confirmed checkout totals you enter |

Not collected: location, contacts, health, browsing history, search history outside the app, sensitive info, and crash data from a third party.

Check one thing before you submit: if PostHog session replay or autocapture is switched on in the PostHog project, add "Usage data: other usage data". The app code only sends named events.

## Screenshots

Saved in `docs/app-store-screenshots/` at 1320 × 2868 (6.9"), the size App Store Connect requires. Apple scales them down for smaller iPhones. In order:

1. `01-welcome.png`: "Groceries that fit your budget." with the sample receipt.
2. `02-budget.png`: the weekly budget step.
3. `03-home.png`: the This week card.
4. `04-list.png`: the shopping list.
5. `05-spend.png`: Spend month view with the track record.

They use the app's built-in sample data, whose dates follow the day of capture, so the week, Spend range and Home date always agree. To recapture after a design change, run this on an iPhone 17 Pro Max simulator and export the attachments from the result bundle:

```bash
TEST_RUNNER_REASI_CAPTURE_SCREENSHOTS=1 xcodebuild test -project Reasi.xcodeproj -scheme Reasi -destination 'name=iPhone 17 Pro Max' -only-testing:ReasiUITests/ReasiAppStoreScreenshots -resultBundlePath shots.xcresult
```
