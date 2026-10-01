#!/bin/bash
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
host="$(mktemp -d /tmp/reasi-core-reliability.XXXXXX)"
mkdir -p "$host/Tests/CoreLoopReliabilityTests"
ln -s "$root/ReasiTests/CoreLoopReliabilityHost/Package.swift" "$host/Package.swift"
for source in Reasi/Core/Services/CoreLoopStore.swift Reasi/Core/Models/MealPlanModels.swift Reasi/Core/Models/Store.swift Reasi/Core/Models/OnboardingPreferences.swift Reasi/Core/Models/SpendingModels.swift Reasi/Core/Fixtures/FixtureStores.swift Reasi/DesignSystem/ReasiMotion.swift ReasiTests/CoreLoopReliabilityTests.swift ReasiTests/CoreLoopReliabilityHost/ServiceDoubles.swift; do
    ln -s "$root/$source" "$host/Tests/CoreLoopReliabilityTests/$(basename "$source")"
done
swift test --package-path "$host"
