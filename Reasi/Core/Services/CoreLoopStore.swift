import Foundation
import Observation
import SwiftUI

enum WeekPlanGenerationState: Equatable {
    case idle
    case generating
    case succeeded
    case failed(String)
    case cancelled(String)

    var isGenerating: Bool {
        if case .generating = self {
            return true
        }
        return false
    }

    var errorMessage: String? {
        if case .failed(let message) = self {
            return message
        }
        return nil
    }

    var noticeMessage: String? {
        if case .cancelled(let message) = self {
            return message
        }
        return nil
    }

    var isCancelled: Bool {
        if case .cancelled = self {
            return true
        }
        return false
    }
}

enum WeekPlanGenerationStage: String, Equatable {
    case preparing
    case buildingMeals
    case organizingList
    case saving

    var title: String {
        switch self {
        case .preparing:
            "Reading your preferences"
        case .buildingMeals:
            "Building seven dinners"
        case .organizingList:
            "Combining the shopping list"
        case .saving:
            "Saving your week"
        }
    }

    var detail: String {
        switch self {
        case .preparing:
            "Checking household, food style, and store."
        case .buildingMeals:
            "Choosing practical meals with enough variety."
        case .organizingList:
            "Removing duplicates and ordering store sections."
        case .saving:
            "Almost there. Your plan will stay linked to your account."
        }
    }
}

@MainActor
@Observable
final class CoreLoopStore {
    var plan: WeekPlan
    var hasPlan: Bool
    var isRestoringPlan = false
    var planRestoreMessage: String?
    var generationState: WeekPlanGenerationState = .idle
    var generationStage: WeekPlanGenerationStage = .preparing
    var generationElapsedSeconds = 0
    var checkedItemIDs: Set<String>

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let localCache = ShoppingListLocalCache()
    @ObservationIgnored private var progressMilestones: Set<Int> = []
    @ObservationIgnored private var activeUserId: String?
    @ObservationIgnored private var checkedStates: [String: Bool] = [:]
    @ObservationIgnored private var pendingCheckItemIDs: Set<String> = []
    @ObservationIgnored private var pendingImports: [PendingImportedItem] = []
    @ObservationIgnored private var addedImportKeys: Set<String> = []
    @ObservationIgnored private var itemSyncTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var generationProgressTask: Task<Void, Never>?
    @ObservationIgnored private var activeGenerationID: UUID?

    private let lastSuccessfulWeekKeyPrefix = "reasi.lastSuccessfulGeneratedWeekKey"

    init(plan: WeekPlan? = nil, defaults: UserDefaults = .standard) {
        let initialPlan = plan ?? FixtureWeekPlan.current
        self.plan = initialPlan
        hasPlan = plan != nil
        self.defaults = defaults
        checkedItemIDs = Self.checkedIDs(from: initialPlan)
    }

    var allShoppingItems: [ShoppingListItem] {
        guard hasPlan else { return [] }
        return plan.shoppingList.sections.flatMap(\.items)
    }

    var checkedCount: Int {
        checkedItemIDs.count
    }

    var shoppingProgress: Double {
        guard !allShoppingItems.isEmpty else { return 0 }
        return Double(checkedCount) / Double(allShoppingItems.count)
    }

    func syncFixturePlan(to store: StoreSummary) {
        guard plan.source == .fixture, plan.storeId != store.id else { return }

        let previousCheckedIDs = checkedItemIDs
        let updatedPlan = FixtureWeekPlan.plan(for: store)
        let validItemIDs = Set(updatedPlan.shoppingList.sections.flatMap(\.items).map(\.id))

        plan = updatedPlan
        checkedItemIDs = previousCheckedIDs.intersection(validItemIDs)
        progressMilestones = []
    }

