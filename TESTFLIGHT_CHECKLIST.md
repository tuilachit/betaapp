# Reasi TestFlight Checklist

Current app metadata:

- Bundle ID: `ai.reasi.ios`
- Version: `1.0.0`
- Build: `1`
- Deployment target: iOS 26.0
- Privacy URL: `https://reasi.ai/privacy`
- Terms URL: `https://reasi.ai/terms`
- Sign-in: Apple, Google, and email after the Apple-auth PR is merged and configured
- Subscription products: `ai.reasi.pro.monthly` and `ai.reasi.pro.annual`

## Before Archiving

1. Join the paid Apple Developer Program. Internal TestFlight still requires an App Store Connect app and distribution signing.
2. Register `ai.reasi.ios` as an explicit App ID in Certificates, Identifiers & Profiles, enable Sign in with Apple as the primary App ID, and refresh the Xcode-managed provisioning profile.
3. Create or approve the Reasi app record in App Store Connect using that exact bundle ID.
4. Enable Sign in with Apple for `ai.reasi.ios`, regenerate signing assets, and finish the Supabase Apple provider setup.
5. Confirm the opaque 1024 x 1024 Reasi icon still passes the release preflight.
6. Publish both `https://reasi.ai/privacy` and `https://reasi.ai/terms` over HTTPS and verify they open without authentication.
7. Confirm the Release configuration contains only public client values: Supabase URL/publishable key, PostHog public project key, RevenueCat public iOS SDK key, and Google client ID/scheme.
8. Merge the backend generation, store/state, Reasi Pro, and release-security PRs in dependency order, then run the documented backend TestFlight release workflow.
9. In Xcode, select the Reasi target, choose the registered team, and confirm automatic signing resolves an Apple Distribution profile.
10. Increment `CURRENT_PROJECT_VERSION` for every upload after build 1.
11. Run `scripts/testflight-release-preflight.sh` against the built Release app with `REQUIRE_APPLE_AUTH=1` and `CHECK_LIVE_LEGAL_URLS=1`.
12. Build and run the Release configuration on a physical iPhone, then choose Product > Archive with Any iOS Device selected.
13. In Organizer, run Validate App before Distribute App > App Store Connect > Upload.

## Automated Checks

1. Run the shared `Reasi` scheme on an iOS 26 simulator. It includes `ReasiTests` and `ReasiUITests`.
2. Confirm the unit/UI suite passes before every TestFlight archive.
3. Build the app using the Release configuration.
4. Run `scripts/testflight-release-preflight.sh /path/to/Reasi.app`.
5. For the final integrated branch, run `REQUIRE_APPLE_AUTH=1 CHECK_LIVE_LEGAL_URLS=1 scripts/testflight-release-preflight.sh /path/to/Reasi.app`.

## Manual Auth Checks

1. In Supabase Auth > Providers > Apple, enable Apple and add `ai.reasi.ios` as the native client ID. A native-only flow does not require a Services ID or rotating OAuth secret.
2. Authorize Apple once with Share My Email, confirm the first-login name is saved, then sign out and authorize again; the second login must succeed without Apple returning the name.
3. Revoke the disposable Apple authorization, authorize again with Hide My Email, and confirm Reasi labels the private relay account without exposing a real address.
4. Cancel Apple sign-in and confirm the app silently returns to the auth screen.
5. Create a new email account, open the verification link on the same iPhone, then sign in and generate a plan.
6. Request a password reset, open the recovery link on the same iPhone, set a new password in Reasi, sign out, and sign back in with the new password.
7. Cancel Google sign-in once, then complete it once; confirm cancellation is quiet and the completed session survives a cold launch.
8. Sign out and sign back in; confirm the latest saved plan and shopping list return.
9. Delete disposable Apple, Google, and email accounts from Profile; confirm each can no longer sign in and its owned rows/uploads are gone.

## Subscription Checks

1. In App Store Connect, create the `Reasi Pro` subscription group and both monthly and annual products.
2. Set the intended Australian prices and the seven-day annual introductory trial.
3. In RevenueCat, configure entitlement `reasi_pro`, offering `default`, both App Store products, and the public iOS SDK key used by the app.
4. Configure and sign the RevenueCat-to-Supabase webhook; keep that secret server-side only.
5. With sandbox accounts, test monthly purchase, annual trial, cancellation, expiration, billing failure, restore, and offline entitlement behavior.
6. Confirm each account receives exactly one complete free-preview plan and can keep using that plan after the preview is claimed.

## App Store Connect

1. Open My Apps > Reasi > TestFlight.
2. Wait for build `1.0.0 (1)` to finish processing.
3. Complete the export-compliance question. Reasi currently uses standard HTTPS transport and declares no non-exempt encryption.
4. Add internal testers under Users and Access if they are not already App Store Connect users.
5. Create an Internal Testing group, add the processed build, then add the testers.
6. Add concise Test Information: the core flow to test, a support email, and any test account instructions. Never put passwords or secret keys in review notes.
7. Confirm each tester receives the TestFlight invitation and can install the build.
8. For external TestFlight later, complete Beta App Review information, screenshots where requested, contact details, privacy URL, and review notes, then submit the build for Beta App Review.

## Privacy Policy Coverage

The hosted policy must explain:

- Account data handled by Supabase and the Google/email authentication methods.
- Meal preferences, generated plans, shopping lists, product imports, uploaded product/list photos, and assistant chat data stored for the user.
- OpenAI processing performed only through Supabase Edge Functions for meal generation, vision/OCR, product resolution, comparison, and shopping assistance.
- PostHog analytics, including the categories of events collected and the fact that raw grocery lists, photos, and full chat content are not intentionally sent to analytics.
- RevenueCat and Apple purchase processing, free-preview access, subscription state, renewal, and restore behavior.
- Retention periods, security measures, user rights, contact details, and how account deletion removes the account, owned rows, and uploaded images.

## External Setup Still Required

- Apple Account Holder/Admin: enable Sign in with Apple, approve agreements, banking, tax, subscription products, prices, and trial.
- Supabase Pro: enable leaked-password protection, set a ten-character password minimum, disable anonymous sign-ins, and deploy the reviewed migrations/functions.
- RevenueCat: create the products/offering/entitlement and install the signed webhook secret in Supabase.
- Reasi website: publish the final privacy and terms pages before upload.

## Apple Account Setup

1. The Account Holder or Admin opens Certificates, Identifiers & Profiles > Identifiers > `ai.reasi.ios`.
2. Enable Sign in with Apple, configure it as the primary App ID, and save. Leave the server-to-server notification URL empty for this native Supabase flow.
3. In Xcode, open Signing & Capabilities for Reasi, confirm the team and Sign in with Apple capability, then let automatic signing regenerate the development and distribution profiles.
4. In Supabase Auth > Providers > Apple, enable the provider and set Client IDs to `ai.reasi.ios`. Do not add a web Services ID, `.p8` key, or rotating secret unless Reasi later adds web-based Apple OAuth.
5. Run all Apple checks above on a physical iPhone before uploading the TestFlight build.
