#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT/Reasi.xcodeproj/project.pbxproj"
SOURCE_INFO="$ROOT/Reasi/Info.plist"
SOURCE_ENTITLEMENTS="$ROOT/Reasi/Reasi.entitlements"
ICON="$ROOT/Reasi/Resources/Assets.xcassets/AppIcon.appiconset/ReasiAppIcon.png"
APP_PATH="${1:-}"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$1"
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

require_source_release_setting() {
  local key="$1"
  local value="$2"
  rg -q "^[[:space:]]*$key = $value;" "$PROJECT_FILE" \
    || fail "Release setting $key must be $value"
}

require_nonempty_source_copy() {
  local key="$1"
  local value
  value="$(plist_value "$SOURCE_INFO" "$key")"
  [[ -n "$value" ]] || fail "$key must contain clear user-facing copy"
}

require_source_release_setting "REASI_ENABLE_DEBUG_GUEST_AUTH" "NO"
require_source_release_setting "REASI_ENABLE_DEBUG_FIXTURES" "NO"
pass "Release disables guest auth and fixture fallback"

require_nonempty_source_copy "NSCameraUsageDescription"
require_nonempty_source_copy "NSPhotoLibraryUsageDescription"
pass "Camera and photo-library permission copy is present"

[[ -f "$ICON" ]] || fail "App Store icon is missing"
[[ "$(sips -g pixelWidth "$ICON" 2>/dev/null | awk '/pixelWidth/ {print $2}')" == "1024" ]] \
  || fail "App Store icon must be 1024 pixels wide"
[[ "$(sips -g pixelHeight "$ICON" 2>/dev/null | awk '/pixelHeight/ {print $2}')" == "1024" ]] \
  || fail "App Store icon must be 1024 pixels high"
[[ "$(sips -g hasAlpha "$ICON" 2>/dev/null | awk '/hasAlpha/ {print $2}')" == "no" ]] \
  || fail "App Store icon must be opaque"
pass "App Store icon is opaque 1024 x 1024"

[[ "$(plist_value "$SOURCE_INFO" "ITSAppUsesNonExemptEncryption")" == "false" ]] \
  || fail "Export-compliance declaration is missing"
pass "Export-compliance declaration is present"

if [[ "${REQUIRE_APPLE_AUTH:-0}" == "1" ]]; then
  rg -q 'com.apple.developer.applesignin' "$SOURCE_ENTITLEMENTS" \
    || fail "Sign in with Apple entitlement is missing; include the Apple-auth PR"
  rg -q 'REASI_ENABLE_APPLE_AUTH = YES;' "$PROJECT_FILE" \
    || fail "Release Apple auth flag is not enabled; include the Apple-auth PR"
  pass "Sign in with Apple entitlement and Release flag are enabled"
fi

if [[ -n "$APP_PATH" ]]; then
  [[ -d "$APP_PATH" ]] || fail "Built app does not exist at $APP_PATH"
  BUILT_INFO="$APP_PATH/Info.plist"
  [[ -f "$BUILT_INFO" ]] || fail "Built app Info.plist is missing"

  [[ "$(plist_value "$BUILT_INFO" "CFBundleIdentifier")" == "ai.reasi.ios" ]] \
    || fail "Built bundle identifier is not ai.reasi.ios"
  [[ -n "$(plist_value "$BUILT_INFO" "CFBundleShortVersionString")" ]] \
    || fail "Built app version is empty"
  [[ -n "$(plist_value "$BUILT_INFO" "CFBundleVersion")" ]] \
    || fail "Built app build number is empty"
  pass "Built app identity and version metadata are present"

  for flag in REASI_ENABLE_DEBUG_GUEST_AUTH REASI_ENABLE_DEBUG_FIXTURES; do
    value="$(plist_value "$BUILT_INFO" "$flag" | tr '[:lower:]' '[:upper:]')"
    [[ "$value" == "NO" || "$value" == "FALSE" || "$value" == "0" ]] \
      || fail "$flag is enabled or unresolved in the Release bundle"
  done
  pass "Built Release bundle cannot enable debug auth or fixtures"

  executable="$APP_PATH/$(plist_value "$BUILT_INFO" "CFBundleExecutable")"
  [[ -f "$executable" ]] || fail "Built app executable is missing"
  if strings "$executable" | rg -q 'Continue for testing|-ReasiUITestUnauthenticated|-ReasiSkipBrandIntro'; then
    fail "Debug-only UI/test behavior is present in the Release executable"
  fi
  pass "Debug-only UI and launch hooks are absent from Release"

  if find "$APP_PATH" -type f -maxdepth 5 -print0 \
    | xargs -0 strings 2>/dev/null \
    | rg -q 'sk-proj-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9_-]{32,}|SUPABASE_SERVICE_ROLE_KEY|OPENAI_API_KEY|REVENUECAT_(SECRET|WEBHOOK_SECRET)'; then
    fail "A server-secret pattern was found in the app bundle"
  fi
  pass "No OpenAI, service-role, or RevenueCat secret pattern was found in the bundle"

  privacy_url="$(plist_value "$BUILT_INFO" "REASI_PRIVACY_POLICY_URL")"
  terms_url="$(plist_value "$BUILT_INFO" "REASI_TERMS_OF_SERVICE_URL")"
  [[ "$privacy_url" == "https://www.reasiai.com/privacy" ]] \
    || fail "Built privacy URL must be https://www.reasiai.com/privacy"
  [[ "$terms_url" == "https://www.reasiai.com/terms" ]] \
    || fail "Built terms URL must be https://www.reasiai.com/terms"
  pass "Built legal links point to the production URLs"
fi

if [[ "${CHECK_LIVE_LEGAL_URLS:-0}" == "1" ]]; then
  for url in https://www.reasiai.com/privacy https://www.reasiai.com/terms; do
    status="$(curl --location --silent --output /dev/null --write-out '%{http_code}' --max-time 15 "$url")"
    [[ "$status" == "200" ]] || fail "$url returned HTTP $status"
  done
  pass "Privacy and terms URLs return HTTP 200"
fi

printf '\nReasi TestFlight release preflight passed.\n'