    func activateUser(_ userId: String?, selectedStore: StoreSummary) {
        guard activeUserId != userId else { return }
        cancelOutstandingWork()
        activeUserId = userId

        guard let userId,
              let cached = localCache.loadPlan(userId: userId),
              cached.plan.source == .supabase else {
            clearVisiblePlan(selectedStore: selectedStore)
            return
        }

        plan = cached.plan
        hasPlan = true
        pendingImports = cached.pendingImports
        addedImportKeys = Set(cached.pendingImports.map(\.idempotencyKey))

        let checkSnapshot = localCache.loadChecks(userId: userId)
        if checkSnapshot?.shoppingListId == cached.plan.shoppingList.id {
            checkedStates = checkSnapshot?.states ?? [:]
            pendingCheckItemIDs = Set(checkSnapshot?.pendingItemIDs ?? [])
            applyCheckedStates(checkedStates, to: &plan)
            checkedItemIDs = Set(checkedStates.filter(\.value).map(\.key))
                .intersection(Set(allItemIDs(in: plan)))
        } else {
            checkedItemIDs = Self.checkedIDs(from: cached.plan)
            checkedStates = Dictionary(uniqueKeysWithValues: allItemIDs(in: cached.plan).map {
                ($0, checkedItemIDs.contains($0))
            })
            pendingCheckItemIDs = []
        }
        progressMilestones = []
    }

    func restoreLatestPlan(supabase: SupabaseService, selectedStore: StoreSummary) async {
        guard supabase.isSignedIn, !isRestoringPlan else { return }

        isRestoringPlan = true
        planRestoreMessage = nil
        defer { isRestoringPlan = false }

        do {
            guard var restored = try await supabase.fetchLatestWeekPlan() else {
                if let activeUserId {
                    localCache.remove(userId: activeUserId)
                }
                clearVisiblePlan(selectedStore: selectedStore)
                return
            }

            let cachedPlan = activeUserId.flatMap { localCache.loadPlan(userId: $0) }
            if cachedPlan?.plan.shoppingList.id == restored.shoppingList.id {
                pendingImports = cachedPlan?.pendingImports ?? []
                addedImportKeys = Set(pendingImports.map(\.idempotencyKey))
                mergePendingImportedItems(from: cachedPlan?.plan, into: &restored)
            } else {
                pendingImports = []
                addedImportKeys = []
            }

            var restoredCheckedIDs = Self.checkedIDs(from: restored)
            if let activeUserId,
               let localChecks = localCache.loadChecks(userId: activeUserId),
               localChecks.shoppingListId == restored.shoppingList.id {
                checkedStates = Dictionary(uniqueKeysWithValues: allItemIDs(in: restored).map {
                    ($0, restoredCheckedIDs.contains($0))
                })
                pendingCheckItemIDs = Set(localChecks.pendingItemIDs)
                    .intersection(Set(allItemIDs(in: restored)))
                for itemId in pendingCheckItemIDs {
                    let isChecked = localChecks.states[itemId] ?? false
                    checkedStates[itemId] = isChecked
                    if isChecked {
                        restoredCheckedIDs.insert(itemId)
                    } else {
                        restoredCheckedIDs.remove(itemId)
                    }
                }
                applyCheckedStates(checkedStates, to: &restored)
            } else {
                checkedStates = Dictionary(uniqueKeysWithValues: allItemIDs(in: restored).map {
                    ($0, restoredCheckedIDs.contains($0))
                })
                pendingCheckItemIDs = []
            }

            withAnimation(ReasiMotion.base) {
                plan = restored
                hasPlan = true
                checkedItemIDs = restoredCheckedIDs
                progressMilestones = []
            }
            persistPlanCache()
            persistCheckCache()
            await syncPendingChanges(supabase: supabase)
        } catch {
            planRestoreMessage = supabase.userFacingMessage(
                for: error,
                fallback: "Your saved plan could not be loaded yet. Pulling it in will work when Reasi reconnects."
            )
        }
    }

    func clearVisiblePlan(selectedStore: StoreSummary) {
        plan = FixtureWeekPlan.plan(for: selectedStore)
        hasPlan = false
        checkedItemIDs = []
        checkedStates = [:]
        pendingCheckItemIDs = []
        pendingImports = []
        addedImportKeys = []
        progressMilestones = []
        generationState = .idle
        generationStage = .preparing
        generationElapsedSeconds = 0
    }

