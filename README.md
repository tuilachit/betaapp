# Reasi iOS

Native SwiftUI rebuild of the Reasi mobile app.

Reference app: `/Users/locnguyen/Documents/Reasi_mobile`

## Phase 0 Scope

- SwiftUI Xcode scaffold.
- Dark premium shell.
- Floating glass bottom navigation.
- Ported design tokens from Expo `src/theme/tokens.ts`.
- Inter typography resources copied from the Expo app dependency cache.
- Haptics, skeleton primitives, and press micro-interactions.
- Supabase, PostHog, and RevenueCat Swift Package references.
- Thin service shells for Phase 1 wiring.

## Toolchain Target

This project is configured for the App Store target stack:

- Xcode 26.6
- Swift 6 compiler toolchain, with Swift 6 language mode
- iOS 26 deployment target

The project has been verified with Xcode 26.6 and the iOS 26 SDK in Swift 6 language mode.

## Backend Boundary

Do not duplicate the backend. The Supabase schema, RLS, and `generate-week-plan` edge function remain in the Expo reference app until the backend is moved into a shared package or repository.

## Phase 4 Status

- Release configuration: `1.0.0 (1)`, bundle ID `ai.reasi.ios`.
- Google and email auth use Supabase sessions stored in Keychain.
- Debug anonymous auth and fixture fallbacks are compile-gated and forced off in Release.
- Camera/photo usage descriptions, privacy URL plumbing, account deletion, offline/error states, and saved-plan restoration are wired.
- The exact App Store Connect handoff is in `TESTFLIGHT_CHECKLIST.md`.

The remaining packaging blocker is a final brand-approved 1024 x 1024 App Store icon. Do not ship the old Expo placeholder. Sign in with Apple is also required before a public App Store submission, though not for internal TestFlight testing.
