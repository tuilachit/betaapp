#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -o "$tmp/preferences" \
  Reasi/Core/Models/Store.swift \
  Reasi/Core/Models/OnboardingPreferences.swift \
  Reasi/Core/Services/OnboardingStore.swift \
  scripts/preference-reliability/PreferenceHarnessStubs.swift \
  scripts/preference-reliability/PreferenceHarness.swift
"$tmp/preferences"