    func generateWeekPlan(
        store: StoreSummary,
        supabase: SupabaseService,
        analytics: AnalyticsService,
        appState: AppState,
        network: NetworkMonitor? = nil
    ) async {
        guard generationTask == nil else { return }

        let generationID = UUID()
        activeGenerationID = generationID
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performWeekPlanGeneration(
                generationID: generationID,
                store: store,
                supabase: supabase,
                analytics: analytics,
                appState: appState,
                network: network
            )
        }
        generationTask = task
        await task.value
    }

    func cancelGeneration(analytics: AnalyticsService) {
        guard generationTask != nil else { return }

        generationTask?.cancel()
        generationProgressTask?.cancel()
        generationState = .cancelled("Planning stopped. Nothing was changed, and you can try again whenever you’re ready.")
        analytics.capture(.planGenerationFailed, properties: [
            "store_id": .string(plan.storeId.rawValue),
            "reason": .string("cancelled"),
            "elapsed_seconds": .int(generationElapsedSeconds)
        ])
        ReasiHaptics.selection()
    }

    private func performWeekPlanGeneration(
        generationID: UUID,
        store: StoreSummary,
        supabase: SupabaseService,
        analytics: AnalyticsService,
        appState: AppState,
        network: NetworkMonitor?
    ) async {
        defer {
            if activeGenerationID == generationID {
                generationProgressTask?.cancel()
                generationProgressTask = nil
                generationTask = nil
                activeGenerationID = nil
            }
        }

        let weekStart = Self.isoWeekStartString(from: Date())
        let source = supabase.status.state == .configured ? "supabase" : "fixture"

        generationState = .generating
        generationStage = .preparing
        generationElapsedSeconds = 0
        startGenerationProgress(for: generationID)
        ReasiHaptics.light()
        analytics.capture(.planGenerationStarted, properties: [
            "store_id": .string(store.id.rawValue),
            "week_start": .string(weekStart),
            "source": .string(source)
        ])

        do {
            if network?.isConnected == false {
                throw ReasiServiceError.offline
            }

            let previousWeekStart = try? await supabase.fetchLatestGeneratedWeekStart()
            try Task.checkCancellation()

            let generated = try await supabase.generateWeekPlan(
                input: GenerateWeekPlanInput(
                    storeId: store.id,
                    weekStart: weekStart,
                    idempotencyKey: "ios-\(UUID().uuidString)"
                )
            )
            try Task.checkCancellation()

            generationStage = .saving

            withAnimation(ReasiMotion.slow) {
                plan = generated
                hasPlan = true
                checkedItemIDs = Self.checkedIDs(from: generated)
                checkedStates = Dictionary(uniqueKeysWithValues: allItemIDs(in: generated).map {
                    ($0, checkedItemIDs.contains($0))
                })
                pendingCheckItemIDs = []
                pendingImports = []
                addedImportKeys = []
                progressMilestones = []
                generationState = .succeeded
            }
            persistPlanCache()
            persistCheckCache()

            analytics.capture(.planGenerationSucceeded, properties: [
                "store_id": .string(generated.storeId.rawValue),
                "week_start": .string(weekStart),
                "source": .string(generated.source.rawValue),
                "meal_count": .int(generated.meals.count),
                "item_count": .int(allShoppingItems.count)
            ])
            analytics.capture(.shoppingListCreated, properties: [
                "store_id": .string(generated.storeId.rawValue),
                "source": .string(generated.source.rawValue),
                "item_count": .int(allShoppingItems.count),
                "section_count": .int(generated.shoppingList.sections.count)
            ])
            captureWeeklyReturnIfNeeded(
                previousWeekStart: previousWeekStart,
                weekStart: weekStart,
                analytics: analytics
            )
            analytics.flush()
            ReasiHaptics.success()
            appState.showPlan()
        } catch is CancellationError {
            if activeGenerationID == generationID,
               !generationState.isCancelled {
                generationState = .cancelled("Planning stopped. Nothing was changed, and you can try again whenever you’re ready.")
                analytics.capture(.planGenerationFailed, properties: [
                    "store_id": .string(store.id.rawValue),
                    "week_start": .string(weekStart),
                    "source": .string(source),
                    "reason": .string("cancelled")
                ])
            }
        } catch {
            let message = supabase.userFacingMessage(
                for: error,
                fallback: "We couldn't finish your week just now. Your existing plan is safe; please try again."
            )
            generationState = .failed(message)
            analytics.capture(.planGenerationFailed, properties: [
                "store_id": .string(store.id.rawValue),
                "week_start": .string(weekStart),
                "source": .string(source),
                "error": .string(message)
            ])
            ReasiHaptics.warning()
        }
    }

    func openShoppingList(appState: AppState, analytics: AnalyticsService) {
        guard hasPlan else { return }
        ReasiHaptics.light()
        analytics.capture(.shoppingListViewed, properties: shoppingListProperties)
        appState.showShoppingList()
    }

    func toggleItem(
        _ item: ShoppingListItem,
        supabase: SupabaseService,
        analytics: AnalyticsService
    ) {
        guard hasPlan else { return }
        let willCheck = !checkedItemIDs.contains(item.id)

        withAnimation(ReasiMotion.tactileSpring) {
            if willCheck {
                checkedItemIDs.insert(item.id)
            } else {
                checkedItemIDs.remove(item.id)
            }
            setItemChecked(item.id, checked: willCheck, in: &plan)
        }

        checkedStates[item.id] = willCheck
        pendingCheckItemIDs.insert(item.id)
        persistCheckCache()
        startItemSync(itemId: item.id, supabase: supabase)

        ReasiHaptics.selection()
        analytics.capture(.shoppingItemChecked, properties: [
            "store_id": .string(plan.storeId.rawValue),
            "shopping_list_id": .string(plan.shoppingList.id),
            "item_id": .string(item.id),
            "section_type": .string(item.sectionType.rawValue),
            "checked": .bool(willCheck),
            "progress_percent": .int(Int((shoppingProgress * 100).rounded()))
        ])
        captureProgressMilestones(analytics: analytics)
    }

    func addImportedCandidate(
        _ candidate: ProductCandidate,
        quantity: String = "1",
        idempotencyKey: String,
        supabase: SupabaseService,
        analytics: AnalyticsService
    ) async -> Bool {
        guard hasPlan, let clientId = UUID(uuidString: idempotencyKey) else { return false }
        if addedImportKeys.contains(idempotencyKey) { return true }

        let sortOrder = allShoppingItems.count + 1
        let localItemID = "local-import-\(idempotencyKey)"

        let item = ShoppingListItem(
            id: localItemID,
            name: candidate.displayName,
            quantity: quantity,
            checked: false,
            aisleLabel: "Location not certain",
            sectionType: .unknown,
            product: ProductSnapshot(
                sku: nil,
                productName: candidate.displayName,
                brand: candidate.brand,
                size: candidate.size,
                priceAud: candidate.priceAud,
                imageUrl: candidate.imageUrl,
                capturedAt: candidate.capturedAt
            ),
            importedCandidate: candidate,
            locationUncertaintyText: candidate.uncertaintyText,
            clientId: idempotencyKey
        )

        let pending = PendingImportedItem(
            idempotencyKey: idempotencyKey,
            localItemID: localItemID,
            shoppingListId: plan.shoppingList.id,
            candidate: candidate,
            quantity: quantity,
            sortOrder: sortOrder
        )
        pendingImports.append(pending)
        addedImportKeys.insert(idempotencyKey)
        checkedStates[localItemID] = false

        withAnimation(ReasiMotion.tactileSpring) {
            if let sectionIndex = plan.shoppingList.sections.firstIndex(where: { $0.label == "Added items" }) {
                plan.shoppingList.sections[sectionIndex].items.append(item)
            } else {
                plan.shoppingList.sections.append(
                    ShoppingListSection(
                        label: "Added items",
                        sortKey: 980,
                        type: .unknown,
                        items: [item]
                    )
                )
            }
        }
        persistPlanCache()
        persistCheckCache()

        ReasiHaptics.success()
        analytics.capture(.productCandidateAdded, properties: [
            "method": .string("review"),
            "store_id": .string(plan.storeId.rawValue),
            "shopping_list_id": .string(plan.shoppingList.id),
            "confidence": .string(candidate.confidence.rawValue),
            "has_price": .bool(candidate.priceAud != nil),
            "has_source": .bool(!candidate.sourceName.isEmpty)
        ])

        await syncPendingImport(pending, clientId: clientId, supabase: supabase)
        return true
    }

    func markWeekPlanViewed(analytics: AnalyticsService) {
        guard hasPlan else { return }
        analytics.capture(.weekPlanViewed, properties: [
            "store_id": .string(plan.storeId.rawValue),
            "source": .string(plan.source.rawValue),
            "meal_count": .int(plan.meals.count)
        ])
    }

    func markShoppingListViewed(analytics: AnalyticsService) {
        guard hasPlan else { return }
        analytics.capture(.shoppingListViewed, properties: shoppingListProperties)
    }

    private var shoppingListProperties: [String: AnalyticsProperty] {
        [
            "store_id": .string(plan.storeId.rawValue),
            "source": .string(plan.source.rawValue),
            "shopping_list_id": .string(plan.shoppingList.id),
            "item_count": .int(allShoppingItems.count),
            "section_count": .int(plan.shoppingList.sections.count)
        ]
    }

    private func captureWeeklyReturnIfNeeded(
        previousWeekStart: String?,
        weekStart: String,
        analytics: AnalyticsService
    ) {
        guard let currentWeek = Self.calendarWeekKey(fromISODate: weekStart) else { return }
        let storageKey = "\(lastSuccessfulWeekKeyPrefix).\(activeUserId ?? "anonymous")"
        let previousWeek = previousWeekStart.flatMap(Self.calendarWeekKey(fromISODate:))
            ?? defaults.string(forKey: storageKey)

        if let previousWeek, previousWeek != currentWeek {
            analytics.capture(.weeklyReturnDetected, properties: [
                "previous_week": .string(previousWeek),
                "current_week": .string(currentWeek)
            ])
        }

        defaults.set(currentWeek, forKey: storageKey)
    }

    private func startGenerationProgress(for generationID: UUID) {
        generationProgressTask?.cancel()
        generationProgressTask = Task { @MainActor [weak self] in
            for second in 1...120 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self,
                      self.activeGenerationID == generationID,
                      self.generationState.isGenerating else { return }

                self.generationElapsedSeconds = second
                switch second {
                case 0..<8:
                    self.generationStage = .preparing
                case 8..<30:
                    self.generationStage = .buildingMeals
                case 30..<75:
                    self.generationStage = .organizingList
                default:
                    self.generationStage = .saving
                }
            }
        }
    }

    private func cancelOutstandingWork() {
        generationTask?.cancel()
        generationProgressTask?.cancel()
        itemSyncTasks.values.forEach { $0.cancel() }
        generationTask = nil
        generationProgressTask = nil
        itemSyncTasks = [:]
        activeGenerationID = nil
    }

    private func startItemSync(itemId: String, supabase: SupabaseService) {
        guard !itemId.hasPrefix("local-import-"), itemSyncTasks[itemId] == nil else { return }

        itemSyncTasks[itemId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.itemSyncTasks[itemId] = nil }

            while self.pendingCheckItemIDs.contains(itemId), !Task.isCancelled {
                let desiredState = self.checkedStates[itemId] ?? false
                do {
                    try await supabase.updateShoppingListItemChecked(
                        itemId: itemId,
                        shoppingListId: self.plan.shoppingList.id,
                        checked: desiredState
                    )
                } catch {
                    return
                }

                guard self.checkedStates[itemId] == desiredState else { continue }
                self.pendingCheckItemIDs.remove(itemId)
                self.persistCheckCache()
            }
        }
    }

    private func syncPendingChanges(supabase: SupabaseService) async {
        for itemId in pendingCheckItemIDs {
            startItemSync(itemId: itemId, supabase: supabase)
        }

        for pending in pendingImports {
            guard let clientId = UUID(uuidString: pending.idempotencyKey) else { continue }
            await syncPendingImport(pending, clientId: clientId, supabase: supabase)
        }
    }

    private func syncPendingImport(
        _ pending: PendingImportedItem,
        clientId: UUID,
        supabase: SupabaseService
    ) async {
        guard pendingImports.contains(where: { $0.idempotencyKey == pending.idempotencyKey }),
              plan.shoppingList.id == pending.shoppingListId else { return }

        do {
            guard let persistedID = try await supabase.addImportedCandidateToShoppingList(
                shoppingListId: pending.shoppingListId,
                candidate: pending.candidate,
                quantity: pending.quantity,
                sortOrder: pending.sortOrder,
                idempotencyKey: clientId
            ) else { return }

            replaceImportedItem(
                localItemID: pending.localItemID,
                persistedID: persistedID,
                clientID: pending.idempotencyKey
            )
            pendingImports.removeAll { $0.idempotencyKey == pending.idempotencyKey }
            persistPlanCache()
            persistCheckCache()
        } catch {
            // Keep the locally visible item and retry this idempotent write on restore.
        }
    }

    private func replaceImportedItem(localItemID: String, persistedID: String, clientID: String) {
        if allShoppingItems.contains(where: { $0.id == persistedID }) {
            removeItem(localItemID, from: &plan)
            return
        }

        for sectionIndex in plan.shoppingList.sections.indices {
            guard let itemIndex = plan.shoppingList.sections[sectionIndex].items.firstIndex(where: { $0.id == localItemID }) else {
                continue
            }

            let item = plan.shoppingList.sections[sectionIndex].items[itemIndex]
            plan.shoppingList.sections[sectionIndex].items[itemIndex] = ShoppingListItem(
                id: persistedID,
                name: item.name,
                quantity: item.quantity,
                checked: checkedItemIDs.contains(localItemID),
                aisleLabel: item.aisleLabel,
                sectionType: item.sectionType,
                product: item.product,
                importedCandidate: item.importedCandidate,
                locationUncertaintyText: item.locationUncertaintyText,
                clientId: clientID
            )

            if let checked = checkedStates.removeValue(forKey: localItemID) {
                checkedStates[persistedID] = checked
                if pendingCheckItemIDs.remove(localItemID) != nil {
                    pendingCheckItemIDs.insert(persistedID)
                }
                if checkedItemIDs.remove(localItemID) != nil {
                    checkedItemIDs.insert(persistedID)
                }
            }
            return
        }
    }

    private func mergePendingImportedItems(from cachedPlan: WeekPlan?, into restored: inout WeekPlan) {
        guard let cachedPlan else { return }
        let restoredClientIDs = Set(
            restored.shoppingList.sections.flatMap(\.items).compactMap(\.clientId)
        )

        for pending in pendingImports where !restoredClientIDs.contains(pending.idempotencyKey) {
            guard let cachedItem = cachedPlan.shoppingList.sections
                .flatMap(\.items)
                .first(where: { $0.id == pending.localItemID }) else { continue }

            if let sectionIndex = restored.shoppingList.sections.firstIndex(where: { $0.label == "Added items" }) {
                restored.shoppingList.sections[sectionIndex].items.append(cachedItem)
            } else {
                restored.shoppingList.sections.append(
                    ShoppingListSection(label: "Added items", sortKey: 980, type: .unknown, items: [cachedItem])
                )
            }
        }
    }

    private func persistPlanCache() {
        guard let activeUserId, hasPlan, plan.source == .supabase else { return }
        localCache.savePlan(
            CachedPlanState(plan: plan, pendingImports: pendingImports),
            userId: activeUserId
        )
    }

    private func persistCheckCache() {
        guard let activeUserId, hasPlan, plan.source == .supabase else { return }
        localCache.saveChecks(
            CachedCheckState(
                shoppingListId: plan.shoppingList.id,
                states: checkedStates,
                pendingItemIDs: Array(pendingCheckItemIDs)
            ),
            userId: activeUserId
        )
    }

    private func setItemChecked(_ itemId: String, checked: Bool, in plan: inout WeekPlan) {
        for sectionIndex in plan.shoppingList.sections.indices {
            guard let itemIndex = plan.shoppingList.sections[sectionIndex].items.firstIndex(where: { $0.id == itemId }) else {
                continue
            }
            plan.shoppingList.sections[sectionIndex].items[itemIndex].checked = checked
            return
        }
    }

    private func applyCheckedStates(_ states: [String: Bool], to plan: inout WeekPlan) {
        for (itemId, checked) in states {
            setItemChecked(itemId, checked: checked, in: &plan)
        }
    }

    private func removeItem(_ itemId: String, from plan: inout WeekPlan) {
        for sectionIndex in plan.shoppingList.sections.indices {
            plan.shoppingList.sections[sectionIndex].items.removeAll { $0.id == itemId }
        }
        plan.shoppingList.sections.removeAll { $0.items.isEmpty }
    }

    private func allItemIDs(in plan: WeekPlan) -> [String] {
        plan.shoppingList.sections.flatMap(\.items).map(\.id)
    }

    private func captureProgressMilestones(analytics: AnalyticsService) {
        let percent = Int((shoppingProgress * 100).rounded(.down))

        for milestone in [25, 50, 75, 100] where percent >= milestone && !progressMilestones.contains(milestone) {
            progressMilestones.insert(milestone)
            analytics.capture(.shoppingListProgress, properties: [
                "store_id": .string(plan.storeId.rawValue),
                "shopping_list_id": .string(plan.shoppingList.id),
                "milestone_percent": .int(milestone),
                "checked_count": .int(checkedCount),
                "item_count": .int(allShoppingItems.count)
            ])
        }
    }

    private static func checkedIDs(from plan: WeekPlan) -> Set<String> {
        Set(plan.shoppingList.sections.flatMap(\.items).filter(\.checked).map(\.id))
    }

    private static func isoWeekStartString(from date: Date) -> String {
        let calendar = Calendar(identifier: .iso8601)
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: interval?.start ?? date)
    }

    private static func calendarWeekKey(fromISODate value: String) -> String? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        guard let date = formatter.date(from: value) else { return nil }

        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return "\(year)-W\(String(format: "%02d", week))"
    }
}

