# Reasi TestFlight Checklist

Current app metadata:

- Bundle ID: `ai.reasi.ios`
- Version: `1.0.0`
- Build: `1`
- Deployment target: iOS 26.0
- Privacy URL placeholder: `https://reasi.ai/privacy`
- Sign-in for internal TestFlight: Google and email

## Before Archiving

1. Join the paid Apple Developer Program. Internal TestFlight still requires an App Store Connect app and distribution signing.
2. Register `ai.reasi.ios` as an explicit App ID in Certificates, Identifiers & Profiles.
3. Create or approve the Reasi app record in App Store Connect using that exact bundle ID.
4. Supply a final, brand-approved, opaque 1024 x 1024 App Store icon. The current project intentionally does not use the Expo placeholder.
5. Publish `https://reasi.ai/privacy` over HTTPS and verify it opens without authentication.
6. Confirm the Release configuration contains only public client values: Supabase URL/publishable key, PostHog project key, RevenueCat public SDK key, and Google client ID/scheme.
7. In Xcode, select the Reasi target, choose the registered team, and confirm automatic signing resolves an Apple Distribution profile.
8. Increment `CURRENT_PROJECT_VERSION` for every upload after build 1.
9. Build and run the Release configuration on a device, then choose Product > Archive with Any iOS Device selected.
10. In Organizer, run Validate App before Distribute App > App Store Connect > Upload.

## Manual Auth Checks

1. Create a new email account, open the verification link on the same iPhone, then sign in and generate a plan.
2. Request a password reset, open the recovery link on the same iPhone, set a new password in Reasi, sign out, and sign back in with the new password.
3. Cancel Google sign-in once, then complete it once; confirm cancellation is quiet and the completed session survives a cold launch.
4. Sign out and sign back in; confirm the latest saved plan and shopping list return.
5. Delete a disposable account from Profile, then confirm it cannot sign in again and its owned database rows/uploads are gone.

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

## Public App Store Follow-Up

Sign in with Apple must be implemented and enabled before public App Store submission because Reasi offers Google as a third-party sign-in method. It is intentionally absent from this internal TestFlight build.
