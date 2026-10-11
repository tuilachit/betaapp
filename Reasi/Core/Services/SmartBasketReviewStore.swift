import Foundation
import Observation

@MainActor
struct SmartBasketOperations {
    let context: () throws -> SmartBasketContext
    let confirmationContext: () throws -> SmartBasketContext
    let flush: () async throws -> Void
    let preview: (SmartBasketPreviewInput) async throws -> SmartBasketPreview
    let apply: (SmartBasketApplyInput) async throws -> SmartBasketApplyResponse
    let reload: (SmartBasketAppliedReceipt) async throws -> Void

    init(
        context: @escaping () throws -> SmartBasketContext,
        confirmationContext: (() throws -> SmartBasketContext)? = nil,
        flush: @escaping () async throws -> Void,
        preview: @escaping (SmartBasketPreviewInput) async throws -> SmartBasketPreview,
        apply: @escaping (SmartBasketApplyInput) async throws -> SmartBasketApplyResponse,
        reload: @escaping (SmartBasketAppliedReceipt) async throws -> Void
    ) {
        self.context = context
        self.confirmationContext = confirmationContext ?? context
        self.flush = flush
        self.preview = preview
        self.apply = apply
        self.reload = reload
    }
}

@MainActor
@Observable
final class SmartBasketReviewStore {
    private(set) var preview: SmartBasketPreview?
    private(set) var context: SmartBasketContext?
    private(set) var selectedLineIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var isApplying = false
    private(set) var didApply = false
    private(set) var requiresPreviewRefresh = false
    private(set) var receipt: SmartBasketAppliedReceipt?
    private(set) var attempt: SmartBasketApplyAttempt?
    private(set) var message: String?
    @ObservationIgnored private var loadID: UUID?
    @ObservationIgnored private var revisionID = UUID()
    @ObservationIgnored private var parkedRecoveries: [SmartBasketRecoveryKey: Recovery] = [:]

    private struct Recovery {
        let preview: SmartBasketPreview?
        let context: SmartBasketContext
        let selectedLineIDs: Set<String>
        let attempt: SmartBasketApplyAttempt?
        let receipt: SmartBasketAppliedReceipt?
    }

    func invalidate() {
        revisionID = UUID()
        parkedRecoveries = [:]
        clearActiveReview()
    }

    private func clearActiveReview() {
        loadID = nil
        preview = nil
        context = nil
        selectedLineIDs = []
        receipt = nil
        attempt = nil
        didApply = false
        requiresPreviewRefresh = false
        message = nil
        isLoading = false
    }

    private func activateRecovery(for current: SmartBasketContext) {
        let key = SmartBasketRecoveryKey(current)
        if let active = receipt?.context ?? attempt?.context ?? context, SmartBasketRecoveryKey(active) != key {
            if attempt != nil || (receipt != nil && !didApply) {
                parkedRecoveries[SmartBasketRecoveryKey(active)] = Recovery(
                    preview: preview, context: active, selectedLineIDs: selectedLineIDs, attempt: attempt, receipt: receipt
                )
            }
            clearActiveReview()
        }
        if let recovery = parkedRecoveries.removeValue(forKey: key) {
            clearActiveReview()
            preview = recovery.preview
            context = recovery.context
            selectedLineIDs = recovery.selectedLineIDs
            attempt = recovery.attempt
            receipt = recovery.receipt
        }
    }

    func toggleSelection(_ id: String) {
        guard !isApplying, !isLoading, !didApply, !requiresPreviewRefresh, receipt == nil, attempt == nil,
              let preview, let context, preview.selectableLineIDs(in: context).contains(id) else { return }
        if selectedLineIDs.contains(id) { selectedLineIDs.remove(id) } else { selectedLineIDs.insert(id) }
    }

    func canApply(in current: SmartBasketContext?, at now: Date = Date()) -> Bool {
        guard !isApplying, !isLoading, !didApply, !requiresPreviewRefresh, receipt == nil, attempt == nil,
              let preview, let context, current == context, !preview.isExpired(at: now),
              !selectedLineIDs.isEmpty else { return false }
        return selectedLineIDs.isSubset(of: preview.selectableLineIDs(in: context))
    }

    func canReconcile(in current: SmartBasketContext?) -> Bool {
        guard !isApplying, !isLoading, !didApply, let current,
              let expected = receipt?.context ?? attempt?.context else { return false }
        return expected.hasSameOwnerAndList(as: current)
    }

