#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -swift-version 6 -D DEBUG -parse-as-library -o "$tmp/smart-basket" \
  Reasi/Core/Models/Store.swift \
  Reasi/Core/Models/SmartBasketModels.swift \
  Reasi/Core/Services/SmartBasketReviewStore.swift \
  Reasi/Core/Fixtures/FixtureSmartBasket.swift \
  scripts/smart-basket/SmartBasketHarness.swift
"$tmp/smart-basket"
