import Foundation
import Observation
import SwiftUI

enum WeekPlanGenerationState: Equatable {
    case idle
    case generating
    case cancelling
    case succeeded
    case failed(String)
    case cancelled(String)

    var isGenerating: Bool {
        switch self {
        case .generating, .cancelling:
            true
        case .idle, .succeeded, .failed, .cancelled:
            false
        }
    }

    var isCancelling: Bool {
        if case .cancelling = self { return true }
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

struct ReasiPaywallRequest: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

enum ShoppingItemDeletionSource: String {
    case swipe
    case menu
}

enum WeekPlanGenerationStage: String, Equatable {
    case preparing
    case planningMeals
    case organizingStoreRoute
    case ready

    var title: String {
        switch self {
        case .preparing:
            "Reading your preferences"
        case .planningMeals:
            "Building seven dinners"
        case .organizingStoreRoute:
            "Organizing your store route"
        case .ready:
            "Finishing your week"
        }
    }

    var detail: String {
        switch self {
        case .preparing:
            "Checking household, food style, and store."
        case .planningMeals:
            "Choosing practical meals with enough variety."
        case .organizingStoreRoute:
            "Combining ingredients and ordering real store sections."
        case .ready:
            "Your new plan is ready. Loading the final details now."
        }
    }

    init(serverStage: GenerationRequestStage) {
        switch serverStage {
        case .preparing:
            self = .preparing
        case .planningMeals:
            self = .planningMeals
        case .organizingStoreRoute:
            self = .organizingStoreRoute
        case .ready, .cancelled, .failed, .expired:
            self = .ready
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
    var isSwitchingStore = false
    var switchingStoreName: String?
    var storeSwitchMessage: String?
    var failedStoreSwitch: StoreSummary?
    var paywallRequest: ReasiPaywallRequest?
    var recentPlans: [RecentPlanSummary] = []
    var isLoadingRecentPlans = false
    var isFinishingShopping = false
    var shoppingCompletionError: String?
    var lastShoppingTrip: ShoppingTripSummary?

    @ObservationIgnored private let localCache = ShoppingListLocalCache()
    @ObservationIgnored private let generationCache = GenerationRequestLocalCache()
    @ObservationIgnored private var progressMilestones: Set<Int> = []
    @ObservationIgnored private var activeUserId: String?
    @ObservationIgnored private var checkedStates: [String: Bool] = [:]
    @ObservationIgnored private var pendingCheckItemIDs: Set<String> = []
    @ObservationIgnored private var pendingImports: [PendingImportedItem] = []
    @ObservationIgnored private var pendingDeletions: Set<PendingShoppingListDeletion> = []
    @ObservationIgnored private var addedImportKeys: Set<String> = []
    @ObservationIgnored private var itemSyncTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var deleteSyncTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var generationClockTask: Task<Void, Never>?
    @ObservationIgnored private var generationRunID: UUID?
    @ObservationIgnored private var pendingGeneration: PendingGenerationRequest?
    @ObservationIgnored private var storeSwitchTask: Task<Void, Never>?
    @ObservationIgnored private var mealImageRefreshTask: Task<Void, Never>?

    init(plan: WeekPlan? = nil) {
        let initialPlan = plan ?? FixtureWeekPlan.current
        self.plan = initialPlan
        hasPlan = plan != nil
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

    var basketPriceSummary: BasketPriceSummary {
        BasketPriceSummary(items: allShoppingItems)
    }

    var isShoppingCompleted: Bool {
        hasPlan && plan.shoppingList.status == .completed
    }

    var hasPendingGeneration: Bool {
        pendingGeneration != nil
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

    func requestStoreSwitch(
        to store: StoreSummary,
        appState: AppState,
        supabase: SupabaseService,
        analytics: AnalyticsService,
        completion: (@MainActor (Bool, StoreSummary) -> Void)? = nil
    ) {
        failedStoreSwitch = nil
        guard storeSwitchTask == nil else {
            if let displayedStore = FixtureStores.store(id: plan.shoppingList.storeId) {
                appState.selectStore(displayedStore)
                completion?(false, displayedStore)
            }
            return
        }

        storeSwitchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.storeSwitchTask = nil
                self.isSwitchingStore = false
                self.switchingStoreName = nil
            }
            let outcome = await self.performStoreSwitch(
                to: store,
                appState: appState,
                supabase: supabase,
                analytics: analytics
            )
            completion?(outcome.succeeded, outcome.confirmedStore)
        }
    }

    private func performStoreSwitch(
        to store: StoreSummary,
        appState: AppState,
        supabase: SupabaseService,
        analytics: AnalyticsService
    ) async -> (succeeded: Bool, confirmedStore: StoreSummary) {
        storeSwitchMessage = nil
        let previousStore = FixtureStores.store(id: plan.shoppingList.storeId)
            ?? FixtureStores.store(id: plan.storeId)
            ?? appState.selectedStore

        guard hasPlan else {
            syncFixturePlan(to: store)
            try? await supabase.saveSelectedStore(store.id)
            appState.selectStore(store)
            return (true, store)
        }
        guard plan.storeId != store.id || plan.shoppingList.storeId != store.id else {
            try? await supabase.saveSelectedStore(store.id)
            appState.selectStore(store)
            return (true, store)
        }

        if plan.source == .fixture {
            withAnimation(ReasiMotion.fast) {
                syncFixturePlan(to: store)
                appState.selectStore(store)
            }
            try? await supabase.saveSelectedStore(store.id)
            return (true, store)
        }

        guard supabase.isSignedIn else {
            appState.selectStore(previousStore)
            failedStoreSwitch = store
            storeSwitchMessage = "Sign in again to update this list for \(store.shortName)."
            return (false, previousStore)
        }

        isSwitchingStore = true
        switchingStoreName = store.name
        let existingPlan = plan

        do {
            var refreshed = try await supabase.regroupShoppingList(
                shoppingListId: existingPlan.shoppingList.id,
                from: existingPlan.shoppingList.storeId,
                to: store.id
            )
            guard refreshed.storeId == store.id, refreshed.shoppingList.storeId == store.id else {
                throw ReasiServiceError.invalidResponse
            }

            mergePendingImportedItems(from: existingPlan, into: &refreshed)
            for deletion in pendingDeletions where deletion.shoppingListId == refreshed.shoppingList.id {
                removeItem(deletion.itemId, from: &refreshed)
            }
            for itemId in pendingCheckItemIDs {
                setItemChecked(itemId, checked: checkedStates[itemId] ?? false, in: &refreshed)
            }

            withAnimation(ReasiMotion.base) {
                plan = refreshed
                appState.selectStore(store)
                checkedItemIDs = Self.checkedIDs(from: refreshed)
                progressMilestones = []
            }
            persistPlanCache()
            persistCheckCache()
            failedStoreSwitch = nil
            ReasiHaptics.success()
            return (true, store)
        } catch {
            appState.selectStore(previousStore)
            failedStoreSwitch = store
            let reason = supabase.userFacingMessage(
                for: error,
                fallback: "Item locations could not update yet. Try again when you are online."
            )
            storeSwitchMessage = "Still showing \(previousStore.shortName). \(reason)"
            analytics.capture(.storeSelected, properties: [
                "store_id": .string(store.id.rawValue),
                "store_name": .string(store.name),
                "regroup_succeeded": .bool(false)
            ])
            ReasiHaptics.warning()
            return (false, previousStore)
        }
    }

    func activateUser(_ userId: String?, selectedStore: StoreSummary) {
        guard activeUserId != userId else { return }
        cancelOutstandingWork()
        activeUserId = userId
        recentPlans = []
        lastShoppingTrip = nil
        shoppingCompletionError = nil
        isFinishingShopping = false
        pendingDeletions = userId.map { Set(localCache.loadDeletions(userId: $0)) } ?? []

        guard let userId,
              let cached = localCache.loadPlan(userId: userId),
              cached.plan.source == .supabase else {
            clearVisiblePlan(selectedStore: selectedStore)
            restorePendingGenerationCache(for: userId)
            return
        }

        plan = cached.plan
        hasPlan = true
        pendingImports = cached.pendingImports
        if pendingDeletions.isEmpty, !cached.pendingDeletionItemIDs.isEmpty {
            pendingDeletions = Set(cached.pendingDeletionItemIDs.map {
                PendingShoppingListDeletion(shoppingListId: cached.plan.shoppingList.id, itemId: $0)
            })
            persistDeletionCache()
        }
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
        restorePendingGenerationCache(for: userId)
    }

    func restoreLatestPlan(supabase: SupabaseService, selectedStore: StoreSummary) async {
        guard supabase.isSignedIn, !isRestoringPlan else { return }

        isRestoringPlan = true
        planRestoreMessage = nil
        defer { isRestoringPlan = false }

        do {
            let cachedPlan = activeUserId.flatMap { localCache.loadPlan(userId: $0) }
            let remotePlan: WeekPlan?
            if let cachedPlan, cachedPlan.plan.source == .supabase {
                if let exactPlan = try await supabase.fetchWeekPlan(id: cachedPlan.plan.id) {
                    remotePlan = exactPlan
                } else {
                    remotePlan = try await supabase.fetchLatestWeekPlan()
                }
            } else {
                remotePlan = try await supabase.fetchLatestWeekPlan()
            }

            guard var restored = remotePlan else {
                if let activeUserId {
                    localCache.remove(userId: activeUserId)
                }
                clearVisiblePlan(selectedStore: selectedStore)
                return
            }

            if cachedPlan?.plan.shoppingList.id == restored.shoppingList.id {
                pendingImports = cachedPlan?.pendingImports ?? []
                addedImportKeys = Set(pendingImports.map(\.idempotencyKey))
                mergePendingImportedItems(from: cachedPlan?.plan, into: &restored)
            } else {
                pendingImports = []
                addedImportKeys = []
            }
            for deletion in pendingDeletions where deletion.shoppingListId == restored.shoppingList.id {
                removeItem(deletion.itemId, from: &restored)
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
        isSwitchingStore = false
        switchingStoreName = nil
        storeSwitchMessage = nil
        failedStoreSwitch = nil
        pendingGeneration = nil
        paywallRequest = nil
        isFinishingShopping = false
        shoppingCompletionError = nil
        lastShoppingTrip = nil
    }

    func restorePendingGeneration(
        supabase: SupabaseService,
        analytics: AnalyticsService,
        appState: AppState,
        network: NetworkMonitor? = nil
    ) async {
        guard supabase.isSignedIn,
              generationTask == nil,
              let expectedUserId = activeUserId else { return }

        if pendingGeneration == nil, let activeUserId {
            pendingGeneration = generationCache.load(userId: activeUserId)
        }

        if pendingGeneration == nil {
            do {
                if let remote = try await supabase.fetchLatestUnfinishedGeneration() {
                    guard activeUserId == expectedUserId,
                          supabase.currentUserId == expectedUserId,
                          pendingGeneration == nil,
                          generationTask == nil else { return }
                    pendingGeneration = PendingGenerationRequest(
                        idempotencyKey: remote.requestId,
                        requestId: remote.requestId,
                        storeId: remote.storeId ?? appState.selectedStore.id,
                        weekStart: remote.weekStart ?? Self.isoWeekStartString(from: Date()),
                        startedAt: remote.createdAt.flatMap(Self.dateFromISO8601) ?? Date(),
                        stage: remote.stage,
                        cancellationRequested: remote.status == .cancelRequested,
                        opensWhenReady: !hasPlan
                    )
                    persistPendingGeneration()
                }
            } catch {
                return
            }
        }

        guard pendingGeneration != nil else { return }
        presentPendingGeneration()
        launchGenerationWorkflow(
            supabase: supabase,
            analytics: analytics,
            appState: appState,
            network: network
        )
        await Task.yield()
    }

    func startWeekPlanGeneration(
        store: StoreSummary,
        supabase: SupabaseService,
        analytics: AnalyticsService,
        appState: AppState,
        network: NetworkMonitor? = nil
    ) {
        startPlanGeneration(
            brief: nil,
            store: store,
            supabase: supabase,
            analytics: analytics,
            appState: appState,
            network: network
        )
    }

    func startPlanGeneration(
        brief: PlanBrief?,
        store: StoreSummary,
        supabase: SupabaseService,
        analytics: AnalyticsService,
        appState: AppState,
        network: NetworkMonitor? = nil
    ) {
        guard generationTask == nil else { return }

        if pendingGeneration == nil {
            let weekStart = Self.isoWeekStartString(from: Date())
            pendingGeneration = PendingGenerationRequest(
                idempotencyKey: "ios-\(UUID().uuidString)",
                requestId: nil,
                storeId: store.id,
                weekStart: weekStart,
                startedAt: Date(),
                stage: .preparing,
                cancellationRequested: false,
                opensWhenReady: !hasPlan,
                planBrief: brief
            )
            persistPendingGeneration()
            analytics.capture(.planGenerationStarted, properties: [
                "store_id": .string(store.id.rawValue),
                "week_start": .string(weekStart),
                "source": .string(supabase.status.state == .configured ? "supabase" : "fixture"),
                "plan_kind": .string((brief?.kind ?? .week).rawValue),
                "entry_method": .string((brief?.entryMethod ?? .describe).rawValue)
            ])
            ReasiHaptics.light()
        }

        presentPendingGeneration()
        launchGenerationWorkflow(
            supabase: supabase,
            analytics: analytics,
            appState: appState,
            network: network
        )
    }

    func cancelGeneration(
        supabase: SupabaseService,
        analytics: AnalyticsService,
        appState: AppState
    ) {
        guard var pending = pendingGeneration else { return }
        pending.cancellationRequested = true
        pendingGeneration = pending
        persistPendingGeneration()
        generationState = .cancelling
        ReasiHaptics.selection()

        if generationTask == nil {
            launchGenerationWorkflow(
                supabase: supabase,
                analytics: analytics,
                appState: appState,
                network: nil
            )
        }
    }

    func pauseGenerationPolling() {
        generationTask?.cancel()
        generationClockTask?.cancel()
        generationTask = nil
        generationClockTask = nil
        generationRunID = nil
    }

    private func launchGenerationWorkflow(
        supabase: SupabaseService,
        analytics: AnalyticsService,
        appState: AppState,
        network: NetworkMonitor?
    ) {
        guard generationTask == nil, pendingGeneration != nil else { return }

        let runID = UUID()
        generationRunID = runID
        startGenerationClock(runID: runID)
        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.generationRunID == runID {
                    self.generationClockTask?.cancel()
                    self.generationClockTask = nil
                    self.generationTask = nil
                    self.generationRunID = nil
                }
            }
            await self.runGenerationWorkflow(
                runID: runID,
                supabase: supabase,
                analytics: analytics,
                appState: appState,
                network: network
            )
        }
    }

    private func runGenerationWorkflow(
        runID: UUID,
        supabase: SupabaseService,
        analytics: AnalyticsService,
        appState: AppState,
        network: NetworkMonitor?
    ) async {
        guard var pending = pendingGeneration else { return }

        do {
            if network?.isConnected == false {
                throw ReasiServiceError.offline
            }

            var request: WeekPlanGenerationRequest
            if let requestId = pending.requestId {
                request = try await supabase.generationStatus(requestId: requestId)
            } else {
                let result = try await supabase.startWeekPlanGeneration(
                    input: GenerateWeekPlanInput(
                        storeId: pending.storeId,
                        weekStart: pending.weekStart,
                        idempotencyKey: pending.idempotencyKey,
                        planBrief: pending.planBrief
                    )
                )
                switch result {
                case .fixture(let fixture):
                    completeGeneration(
                        fixture,
                        opensWhenReady: pending.opensWhenReady,
                        analytics: analytics,
                        appState: appState
                    )
                    return
                case .request(let started):
                    request = started
                    pending.requestId = started.requestId
                    pending.stage = started.stage
                    pendingGeneration = pending
                    persistPendingGeneration()
                }
            }

            while !Task.isCancelled, generationRunID == runID {
                if pendingGeneration?.cancellationRequested == true,
                   request.status == .queued || request.status == .inProgress {
                    generationState = .cancelling
                    request = try await supabase.cancelWeekPlanGeneration(requestId: request.requestId)
                }

                updatePendingGeneration(from: request)
                switch request.status {
                case .completed:
                    guard let mealPlanId = request.mealPlanId,
                          let generated = try await supabase.fetchWeekPlan(id: mealPlanId) else {
                        throw ReasiServiceError.invalidResponse
                    }
                    completeGeneration(
                        generated,
                        opensWhenReady: pendingGeneration?.opensWhenReady ?? false,
                        analytics: analytics,
                        appState: appState
                    )
                    refreshMealImagesIfNeeded(supabase: supabase)
                    return

                case .failed, .expired:
                    let fallback = request.status == .expired
                        ? "Planning took too long this time. Your existing week is safe; please try again."
                        : "We couldn't finish your new week. Your existing week is safe; please try again."
                    finishGenerationFailure(request.message ?? fallback)
                    return

                case .cancelRequested where request.stage == .cancelled:
                    finishGenerationCancellation()
                    return

                case .queued, .inProgress, .cancelRequested:
                    try await Task.sleep(for: .seconds(2))
                    request = try await supabase.generationStatus(requestId: request.requestId)
                }
            }
        } catch is CancellationError {
            // Signing out or switching accounts stops local polling. The server job and
            // user-scoped cache remain available for the next authenticated launch.
        } catch {
            let message = supabase.userFacingMessage(
                for: error,
                fallback: "We couldn't check your plan just now. It may still be running; try again when you're connected."
            )
            if let serviceError = error as? ReasiServiceError,
               case .reasiProRequired = serviceError {
                clearPendingGeneration()
                generationState = .idle
                paywallRequest = ReasiPaywallRequest(message: message)
                ReasiHaptics.selection()
                return
            }
            generationState = .failed(message)
            ReasiHaptics.warning()
        }
    }

    func dismissPaywall() {
        paywallRequest = nil
    }

    #if DEBUG
    func presentDebugPaywall() {
        paywallRequest = ReasiPaywallRequest(
            message: "Your first complete week is included. Reasi Pro unlocks every new week after that."
        )
    }
    #endif

    private func completeGeneration(
        _ generated: WeekPlan,
        opensWhenReady: Bool,
        analytics: AnalyticsService,
        appState: AppState
    ) {
        let completedBrief = pendingGeneration?.planBrief
        var resolvedPlan = generated
        if let completedBrief {
            resolvedPlan.kind = completedBrief.kind
            resolvedPlan.entryMethod = completedBrief.entryMethod
            resolvedPlan.occasionAt = completedBrief.occasionAt
        }
        generationStage = .ready
        withAnimation(ReasiMotion.slow) {
            plan = resolvedPlan
            hasPlan = true
            checkedItemIDs = Self.checkedIDs(from: resolvedPlan)
            checkedStates = Dictionary(uniqueKeysWithValues: allItemIDs(in: resolvedPlan).map {
                ($0, checkedItemIDs.contains($0))
            })
            pendingCheckItemIDs = []
            pendingImports = []
            addedImportKeys = []
            progressMilestones = []
            generationState = .succeeded
            lastShoppingTrip = nil
            shoppingCompletionError = nil
        }
        clearPendingGeneration()
        if completedBrief != nil {
            appState.planBuilder.discard()
        }
        persistPlanCache()
        persistCheckCache()
        analytics.capture(.shoppingListCreated, properties: [
            "store_id": .string(resolvedPlan.storeId.rawValue),
            "source": .string(resolvedPlan.source.rawValue),
            "item_count": .int(allShoppingItems.count),
            "section_count": .int(generated.shoppingList.sections.count),
            "plan_kind": .string(resolvedPlan.kind.rawValue),
            "entry_method": .string((resolvedPlan.entryMethod ?? .describe).rawValue)
        ])
        analytics.flush()
        ReasiHaptics.success()
        if opensWhenReady {
            appState.showPlan()
        }
    }

    private func finishGenerationFailure(_ message: String) {
        clearPendingGeneration()
        generationState = .failed(message.reasiUserFacingCopy)
        ReasiHaptics.warning()
    }

    private func finishGenerationCancellation() {
        clearPendingGeneration()
        generationState = .cancelled(
            "Planning was cancelled. Your previous week was not changed."
        )
        ReasiHaptics.selection()
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
        guard hasPlan, plan.shoppingList.status == .active else { return }
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

    func deleteItem(
        _ item: ShoppingListItem,
        source: ShoppingItemDeletionSource = .swipe,
        supabase: SupabaseService,
        analytics: AnalyticsService
    ) {
        guard hasPlan,
              plan.shoppingList.status == .active,
              allShoppingItems.contains(where: { $0.id == item.id }) else { return }
        let shoppingListId = plan.shoppingList.id

        itemSyncTasks[item.id]?.cancel()
        itemSyncTasks[item.id] = nil
        checkedItemIDs.remove(item.id)
        checkedStates.removeValue(forKey: item.id)
        pendingCheckItemIDs.remove(item.id)

        if item.id.hasPrefix("local-import-") {
            if let pending = pendingImports.first(where: { $0.localItemID == item.id }) {
                pendingImports.removeAll { $0.localItemID == item.id }
                addedImportKeys.remove(pending.idempotencyKey)
            }
        } else {
            pendingDeletions.insert(PendingShoppingListDeletion(
                shoppingListId: shoppingListId,
                itemId: item.id
            ))
        }

        withAnimation(ReasiMotion.tactileSpring) {
            removeItem(item.id, from: &plan)
        }
        persistPlanCache()
        persistCheckCache()
        persistDeletionCache()
        if !item.id.hasPrefix("local-import-") {
            startDeleteSync(
                deletion: PendingShoppingListDeletion(shoppingListId: shoppingListId, itemId: item.id),
                supabase: supabase
            )
        }

        ReasiHaptics.warning()
        analytics.capture(.shoppingItemDeleted, properties: [
            "store_id": .string(plan.storeId.rawValue),
            "shopping_list_id": .string(shoppingListId),
            "item_id": .string(item.id),
            "source": .string(source.rawValue)
        ])
    }

    func applyAssistantMutations(_ mutations: [AssistantListMutation]) {
        guard hasPlan, plan.shoppingList.status == .active, !mutations.isEmpty else { return }

        for mutation in mutations {
            switch mutation.operation {
            case "add":
                guard !allShoppingItems.contains(where: { $0.id == mutation.itemId }) else { continue }
                let sectionType = mutation.sectionType ?? .unknown
                let item = ShoppingListItem(
                    id: mutation.itemId,
                    name: mutation.name,
                    quantity: mutation.quantity ?? "1",
                    checked: mutation.checked ?? false,
                    aisleLabel: mutation.aisleLabel,
                    sectionType: sectionType,
                    product: nil,
                    locationUncertaintyText: sectionType == .unknown ? "Location not certain" : nil
                )
                insertItem(
                    item,
                    sectionLabel: mutation.sectionLabel ?? "Location not certain",
                    sectionSortKey: mutation.sectionSortKey ?? 999,
                    sectionType: sectionType,
                    into: &plan
                )
                checkedStates[item.id] = item.checked
                if item.checked { checkedItemIDs.insert(item.id) }

            case "delete":
                removeItem(mutation.itemId, from: &plan)
                checkedItemIDs.remove(mutation.itemId)
                checkedStates.removeValue(forKey: mutation.itemId)
                pendingCheckItemIDs.remove(mutation.itemId)

            case "update":
                updateAssistantItem(mutation)

            default:
                continue
            }
        }

        persistPlanCache()
        persistCheckCache()
    }

    func addImportedCandidate(
        _ candidate: ProductCandidate,
        quantity: String = "1",
        idempotencyKey: String,
        analyticsMethod: String = "review",
        supabase: SupabaseService,
        analytics: AnalyticsService
    ) async -> Bool {
        guard hasPlan,
              plan.shoppingList.status == .active,
              let clientId = UUID(uuidString: idempotencyKey) else { return false }
        if addedImportKeys.contains(idempotencyKey) { return true }
        if allShoppingItems.contains(where: { item in
            if let sku = candidate.sku, item.product?.sku == sku { return true }
            if let barcode = candidate.barcode, item.product?.barcode == barcode { return true }
            return false
        }) {
            return true
        }

        let sortOrder = allShoppingItems.count + 1
        let localItemID = "local-import-\(idempotencyKey)"
        let sectionLabel = candidate.sectionLabel ?? "Location not certain"
        let sectionSortKey = candidate.sectionSortKey ?? 999
        let sectionType = candidate.sectionType ?? .unknown

        let item = ShoppingListItem(
            id: localItemID,
            name: candidate.displayName,
            quantity: quantity,
            checked: false,
            aisleLabel: candidate.aisleLabel ?? "Location not certain",
            sectionType: sectionType,
            product: ProductSnapshot(candidate: candidate),
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
            insertItem(
                item,
                sectionLabel: sectionLabel,
                sectionSortKey: sectionSortKey,
                sectionType: sectionType,
                into: &plan
            )
        }
        persistPlanCache()
        persistCheckCache()

        ReasiHaptics.success()
        analytics.capture(.productCandidateAdded, properties: [
            "method": .string(analyticsMethod),
            "store_id": .string(plan.storeId.rawValue),
            "shopping_list_id": .string(plan.shoppingList.id),
            "confidence": .string(candidate.confidence.rawValue),
            "has_price": .bool(candidate.priceAud != nil),
            "has_source": .bool(!candidate.sourceName.isEmpty)
        ])

        await syncPendingImport(pending, clientId: clientId, supabase: supabase)
        return true
    }

    func selectProduct(
        _ candidate: ProductCandidate,
        for item: ShoppingListItem,
        actualPriceAud: Double?,
        supabase: SupabaseService,
        analytics: AnalyticsService
    ) async throws {
        guard hasPlan,
              plan.shoppingList.status == .active,
              !item.id.hasPrefix("local-import-"),
              let context = sectionContext(for: item.id, in: plan) else {
            throw ReasiServiceError.invalidResponse
        }

        let resolvedLabel = candidate.sectionLabel ?? context.label
        let resolvedSortKey = candidate.sectionSortKey ?? context.sortKey
        let resolvedType = candidate.sectionType ?? context.type
        let resolvedAisle = candidate.aisleLabel ?? item.aisleLabel ?? "Location not certain"

        try await supabase.selectProduct(
            candidate,
            for: item,
            shoppingListId: plan.shoppingList.id,
            sectionLabel: context.label,
            sectionSortKey: context.sortKey,
            sectionType: context.type,
            actualPriceAud: actualPriceAud
        )

        let selectedItem = ShoppingListItem(
            id: item.id,
            name: item.name,
            quantity: item.quantity,
            checked: true,
            aisleLabel: resolvedAisle,
            sectionType: resolvedType,
            product: ProductSnapshot(candidate: candidate, actualPriceAud: actualPriceAud),
            importedCandidate: candidate,
            locationUncertaintyText: resolvedType == .unknown ? candidate.uncertaintyText : nil,
            clientId: item.clientId
        )

        withAnimation(ReasiMotion.tactileSpring) {
            removeItem(item.id, from: &plan)
            insertItem(
                selectedItem,
                sectionLabel: resolvedLabel,
                sectionSortKey: resolvedSortKey,
                sectionType: resolvedType,
                into: &plan
            )
            checkedItemIDs.insert(item.id)
        }
        checkedStates[item.id] = true
        pendingCheckItemIDs.remove(item.id)
        persistPlanCache()
        persistCheckCache()
        ReasiHaptics.success()
        analytics.capture(.productCandidateAdded, properties: [
            "method": .string(candidate.barcode == nil ? "item_search" : "barcode"),
            "store_id": .string(plan.storeId.rawValue),
            "shopping_list_id": .string(plan.shoppingList.id),
            "item_id": .string(item.id),
            "confidence": .string(candidate.confidence.rawValue),
            "has_sku": .bool(candidate.sku != nil),
            "has_barcode": .bool(candidate.barcode != nil),
            "has_price": .bool(candidate.priceAud != nil || actualPriceAud != nil)
        ])
        captureProgressMilestones(analytics: analytics)
    }

    func markWeekPlanViewed(analytics: AnalyticsService) {
        guard hasPlan else { return }
        var properties: [String: AnalyticsProperty] = [
            "store_id": .string(plan.storeId.rawValue),
            "source": .string(plan.source.rawValue),
            "meal_count": .int(plan.meals.count),
            "plan_kind": .string(plan.kind.rawValue)
        ]
        if let entryMethod = plan.entryMethod {
            properties["entry_method"] = .string(entryMethod.rawValue)
        }
        analytics.capture(.weekPlanViewed, properties: properties)
    }

    func markShoppingListViewed(analytics: AnalyticsService) {
        guard hasPlan else { return }
        analytics.capture(.shoppingListViewed, properties: shoppingListProperties)
    }

    func refreshRecentPlans(supabase: SupabaseService?) async {
        guard let supabase, supabase.isSignedIn else { return }
        isLoadingRecentPlans = true
        defer { isLoadingRecentPlans = false }
        do {
            recentPlans = try await supabase.fetchRecentPlans()
        } catch {
            // The current plan remains usable when history cannot refresh.
        }
    }

    func refreshMealImagesIfNeeded(supabase: SupabaseService) {
        guard hasPlan,
              plan.source == .supabase,
              plan.meals.contains(where: { $0.imageUrl == nil }),
              supabase.isSignedIn else { return }

        let planID = plan.id
        mealImageRefreshTask?.cancel()
        mealImageRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.mealImageRefreshTask = nil }

            for delay in [0, 2, 4, 8] {
                if delay > 0 {
                    do {
                        try await Task.sleep(for: .seconds(delay))
                    } catch {
                        return
                    }
                }

                guard !Task.isCancelled,
                      self.hasPlan,
                      self.plan.id == planID,
                      self.plan.meals.contains(where: { $0.imageUrl == nil }) else { return }

                do {
                    guard let refreshed = try await supabase.fetchWeekPlan(id: planID),
                          refreshed.id == planID else { continue }
                    let refreshedByID = Dictionary(uniqueKeysWithValues: refreshed.meals.map { ($0.id, $0) })
                    let mergedMeals = self.plan.meals.map { meal in
                        guard let update = refreshedByID[meal.id] else { return meal }
                        return meal.withImageMetadata(from: update)
                    }
                    guard mergedMeals != self.plan.meals else { continue }
                    withAnimation(ReasiMotion.base) {
                        self.plan = self.plan.withMeals(mergedMeals)
                    }
                    self.persistPlanCache()
                } catch {
                    // Images are optional; the existing plan remains fully usable while retrying.
                }
            }
        }
    }

    func selectRecentPlan(id: String, supabase: SupabaseService) async {
        guard id != plan.id else { return }
        do {
            await syncPendingChanges(supabase: supabase)
            let outstandingSyncTasks = Array(itemSyncTasks.values) + Array(deleteSyncTasks.values)
            for task in outstandingSyncTasks {
                await task.value
            }
            guard pendingImports.isEmpty, pendingCheckItemIDs.isEmpty, pendingDeletions.isEmpty else {
                planRestoreMessage = "Your latest list changes are still syncing. Stay online and try again in a moment."
                return
            }

            guard var selected = try await supabase.fetchWeekPlan(id: id) else { return }
            for deletion in pendingDeletions where deletion.shoppingListId == selected.shoppingList.id {
                removeItem(deletion.itemId, from: &selected)
            }
            var selectedCheckedIDs = Self.checkedIDs(from: selected)
            var selectedCheckedStates = Dictionary(uniqueKeysWithValues: allItemIDs(in: selected).map {
                ($0, selectedCheckedIDs.contains($0))
            })
            var selectedPendingIDs: Set<String> = []
            if let activeUserId,
               let localChecks = localCache.loadChecks(userId: activeUserId),
               localChecks.shoppingListId == selected.shoppingList.id {
                selectedPendingIDs = Set(localChecks.pendingItemIDs)
                    .intersection(Set(allItemIDs(in: selected)))
                for itemID in selectedPendingIDs {
                    let isChecked = localChecks.states[itemID] ?? false
                    selectedCheckedStates[itemID] = isChecked
                    if isChecked {
                        selectedCheckedIDs.insert(itemID)
                    } else {
                        selectedCheckedIDs.remove(itemID)
                    }
                }
                applyCheckedStates(selectedCheckedStates, to: &selected)
            }
            withAnimation(ReasiMotion.base) {
                plan = selected
                hasPlan = true
                checkedItemIDs = selectedCheckedIDs
            }
            lastShoppingTrip = nil
            shoppingCompletionError = nil
            checkedStates = selectedCheckedStates
            pendingCheckItemIDs = selectedPendingIDs
            pendingImports = []
            addedImportKeys = []
            progressMilestones = []
            persistPlanCache()
            persistCheckCache()
            ReasiHaptics.selection()
        } catch {
            planRestoreMessage = "That saved plan could not be opened yet. Please try again."
        }
    }

    private var shoppingListProperties: [String: AnalyticsProperty] {
        [
            "store_id": .string(plan.storeId.rawValue),
            "source": .string(plan.source.rawValue),
            "shopping_list_id": .string(plan.shoppingList.id),
            "item_count": .int(allShoppingItems.count),
            "section_count": .int(plan.shoppingList.sections.count),
            "plan_kind": .string(plan.kind.rawValue)
        ]
    }

    private func restorePendingGenerationCache(for userId: String?) {
        guard let userId, let cached = generationCache.load(userId: userId) else {
            pendingGeneration = nil
            return
        }
        pendingGeneration = cached
        presentPendingGeneration()
    }

    private func presentPendingGeneration() {
        guard let pending = pendingGeneration else { return }
        generationState = pending.cancellationRequested ? .cancelling : .generating
        generationStage = WeekPlanGenerationStage(serverStage: pending.stage)
        generationElapsedSeconds = max(0, Int(Date().timeIntervalSince(pending.startedAt)))
    }

    private func updatePendingGeneration(from request: WeekPlanGenerationRequest) {
        guard let previous = pendingGeneration else { return }
        var pending = previous
        pending.requestId = request.requestId
        pending.stage = request.stage
        if request.status == .cancelRequested {
            pending.cancellationRequested = true
        }
        pendingGeneration = pending
        generationStage = WeekPlanGenerationStage(serverStage: request.stage)
        generationState = pending.cancellationRequested ? .cancelling : .generating
        if pending != previous {
            persistPendingGeneration()
        }
    }

    private func persistPendingGeneration() {
        guard let activeUserId, let pendingGeneration else { return }
        generationCache.save(pendingGeneration, userId: activeUserId)
    }

    private func clearPendingGeneration() {
        if let activeUserId {
            generationCache.remove(userId: activeUserId)
        }
        pendingGeneration = nil
        generationClockTask?.cancel()
        generationClockTask = nil
    }

    private func startGenerationClock(runID: UUID) {
        generationClockTask?.cancel()
        generationClockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self,
                      self.generationRunID == runID,
                      let pending = self.pendingGeneration,
                      self.generationState.isGenerating else { return }
                self.generationElapsedSeconds = max(
                    0,
                    Int(Date().timeIntervalSince(pending.startedAt))
                )
            }
        }
    }

    private func cancelOutstandingWork() {
        generationTask?.cancel()
        generationClockTask?.cancel()
        storeSwitchTask?.cancel()
        itemSyncTasks.values.forEach { $0.cancel() }
        deleteSyncTasks.values.forEach { $0.cancel() }
        mealImageRefreshTask?.cancel()
        generationTask = nil
        generationClockTask = nil
        storeSwitchTask = nil
        itemSyncTasks = [:]
        deleteSyncTasks = [:]
        mealImageRefreshTask = nil
        generationRunID = nil
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
        for deletion in pendingDeletions {
            startDeleteSync(deletion: deletion, supabase: supabase)
        }

        for itemId in pendingCheckItemIDs {
            startItemSync(itemId: itemId, supabase: supabase)
        }

        for pending in pendingImports {
            guard let clientId = UUID(uuidString: pending.idempotencyKey) else { continue }
            await syncPendingImport(pending, clientId: clientId, supabase: supabase)
        }
    }

    func flushPendingShoppingChanges(supabase: SupabaseService) async {
        guard supabase.isSignedIn else { return }
        await syncPendingChanges(supabase: supabase)
        let outstandingTasks = Array(itemSyncTasks.values) + Array(deleteSyncTasks.values)
        for task in outstandingTasks {
            await task.value
        }
    }

    func finishShopping(
        supabase: SupabaseService,
        analytics: AnalyticsService
    ) async {
        guard hasPlan,
              plan.shoppingList.status == .active,
              !isFinishingShopping else { return }

        isFinishingShopping = true
        shoppingCompletionError = nil
        let summaryBeforeFinish = basketPriceSummary
        analytics.capture(.shoppingFinishStarted, properties: [
            "store_id": .string(plan.shoppingList.storeId.rawValue),
            "shopping_list_id": .string(plan.shoppingList.id),
            "checked_items": .int(summaryBeforeFinish.checkedItemCount),
            "item_count": .int(summaryBeforeFinish.totalItemCount),
            "priced_items": .int(summaryBeforeFinish.pricedItemCount)
        ])
        defer { isFinishingShopping = false }

        do {
            await flushPendingShoppingChanges(supabase: supabase)
            guard pendingImports.isEmpty,
                  pendingCheckItemIDs.isEmpty,
                  pendingDeletions.isEmpty else {
                throw ReasiServiceError.requestFailed(
                    "A few list changes are still syncing. Stay online and try Finish shopping again in a moment."
                )
            }

            let trip = try await supabase.finishShopping(plan.shoppingList)
            withAnimation(ReasiMotion.slow) {
                plan.shoppingList.status = .completed
                plan.shoppingList.completedAt = trip.completedAt
                lastShoppingTrip = trip
            }
            persistPlanCache()
            analytics.capture(.shoppingFinished, properties: [
                "store_id": .string(trip.storeId.rawValue),
                "shopping_list_id": .string(trip.shoppingListId),
                "item_count": .int(trip.totalItems),
                "checked_items": .int(trip.checkedItems),
                "priced_items": .int(trip.pricedItems),
                "priced_checked_items": .int(trip.pricedCheckedItems),
                "known_basket_total_aud": .double(trip.knownBasketTotalAud),
                "known_planned_total_aud": .double(trip.knownPlannedTotalAud),
                "already_completed": .bool(trip.alreadyCompleted)
            ])
            analytics.flush()
            ReasiHaptics.success()
        } catch {
            let message = supabase.userFacingMessage(
                for: error,
                fallback: "Your list is still open. We couldn't save this shop yet; please try again."
            )
            shoppingCompletionError = message
            analytics.capture(.shoppingFinishFailed, properties: [
                "store_id": .string(plan.shoppingList.storeId.rawValue),
                "shopping_list_id": .string(plan.shoppingList.id)
            ])
            ReasiHaptics.warning()
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

            guard pendingImports.contains(where: { $0.idempotencyKey == pending.idempotencyKey }) else {
                let deletion = PendingShoppingListDeletion(
                    shoppingListId: pending.shoppingListId,
                    itemId: persistedID
                )
                pendingDeletions.insert(deletion)
                persistDeletionCache()
                startDeleteSync(deletion: deletion, supabase: supabase)
                return
            }

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

    private func startDeleteSync(deletion: PendingShoppingListDeletion, supabase: SupabaseService) {
        let taskKey = deletion.cacheKey
        guard deleteSyncTasks[taskKey] == nil else { return }

        deleteSyncTasks[taskKey] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.deleteSyncTasks[taskKey] = nil }
            guard self.pendingDeletions.contains(deletion) else { return }
            do {
                try await supabase.deleteShoppingListItem(
                    itemId: deletion.itemId,
                    shoppingListId: deletion.shoppingListId
                )
                self.pendingDeletions.remove(deletion)
                self.persistDeletionCache()
            } catch {
                // Keep the tombstone and retry after reconnect or relaunch.
            }
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

            insertItem(
                cachedItem,
                sectionLabel: pending.candidate.sectionLabel ?? "Location not certain",
                sectionSortKey: pending.candidate.sectionSortKey ?? 999,
                sectionType: pending.candidate.sectionType ?? .unknown,
                into: &restored
            )
        }
    }

    private func persistPlanCache() {
        guard let activeUserId, hasPlan, plan.source == .supabase else { return }
        localCache.savePlan(
            CachedPlanState(
                plan: plan,
                pendingImports: pendingImports,
                pendingDeletionItemIDs: []
            ),
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

    private func persistDeletionCache() {
        guard let activeUserId else { return }
        localCache.saveDeletions(Array(pendingDeletions), userId: activeUserId)
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

    private func updateAssistantItem(_ mutation: AssistantListMutation) {
        for sectionIndex in plan.shoppingList.sections.indices {
            guard let itemIndex = plan.shoppingList.sections[sectionIndex].items.firstIndex(where: {
                $0.id == mutation.itemId
            }) else { continue }
            let current = plan.shoppingList.sections[sectionIndex].items[itemIndex]
            let checked = mutation.checked ?? current.checked
            plan.shoppingList.sections[sectionIndex].items[itemIndex] = ShoppingListItem(
                id: current.id,
                name: current.name,
                quantity: mutation.quantity ?? current.quantity,
                checked: checked,
                aisleLabel: current.aisleLabel,
                sectionType: current.sectionType,
                product: current.product,
                importedCandidate: current.importedCandidate,
                locationUncertaintyText: current.locationUncertaintyText,
                clientId: current.clientId
            )
            checkedStates[current.id] = checked
            if checked {
                checkedItemIDs.insert(current.id)
            } else {
                checkedItemIDs.remove(current.id)
            }
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

    private func insertItem(
        _ item: ShoppingListItem,
        sectionLabel: String,
        sectionSortKey: Int,
        sectionType: ShoppingSectionType,
        into plan: inout WeekPlan
    ) {
        if let sectionIndex = plan.shoppingList.sections.firstIndex(where: {
            $0.label == sectionLabel && $0.sortKey == sectionSortKey
        }) {
            plan.shoppingList.sections[sectionIndex].items.append(item)
        } else {
            plan.shoppingList.sections.append(
                ShoppingListSection(
                    label: sectionLabel,
                    sortKey: sectionSortKey,
                    type: sectionType,
                    items: [item]
                )
            )
        }

        plan.shoppingList.sections.sort {
            if $0.sortKey == $1.sortKey { return $0.label < $1.label }
            return $0.sortKey < $1.sortKey
        }
    }

    private func sectionContext(for itemId: String, in plan: WeekPlan) -> ShoppingItemSectionContext? {
        guard let section = plan.shoppingList.sections.first(where: { section in
            section.items.contains(where: { $0.id == itemId })
        }) else { return nil }

        return ShoppingItemSectionContext(
            label: section.label,
            sortKey: section.sortKey,
            type: section.type
        )
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

    private static func dateFromISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

}

private struct ShoppingItemSectionContext {
    let label: String
    let sortKey: Int
    let type: ShoppingSectionType
}

private struct PendingImportedItem: Codable, Hashable {
    let idempotencyKey: String
    let localItemID: String
    let shoppingListId: String
    let candidate: ProductCandidate
    let quantity: String
    let sortOrder: Int
}

private struct PendingShoppingListDeletion: Codable, Hashable {
    let shoppingListId: String
    let itemId: String

    var cacheKey: String { "\(shoppingListId):\(itemId)" }
}

private struct CachedPlanState: Codable {
    let plan: WeekPlan
    let pendingImports: [PendingImportedItem]
    let pendingDeletionItemIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case plan, pendingImports, pendingDeletionItemIDs
    }

    init(plan: WeekPlan, pendingImports: [PendingImportedItem], pendingDeletionItemIDs: [String]) {
        self.plan = plan
        self.pendingImports = pendingImports
        self.pendingDeletionItemIDs = pendingDeletionItemIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decode(WeekPlan.self, forKey: .plan)
        pendingImports = try container.decodeIfPresent([PendingImportedItem].self, forKey: .pendingImports) ?? []
        pendingDeletionItemIDs = try container.decodeIfPresent([String].self, forKey: .pendingDeletionItemIDs) ?? []
    }
}

private struct CachedCheckState: Codable {
    let shoppingListId: String
    let states: [String: Bool]
    let pendingItemIDs: [String]
}

private struct PendingGenerationRequest: Codable, Hashable {
    let idempotencyKey: String
    var requestId: String?
    let storeId: StoreID
    let weekStart: String
    let startedAt: Date
    var stage: GenerationRequestStage
    var cancellationRequested: Bool
    let opensWhenReady: Bool
    let planBrief: PlanBrief?

    enum CodingKeys: String, CodingKey {
        case idempotencyKey, requestId, storeId, weekStart, startedAt, stage
        case cancellationRequested, opensWhenReady, planBrief
    }

    init(
        idempotencyKey: String,
        requestId: String?,
        storeId: StoreID,
        weekStart: String,
        startedAt: Date,
        stage: GenerationRequestStage,
        cancellationRequested: Bool,
        opensWhenReady: Bool,
        planBrief: PlanBrief? = nil
    ) {
        self.idempotencyKey = idempotencyKey
        self.requestId = requestId
        self.storeId = storeId
        self.weekStart = weekStart
        self.startedAt = startedAt
        self.stage = stage
        self.cancellationRequested = cancellationRequested
        self.opensWhenReady = opensWhenReady
        self.planBrief = planBrief
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idempotencyKey = try container.decode(String.self, forKey: .idempotencyKey)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        storeId = try container.decode(StoreID.self, forKey: .storeId)
        weekStart = try container.decode(String.self, forKey: .weekStart)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        stage = try container.decode(GenerationRequestStage.self, forKey: .stage)
        cancellationRequested = try container.decode(Bool.self, forKey: .cancellationRequested)
        opensWhenReady = try container.decode(Bool.self, forKey: .opensWhenReady)
        planBrief = try container.decodeIfPresent(PlanBrief.self, forKey: .planBrief)
    }
}

private final class GenerationRequestLocalCache {
    private let fileManager: FileManager
    private let directoryURL: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        directoryURL = applicationSupport?.appendingPathComponent("ReasiGenerationCache", isDirectory: true)
        if let directoryURL {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    func load(userId: String) -> PendingGenerationRequest? {
        guard let url = fileURL(userId: userId),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(PendingGenerationRequest.self, from: data)
    }

    func save(_ request: PendingGenerationRequest, userId: String) {
        guard let url = fileURL(userId: userId),
              let data = try? encoder.encode(request) else { return }
        do {
            try data.write(to: url, options: [.atomic])
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            // The remote generation request remains authoritative.
        }
    }

    func remove(userId: String) {
        guard let url = fileURL(userId: userId) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func fileURL(userId: String) -> URL? {
        let safeUserId = userId.replacingOccurrences(of: "/", with: "_")
        return directoryURL?.appendingPathComponent("pending-\(safeUserId).json", isDirectory: false)
    }
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

    func loadDeletions(userId: String) -> [PendingShoppingListDeletion] {
        load([PendingShoppingListDeletion].self, from: fileURL(kind: "deletions", userId: userId)) ?? []
    }

    func saveDeletions(_ deletions: [PendingShoppingListDeletion], userId: String) {
        save(deletions, to: fileURL(kind: "deletions", userId: userId))
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
