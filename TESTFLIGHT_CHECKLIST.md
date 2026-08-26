# Reasi TestFlight Checklist

Current app metadata:

- Bundle ID: `ai.reasi.ios`
- Version: `1.0.0`
- Build: `1`
- Deployment target: iOS 26.0
- Privacy URL placeholder: `https://reasi.ai/privacy`
- Sign-in: Apple, Google, and email

## Before Archiving

1. Join the paid Apple Developer Program. Internal TestFlight still requires an App Store Connect app and distribution signing.
2. Register `ai.reasi.ios` as an explicit App ID in Certificates, Identifiers & Profiles, enable Sign in with Apple as the primary App ID, and refresh the Xcode-managed provisioning profile.
3. Create or approve the Reasi app record in App Store Connect using that exact bundle ID.
4. Supply a final, brand-approved, opaque 1024 x 1024 App Store icon. The current project intentionally does not use the Expo placeholder.
5. Publish `https://reasi.ai/privacy` over HTTPS and verify it opens without authentication.
6. Confirm the Release configuration contains only public client values: Supabase URL/publishable key, PostHog project key, RevenueCat public SDK key, and Google client ID/scheme.
7. In Xcode, select the Reasi target, choose the registered team, and confirm automatic signing resolves an Apple Distribution profile.
8. Increment `CURRENT_PROJECT_VERSION` for every upload after build 1.
9. Build and run the Release configuration on a device, then choose Product > Archive with Any iOS Device selected.
10. In Organizer, run Validate App before Distribute App > App Store Connect > Upload.

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
- RevenueCat and Apple purchase processing before subscriptions are enabled.
- Retention periods, security measures, user rights, contact details, and how account deletion removes the account, owned rows, and uploaded images.

## Apple Account Setup

1. The Account Holder or Admin opens Certificates, Identifiers & Profiles > Identifiers > `ai.reasi.ios`.
2. Enable Sign in with Apple, configure it as the primary App ID, and save. Leave the server-to-server notification URL empty for this native Supabase flow.
3. In Xcode, open Signing & Capabilities for Reasi, confirm the team and Sign in with Apple capability, then let automatic signing regenerate the development and distribution profiles.
4. In Supabase Auth > Providers > Apple, enable the provider and set Client IDs to `ai.reasi.ios`. Do not add a web Services ID, `.p8` key, or rotating secret unless Reasi later adds web-based Apple OAuth.
5. Run all Apple checks above on a physical iPhone before uploading the TestFlight build.
