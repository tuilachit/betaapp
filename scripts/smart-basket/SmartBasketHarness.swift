import Foundation

@main struct SmartBasketHarness {
    @MainActor static func main() async throws {
        var failures = 0
        var checks = 0
        func check(_ pass: Bool, _ name: String) {
            checks += 1
            print("\(pass ? "PASS" : "FAIL") \(name)")
            if !pass { failures += 1 }
        }
        let now = Date()
        let preview = FixtureSmartBasket.preview(now: now)
        let context = FixtureSmartBasket.context
        func editedPreview(_ edit: (inout [String: Any]) -> Void) throws -> SmartBasketPreview {
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preview)) as! [String: Any]
            edit(&json)
            return try JSONDecoder().decode(SmartBasketPreview.self, from: JSONSerialization.data(withJSONObject: json))
        }
        check(SmartBasketFlexibility() == .init(allowBrandChange: false, allowPackChange: false), "flexibility defaults off")
        check(SmartBasketMoney.text(nil) == "Unconfirmed", "unknown money is not zero")
        check(SmartBasketMoney.text(0) == "A$0.00", "confirmed zero remains zero")
        check(SmartBasketMoney.text(3596) == "A$35.96", "cents do not become prorated dollars")
        check(preview.lines[0].selected?.isWeightedEstimate == true, "weighted choice explicitly marked")
        check(preview.lines[1].selected?.costType == nil, "legacy choices decode without additive cost type")
        check(!preview.isExpired(at: now), "fresh preview can be used")
        check(preview.isExpired(at: now.addingTimeInterval(901)), "expired preview is unusable")
        check(SmartBasketDate.parse("invalid") == nil, "invalid dates fail closed")
        check(SmartBasketDate.parse("2026-10-09T12:00:00.123Z") != nil, "fractional capture timestamps decode")
        let labeled = try SmartBasketContext.ownedQuantities([(id: "rice", quantity: " 1 kg pack ")])
        check(labeled["rice"] == " 1 kg pack ", "owned quantity labels remain verbatim")
        do {
            _ = try SmartBasketContext.ownedQuantities([(id: "rice", quantity: "1 kg"), (id: "rice", quantity: "2 kg")])
            check(false, "duplicate owned item IDs rejected without dictionary trap")
        } catch {
            check(error is SmartBasketError, "duplicate owned item IDs rejected without dictionary trap")
        }
        check(preview.isValid(for: context, at: now), "owned fixture validates")
        var wrong = context
        wrong.storeId = .topRyde
        check(!preview.isValid(for: wrong, at: now), "cross-store response rejected")
        wrong = context
        wrong.shoppingListId = "other-list"
        check(!preview.isValid(for: wrong, at: now), "cross-list response rejected")
        wrong = context
        wrong.mealPlanId = "other-plan"
        check(!preview.isValid(for: wrong, at: now), "cross-plan response rejected")
        wrong = context
        wrong.checkedLineIDs = ["bananas"]
        check(!preview.selectableLineIDs(in: wrong).contains("bananas"), "checked line cannot be selected")
        let selected: Set<String> = ["rice"]
        let cost = preview.costs(selectedLineIDs: selected)
        check(cost.currentTotalCents == 1480 && cost.proposedTotalCents == 1180, "selected costs retain whole-pack purchase counts")
        check(cost.estimatedReductionCents == 300, "only selected swaps count toward estimated savings")
        check(preview.costs(selectedLineIDs: []).estimatedReductionCents == 0, "no selections do not claim savings")
        let partial = FixtureSmartBasket.preview(now: now, partial: true)
        check(partial.costs(selectedLineIDs: selected).currentTotalCents == nil, "missing full baseline never becomes a subtotal")
        check(partial.costs(selectedLineIDs: selected).proposedTotalCents == nil, "missing full proposal never shows zero")
        check(partial.costs(selectedLineIDs: selected).comparableCurrentCents == 1480, "partial comparison remains clearly scoped")
        let unsupported = FixtureSmartBasket.unsupportedPreview()
        let unsupportedCost = unsupported.costs(selectedLineIDs: [])
        check(unsupported.coverage.comparable == 0 && unsupported.coverage.lineCount == 10, "legacy missing evidence retains zero-of-ten coverage")
        check(unsupportedCost.currentTotalCents == nil && unsupportedCost.proposedTotalCents == nil
              && unsupportedCost.estimatedReductionCents == nil, "unsupported data never claims zero totals or cheaper prices")
        check(SmartBasketMoney.sum([9_007_199_254_740_991, 1]) == nil, "unsafe summed cents fail closed")
        check(SmartBasketMoney.text(-1) == "Unconfirmed", "negative cost is not presented as valid money")
        let invalidDate = try editedPreview { $0["expiresAt"] = "invalid" }
        check(invalidDate.isExpired(at: now) && !invalidDate.isValid(for: context), "malformed expiry cannot authorize Apply")
        let duplicates = try editedPreview { json in
            var lines = json["lines"] as! [[String: Any]]
            lines[1]["id"] = lines[0]["id"]
            json["lines"] = lines
        }
        check(!duplicates.isValid(for: context), "duplicate owned line IDs rejected")
        let negative = try editedPreview { $0["baselineTotalCents"] = -1 }
        check(!negative.isValid(for: context), "negative wire totals rejected")
        let unconfirmed = try editedPreview { json in
            for key in ["baselineTotalCents", "candidateTotalCents", "estimatedReductionCents", "comparableBaselineSubtotalCents", "comparableCandidateSubtotalCents", "comparableReductionCents"] {
                json[key] = NSNull()
            }
        }
        check(unconfirmed.costs(selectedLineIDs: selected).estimatedReductionCents == nil, "unconfirmed comparison cannot claim inferred savings")
        let inputJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SmartBasketPreviewInput(
            shoppingListId: context.shoppingListId, expectedStoreId: context.storeId, flexibility: .init()
        ))) as! [String: Any]
        check(Set(inputJSON.keys) == ["shoppingListId", "expectedStoreId", "flexibility"], "wire input never sends client prices or products")
        check(FixtureSmartBasket.preview(status: "no_change").selectableLineIDs(in: context).isEmpty, "no-change preview cannot select swaps")
        check(FixtureSmartBasket.preview(status: "needs_input").selectableLineIDs(in: context).isEmpty, "insufficient data cannot select swaps")

        var current = context
        var events: [String] = []
        var applyCount = 0
        var refreshFails = false
        var mutatePreview: (() -> Void)?
        var mutateApply: (() -> Void)?
        let response = SmartBasketApplyResponse(
            shoppingListId: context.shoppingListId, mealPlanId: context.mealPlanId,
            storeId: context.storeId, appliedLineIds: ["rice"]
        )
        let operations = SmartBasketOperations(
            context: { current },
            flush: { events.append("flush") },
            preview: { input in
                events.append("preview")
                check(input.shoppingListId == current.shoppingListId && !input.flexibility.allowPackChange, "preview sends IDs and opt-in flags only")
                mutatePreview?()
                return preview
            },
            apply: { input in
                events.append("apply")
                applyCount += 1
                check(input.selectedLineIds == ["rice"] && input.expectedStoreId == context.storeId, "apply sends exact selected owned rows")
                mutateApply?()
                return response
            },
            reload: { receipt in
                events.append("reload")
                check(receipt.response.mealPlanId == context.mealPlanId, "reload targets exact response plan")
                if refreshFails { throw SmartBasketError.refreshRequired }
            }
        )
        let review = SmartBasketReviewStore()
        await review.load(using: operations, flexibility: .init(), now: now)
        check(events == ["flush", "preview"], "pending local writes flush before preview")
        check(review.preview != nil && review.selectedLineIDs.isEmpty, "swaps require explicit selection")
        review.toggleSelection("unknown")
        check(review.selectedLineIDs.isEmpty, "unknown line cannot be selected")
        review.toggleSelection("rice")
        await review.apply(using: operations, now: now)
        check(events == ["flush", "preview", "flush", "apply", "reload"], "apply flushes then reloads exact plan")
        check(review.didApply, "successful refreshed apply is terminal")
        await review.apply(using: operations, now: now)
        check(applyCount == 1, "successful apply cannot be sent twice")

        let stale = SmartBasketReviewStore()
        current = context
        mutatePreview = { current.identity.revision += 1 }
        await stale.load(using: operations, flexibility: .init(), now: now)
        check(stale.preview == nil && stale.message != nil, "identity revision change drops in-flight preview")
        mutatePreview = { current.identity.userId = "other-user" }
        current = context
        await stale.load(using: operations, flexibility: .init(), now: now)
        check(stale.preview == nil, "account change drops in-flight preview")
        mutatePreview = nil
        current = context
        await stale.load(using: operations, flexibility: .init(), now: now)
        stale.toggleSelection("rice")
        current.listRevision = Data("changed".utf8)
        await stale.apply(using: operations, now: now)
        check(applyCount == 1 && stale.message != nil, "edited list cannot apply old preview")
        current = context
        check(!stale.canApply(in: current, at: now), "failed Apply stays disabled until refreshed")

        current = context
        let expired = SmartBasketReviewStore()
        await expired.load(using: operations, flexibility: .init(), now: now)
        expired.toggleSelection("rice")
        await expired.apply(using: operations, now: now.addingTimeInterval(901))
        check(applyCount == 1, "expiry checked again at Apply")

        let reload = SmartBasketReviewStore()
        await reload.load(using: operations, flexibility: .init(), now: now)
        reload.toggleSelection("rice")
        refreshFails = true
        await reload.apply(using: operations, now: now)
        check(reload.receipt != nil && !reload.didApply, "successful mutation retained when refresh fails")
        refreshFails = false
        await reload.apply(using: operations, now: now)
        check(applyCount == 2 && reload.didApply, "refresh retry never repeats mutation")

        let changedUser = SmartBasketReviewStore()
        await changedUser.load(using: operations, flexibility: .init(), now: now)
        changedUser.toggleSelection("rice")
        mutateApply = { current.identity.revision += 1 }
        let reloadCount = events.filter { $0 == "reload" }.count
        await changedUser.apply(using: operations, now: now)
        check(events.filter { $0 == "reload" }.count == reloadCount, "apply response after sign-out cannot reload into another session")
        mutateApply = nil
        current = context

        var continuation: CheckedContinuation<SmartBasketApplyResponse, Never>?
        let slow = SmartBasketOperations(
            context: { current }, flush: {}, preview: { _ in preview },
            apply: { _ in
                applyCount += 1
                return await withCheckedContinuation { continuation = $0 }
            }, reload: { _ in }
        )
        let single = SmartBasketReviewStore()
        await single.load(using: slow, flexibility: .init(), now: now)
        single.toggleSelection("rice")
        let first = Task { await single.apply(using: slow, now: now) }
        while continuation == nil { await Task.yield() }
        let countBefore = applyCount
        await single.apply(using: slow, now: now)
        check(applyCount == countBefore && single.isApplying, "Apply is single flight across awaits")
        continuation?.resume(returning: response)
        await first.value
        check(single.didApply, "single-flight request completes")

        var blocked: SmartBasketError?
        var blockedCalls = 0
        var flushMutation: (() -> Void)?
        var reloadMutation: (() -> Void)?
        let guarded = SmartBasketOperations(
            context: { if let blocked { throw blocked }; return current },
            flush: { flushMutation?() },
            preview: { _ in blockedCalls += 1; return preview },
            apply: { _ in blockedCalls += 1; return response },
            reload: { _ in reloadMutation?() }
        )
        for reason: SmartBasketError in [.offline, .signedOut, .unavailable, .contextChanged] {
            let disabled = SmartBasketReviewStore()
            blocked = reason
            await disabled.load(using: guarded, flexibility: .init(), now: now)
            check(disabled.preview == nil && disabled.message == reason.localizedDescription, "blocked \(reason) has a usable state")
        }
        check(blockedCalls == 0, "offline/completed/signed-out/store-switch states never request prices")
        blocked = nil
        let flushChange = SmartBasketReviewStore()
        flushMutation = { current.identity.revision += 1 }
        await flushChange.load(using: guarded, flexibility: .init(), now: now)
        check(blockedCalls == 0, "identity checked after flushing local writes")
        flushMutation = nil
        current = context
        let offlineApply = SmartBasketReviewStore()
        await offlineApply.load(using: guarded, flexibility: .init(), now: now)
        offlineApply.toggleSelection("rice")
        blocked = .offline
        let beforeOffline = blockedCalls
        await offlineApply.apply(using: guarded, now: now)
        check(blockedCalls == beforeOffline && offlineApply.message == SmartBasketError.offline.localizedDescription, "going offline after preview disables Apply")
        blocked = nil
        let applyFlushChange = SmartBasketReviewStore()
        await applyFlushChange.load(using: guarded, flexibility: .init(), now: now)
        applyFlushChange.toggleSelection("rice")
        flushMutation = { current.storeId = .topRyde }
        let beforeFlush = blockedCalls
        await applyFlushChange.apply(using: guarded, now: now)
        check(blockedCalls == beforeFlush, "store rechecked after Apply flush")
        flushMutation = nil
        current = context
        let reloadChange = SmartBasketReviewStore()
        await reloadChange.load(using: guarded, flexibility: .init(), now: now)
        reloadChange.toggleSelection("rice")
        reloadMutation = { current.identity.revision += 1 }
        await reloadChange.apply(using: guarded, now: now)
        check(!reloadChange.didApply, "identity checked after exact-plan reload")
        reloadMutation = nil
        current = context
        let pending = SmartBasketReviewStore()
        let pendingOps = SmartBasketOperations(
            context: { current }, flush: { throw SmartBasketError.pendingChanges },
            preview: { _ in blockedCalls += 1; return preview }, apply: { _ in blockedCalls += 1; return response }, reload: { _ in }
        )
        let beforePending = blockedCalls
        await pending.load(using: pendingOps, flexibility: .init(), now: now)
        check(blockedCalls == beforePending && pending.message == SmartBasketError.pendingChanges.localizedDescription, "unsaved local writes prevent preview")

        var online = true
        var confirmationCalls = 0
        var goOfflineOnApply = false
        let confirmationOps = SmartBasketOperations(
            context: { guard online else { throw SmartBasketError.offline }; return context },
            confirmationContext: { context },
            flush: {}, preview: { _ in preview },
            apply: { _ in
                confirmationCalls += 1
                if goOfflineOnApply { online = false }
                return response
            },
            reload: { _ in guard online else { throw SmartBasketError.offline }; throw SmartBasketError.refreshRequired }
        )
        let offlineReceipt = SmartBasketReviewStore()
        await offlineReceipt.load(using: confirmationOps, flexibility: .init(), now: now)
        offlineReceipt.toggleSelection("rice")
        await offlineReceipt.apply(using: confirmationOps, now: now)
        online = false
        await offlineReceipt.load(using: confirmationOps, flexibility: .init(), now: now)
        check(offlineReceipt.receipt != nil, "offline load preserves confirmed receipt")
        online = true
        goOfflineOnApply = true
        let responseThenOffline = SmartBasketReviewStore()
        await responseThenOffline.load(using: confirmationOps, flexibility: .init(), now: now)
        responseThenOffline.toggleSelection("rice")
        await responseThenOffline.apply(using: confirmationOps, now: now)
        check(responseThenOffline.receipt != nil, "successful response records confirmation even when network goes offline")

        online = true
        var replayInputs: [SmartBasketApplyInput] = []
        var replayFlushes = 0
        let uncertainOps = SmartBasketOperations(
            context: { context }, flush: { replayFlushes += 1 }, preview: { _ in preview },
            apply: { input in
                replayInputs.append(input)
                if replayInputs.count == 1 { throw URLError(.networkConnectionLost) }
                return response
            }, reload: { _ in }
        )
        let uncertain = SmartBasketReviewStore()
        await uncertain.load(using: uncertainOps, flexibility: .init(), now: now)
        uncertain.toggleSelection("rice")
        await uncertain.apply(using: uncertainOps, now: now)
        await uncertain.load(using: uncertainOps, flexibility: .init(allowBrandChange: true), now: now)
        check(uncertain.preview != nil && uncertain.selectedLineIDs == ["rice"], "lost response cannot be discarded by a new preview")
        uncertain.toggleSelection("bananas")
        check(uncertain.selectedLineIDs == ["rice"], "uncertain Apply keeps selection immutable")
        await uncertain.apply(using: uncertainOps, now: now.addingTimeInterval(901))
        check(replayInputs.count == 2 && replayInputs.allSatisfy {
            $0.previewId == preview.previewId && $0.expectedStoreId == context.storeId && $0.selectedLineIds == ["rice"]
        }, "uncertain Apply replays exact payload even after preview expiry")
        check(uncertain.didApply && replayFlushes == 3, "replay flushes local writes and reconciles original result")
        check(uncertain.attempt == nil && uncertain.receipt != nil, "reconciled request becomes a confirmed receipt")
        do {
            try context.validateReload(afterRead: context)
            check(true, "unchanged exact-plan read can integrate")
        } catch { check(false, "unchanged exact-plan read can integrate") }
        var afterRead = context
        afterRead.listRevision = Data("assistant-acknowledged-edit".utf8)
        do {
            try context.validateReload(afterRead: afterRead)
            check(false, "acknowledged mutation during fetch rejects old read")
        } catch { check(true, "acknowledged mutation during fetch rejects old read") }

        var rejectFirstRequest = true
        var rejectReplay = false
        let rejectionOps = SmartBasketOperations(
            context: { context }, flush: {}, preview: { _ in preview },
            apply: { _ in
                if rejectFirstRequest || rejectReplay { throw SmartBasketApplyRejection(reason: .contextChanged) }
                throw URLError(.timedOut)
            }, reload: { _ in }
        )
        let rejected = SmartBasketReviewStore()
        await rejected.load(using: rejectionOps, flexibility: .init(), now: now)
        rejected.toggleSelection("rice")
        await rejected.apply(using: rejectionOps, now: now)
        check(rejected.attempt == nil && rejected.requiresPreviewRefresh, "definitive first rejection permits a fresh preview")
        rejectFirstRequest = false
        await rejected.load(using: rejectionOps, flexibility: .init(), now: now)
        rejected.toggleSelection("rice")
        await rejected.apply(using: rejectionOps, now: now)
        let originalAttempt = rejected.attempt?.input
        rejectReplay = true
        await rejected.apply(using: rejectionOps, now: now)
        check(rejected.attempt?.input == originalAttempt && !rejected.requiresPreviewRefresh,
              "later rejection cannot erase an earlier uncertain commit")
        var differentOwner = context
        differentOwner.identity.revision += 1
        check(!rejected.canReconcile(in: differentOwner), "uncertain Apply cannot replay into another identity revision")

        var switchedContext = context
        var alternative = context
        alternative.shoppingListId = "second-list"
        alternative.mealPlanId = "second-plan"
        alternative.storeId = .topRyde
        let alternativePreview = try editedPreview {
            $0["previewId"] = "second-preview"
            $0["shoppingListId"] = alternative.shoppingListId
            $0["mealPlanId"] = alternative.mealPlanId
            $0["storeId"] = alternative.storeId.rawValue
        }
        var loseContextResponse = true
        var contextApplyCount = 0
        var contextReloadFails = false
        let contextOps = SmartBasketOperations(
            context: { switchedContext }, flush: {},
            preview: { _ in switchedContext.hasSameOwnerAndList(as: context) ? preview : alternativePreview },
            apply: { input in
                contextApplyCount += 1
                if loseContextResponse { loseContextResponse = false; throw URLError(.networkConnectionLost) }
                return response
            },
            reload: { _ in if contextReloadFails { throw SmartBasketError.refreshRequired } }
        )
        let parkedAttempt = SmartBasketReviewStore()
        await parkedAttempt.load(using: contextOps, flexibility: .init(), now: now)
        parkedAttempt.toggleSelection("rice")
        await parkedAttempt.apply(using: contextOps, now: now)
        let parkedPayload = parkedAttempt.attempt?.input
        switchedContext = alternative
        await parkedAttempt.load(using: contextOps, flexibility: .init(), now: now)
        check(parkedAttempt.preview?.previewId == "second-preview" && parkedAttempt.attempt == nil,
              "different store and plan can preview while original Apply is uncertain")
        parkedAttempt.toggleSelection("rice")
        check(parkedAttempt.canApply(in: alternative), "new context is not blocked by parked recovery")
        switchedContext = context
        await parkedAttempt.load(using: contextOps, flexibility: .init(), now: now)
        check(parkedAttempt.attempt?.input == parkedPayload && parkedAttempt.canReconcile(in: context),
              "returning to original context restores exact uncertain request")
        await parkedAttempt.apply(using: contextOps, now: now.addingTimeInterval(901))
        check(parkedAttempt.didApply && contextApplyCount == 2, "restored uncertain context reconciles exact original Apply")

        let parkedReceipt = SmartBasketReviewStore()
        contextReloadFails = true
        await parkedReceipt.load(using: contextOps, flexibility: .init(), now: now)
        parkedReceipt.toggleSelection("rice")
        await parkedReceipt.apply(using: contextOps, now: now)
        switchedContext = alternative
        await parkedReceipt.load(using: contextOps, flexibility: .init(), now: now)
        check(parkedReceipt.preview?.previewId == "second-preview" && parkedReceipt.receipt == nil,
              "different store and plan can preview while original reload is pending")
        switchedContext = context
        await parkedReceipt.load(using: contextOps, flexibility: .init(), now: now)
        check(parkedReceipt.receipt?.response == response && parkedReceipt.canReconcile(in: context),
              "returning to original context restores confirmed receipt")
        let beforeReceiptRetry = contextApplyCount
        contextReloadFails = false
        await parkedReceipt.apply(using: contextOps, now: now)
        check(parkedReceipt.didApply && contextApplyCount == beforeReceiptRetry, "restored receipt reload never repeats Apply")

        loseContextResponse = true
        let signedOutRecovery = SmartBasketReviewStore()
        await signedOutRecovery.load(using: contextOps, flexibility: .init(), now: now)
        signedOutRecovery.toggleSelection("rice")
        await signedOutRecovery.apply(using: contextOps, now: now)
        switchedContext = alternative
        await signedOutRecovery.load(using: contextOps, flexibility: .init(), now: now)
        signedOutRecovery.invalidate()
        switchedContext = context
        await signedOutRecovery.load(using: contextOps, flexibility: .init(), now: now)
        check(signedOutRecovery.attempt == nil && signedOutRecovery.receipt == nil && signedOutRecovery.selectedLineIDs.isEmpty,
              "sign-out invalidation clears active and parked recovery")
        let recoveryKey = SmartBasketRecoveryKey(context)
        var changedKey = context
        changedKey.identity.revision += 1
        check(SmartBasketRecoveryKey(changedKey) != recoveryKey, "recovery key includes identity revision")
        changedKey = context
        changedKey.identity.userId = "another-user"
        check(SmartBasketRecoveryKey(changedKey) != recoveryKey, "recovery key includes account identity")
        changedKey = context
        changedKey.shoppingListId = "another-list"
        check(SmartBasketRecoveryKey(changedKey) != recoveryKey, "recovery key includes shopping list")
        changedKey = context
        changedKey.mealPlanId = "another-plan"
        check(SmartBasketRecoveryKey(changedKey) != recoveryKey, "recovery key includes meal plan")
        changedKey = context
        changedKey.storeId = .topRyde
        check(SmartBasketRecoveryKey(changedKey) != recoveryKey, "recovery key includes store")
        print("\(checks) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