    func load(using operations: SmartBasketOperations, flexibility: SmartBasketFlexibility, now: Date = Date()) async {
        guard !isApplying else { return }
        let initial: SmartBasketContext
        do {
            initial = try operations.context()
        } catch {
            if receipt != nil {
                message = SmartBasketError.refreshRequired.localizedDescription
            } else if attempt != nil {
                message = SmartBasketError.confirmationRequired.localizedDescription
            } else {
                message = Self.displayMessage(error, fallback: "We couldn't check prices right now. Please try again.")
            }
            return
        }
        activateRecovery(for: initial)
        if attempt != nil {
            message = SmartBasketError.confirmationRequired.localizedDescription
            return
        }
        if receipt != nil, !didApply {
            message = SmartBasketError.refreshRequired.localizedDescription
            return
        }
        let id = UUID()
        loadID = id
        isLoading = true
        preview = nil
        context = nil
        selectedLineIDs = []
        message = nil
        didApply = false
        requiresPreviewRefresh = false
        receipt = nil
        defer { if loadID == id { isLoading = false } }
        do {
            try await operations.flush()
            let current = try operations.context()
            guard initial.hasSameOwnerAndList(as: current) else { throw SmartBasketError.contextChanged }
            try Task.checkCancellation()
            let result = try await operations.preview(.init(
                shoppingListId: current.shoppingListId, expectedStoreId: current.storeId, flexibility: flexibility
            ))
            try Task.checkCancellation()
            guard loadID == id else { return }
            guard try operations.context() == current else { throw SmartBasketError.contextChanged }
            guard !result.isExpired(at: max(now, Date())) else { throw SmartBasketError.expired }
            guard result.isValid(for: current, at: max(now, Date())) else { throw SmartBasketError.invalidResponse }
            context = current
            preview = result
        } catch is CancellationError {
            return
        } catch {
            guard loadID == id else { return }
            message = Self.displayMessage(error, fallback: "We couldn't check prices right now. Please try again.")
        }
    }

    func apply(using operations: SmartBasketOperations, now: Date = Date()) async {
        guard !isApplying, !isLoading, !didApply, !requiresPreviewRefresh else { return }
        isApplying = true
        let revision = revisionID
        let isReplay = attempt != nil
        message = nil
        defer { isApplying = false }
        do {
            if let receipt {
                guard receipt.context.hasSameOwnerAndList(as: try operations.context()) else { throw SmartBasketError.contextChanged }
                try await operations.reload(receipt)
                guard revisionID == revision else { return }
                guard receipt.context.hasSameOwnerAndList(as: try operations.confirmationContext()) else { throw SmartBasketError.contextChanged }
                didApply = true
                return
            }
            let pending: SmartBasketApplyAttempt
            if let attempt {
                guard attempt.context.hasSameOwnerAndList(as: try operations.context()) else { throw SmartBasketError.contextChanged }
                pending = attempt
            } else {
                guard let preview, let context, try operations.context() == context else { throw SmartBasketError.contextChanged }
                guard !preview.isExpired(at: max(now, Date())) else { throw SmartBasketError.expired }
                guard !selectedLineIDs.isEmpty, selectedLineIDs.isSubset(of: preview.selectableLineIDs(in: context)) else {
                    throw SmartBasketError.unavailable
                }
                pending = SmartBasketApplyAttempt(input: .init(
                    previewId: preview.previewId, expectedStoreId: context.storeId, selectedLineIds: selectedLineIDs.sorted()
                ), context: context)
            }
            try await operations.flush()
            guard revisionID == revision else { return }
            let current = try operations.context()
            if attempt == nil {
                guard current == pending.context else { throw SmartBasketError.contextChanged }
                guard let preview, !preview.isExpired(at: max(now, Date())) else { throw SmartBasketError.expired }
            } else {
                guard pending.context.hasSameOwnerAndList(as: current) else { throw SmartBasketError.contextChanged }
            }
            try Task.checkCancellation()
            // Retain the exact request before sending. A lost response may still mean it committed.
            attempt = pending
            let response = try await operations.apply(pending.input)
            guard revisionID == revision else { return }
            guard pending.context.hasSameOwnerAndList(as: try operations.confirmationContext()),
                  pending.context.matches(shoppingListId: response.shoppingListId, mealPlanId: response.mealPlanId, storeId: response.storeId),
                  Set(response.appliedLineIds) == Set(pending.input.selectedLineIds),
                  response.appliedLineIds.count == pending.input.selectedLineIds.count else {
                throw SmartBasketError.contextChanged
            }
            // Keep the receipt before reloading. A failed refresh must never resend swaps.
            let applied = SmartBasketAppliedReceipt(previewId: pending.input.previewId, context: pending.context, response: response)
            receipt = applied
            attempt = nil
            do {
                guard pending.context.hasSameOwnerAndList(as: try operations.context()) else { throw SmartBasketError.contextChanged }
                try await operations.reload(applied)
                guard revisionID == revision else { return }
                guard pending.context.hasSameOwnerAndList(as: try operations.confirmationContext()) else { throw SmartBasketError.contextChanged }
                didApply = true
            } catch {
                guard revisionID == revision else { return }
                message = SmartBasketError.refreshRequired.localizedDescription
            }
        } catch {
            guard revisionID == revision else { return }
            if let rejection = error as? SmartBasketApplyRejection, !isReplay {
                attempt = nil
                requiresPreviewRefresh = true
                message = rejection.reason.localizedDescription
            } else if receipt != nil {
                message = SmartBasketError.refreshRequired.localizedDescription
            } else if attempt != nil {
                message = SmartBasketError.confirmationRequired.localizedDescription
            } else {
                requiresPreviewRefresh = true
                message = Self.displayMessage(error, fallback: "We couldn't apply your swaps. Refresh the preview and try again.")
            }
        }
    }

    private static func displayMessage(_ error: Error, fallback: String) -> String {
        (error as? SmartBasketError)?.localizedDescription ?? fallback
    }
}
