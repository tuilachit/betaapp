#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -o "$tmp/spending" \
  Reasi/Core/Models/Store.swift \
  Reasi/Core/Models/SpendingModels.swift \
  Reasi/Core/Services/SpendingStore.swift \
  scripts/spending-identity/SpendingHarnessStubs.swift \
  scripts/spending-identity/SpendingHarness.swift
"$tmp/spending"