private struct PendingImportedItem: Codable, Hashable {
    let idempotencyKey: String
    let localItemID: String
    let shoppingListId: String
    let candidate: ProductCandidate
    let quantity: String
    let sortOrder: Int
}

private struct CachedPlanState: Codable {
    let plan: WeekPlan
    let pendingImports: [PendingImportedItem]
}

private struct CachedCheckState: Codable {
    let shoppingListId: String
    let states: [String: Bool]
    let pendingItemIDs: [String]
}

private final class ShoppingListLocalCache {
    private let fileManager: FileManager
    private let directoryURL: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        directoryURL = applicationSupport?.appendingPathComponent("ReasiShoppingCache", isDirectory: true)
        if let directoryURL {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    func loadPlan(userId: String) -> CachedPlanState? {
        load(CachedPlanState.self, from: fileURL(kind: "plan", userId: userId))
    }

    func savePlan(_ state: CachedPlanState, userId: String) {
        save(state, to: fileURL(kind: "plan", userId: userId))
    }

    func loadChecks(userId: String) -> CachedCheckState? {
        load(CachedCheckState.self, from: fileURL(kind: "checks", userId: userId))
    }

    func saveChecks(_ state: CachedCheckState, userId: String) {
        save(state, to: fileURL(kind: "checks", userId: userId))
    }

    func remove(userId: String) {
        for kind in ["plan", "checks"] {
            guard let url = fileURL(kind: kind, userId: userId) else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func load<Value: Decodable>(_ type: Value.Type, from url: URL?) -> Value? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, to url: URL?) {
        guard let url, let data = try? encoder.encode(value) else { return }
        do {
            try data.write(to: url, options: [.atomic])
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            // Supabase remains authoritative; a failed cache write is retried on the next mutation.
        }
    }

    private func fileURL(kind: String, userId: String) -> URL? {
        let safeUserId = userId.replacingOccurrences(of: "/", with: "_")
        return directoryURL?.appendingPathComponent("\(kind)-\(safeUserId).json", isDirectory: false)
    }
}
