import SwiftUI

struct SmartBasketSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(CoreLoopStore.self) private var coreLoop
    @Environment(SupabaseService.self) private var supabase
    @Environment(AppState.self) private var appState
    @Environment(NetworkMonitor.self) private var network
    let expectedStoreId: StoreID
    @State private var flexibility = SmartBasketFlexibility()

    private var review: SmartBasketReviewStore { coreLoop.smartBasketReview }

    private var operations: SmartBasketOperations {
        #if DEBUG
        if FixtureSmartBasket.isEnabled {
            return FixtureSmartBasket.operations(storeId: expectedStoreId, isOnline: { network.isConnected })
        }
        #endif
        return coreLoop.smartBasketOperations(
            supabase: supabase, appState: appState, network: network, expectedStoreId: expectedStoreId
        )
    }

    private var currentContext: SmartBasketContext? { try? operations.context() }

    private var blockedMessage: String? {
        do {
            let current = try operations.context()
            if let context = review.context, context != current, review.receipt == nil, review.attempt == nil {
                return SmartBasketError.contextChanged.localizedDescription
            }
            if let expected = review.receipt?.context ?? review.attempt?.context,
               !expected.hasSameOwnerAndList(as: current) {
                return SmartBasketError.contextChanged.localizedDescription
            }
            return nil
        } catch {
            if case SmartBasketError.offline = error {
                if review.receipt != nil {
                    return SmartBasketError.refreshRequired.localizedDescription + "\n" + SmartBasketError.offline.localizedDescription
                }
                if review.attempt != nil { return SmartBasketError.confirmationRequired.localizedDescription }
            }
            return (error as? SmartBasketError)?.localizedDescription ?? SmartBasketError.unavailable.localizedDescription
        }
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                ScrollView {
                    VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                        flexibilityControls
                        content(now: timeline.date)
                    }
                    .padding(ReasiSpacing.s5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    applyFooter(now: timeline.date)
                }
            }
            .background(Color.reasi.background)
            .navigationTitle("Smart Basket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .disabled(review.isApplying)
                }
            }
        }
        .interactiveDismissDisabled(review.isApplying)
        .task(id: flexibility) {
            coreLoop.isReviewingSmartBasket = true
            await review.load(using: operations, flexibility: flexibility)
        }
        .onDisappear { coreLoop.isReviewingSmartBasket = false }
    }

    private var flexibilityControls: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            Toggle("Allow different brands", isOn: $flexibility.allowBrandChange)
                .accessibilityIdentifier("smart-basket-brands")
            Toggle("Allow different pack sizes", isOn: $flexibility.allowPackChange)
                .accessibilityIdentifier("smart-basket-packs")
        }
        .font(ReasiTypography.body)
        .foregroundStyle(Color.reasi.text)
        .tint(Color.reasi.success)
        .disabled(review.isLoading || review.isApplying || review.receipt != nil || review.attempt != nil || review.didApply)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if review.isLoading {
            HStack(spacing: ReasiSpacing.s3) {
                ProgressView()
                Text("Checking your basket")
                    .font(ReasiTypography.body)
                    .foregroundStyle(Color.reasi.textMuted)
            }
            .accessibilityIdentifier("smart-basket-loading")
        } else if review.didApply {
            Label("Your selected swaps are saved", systemImage: "checkmark.circle")
                .font(ReasiTypography.headline)
                .foregroundStyle(Color.reasi.success)
        } else {
            if let message = blockedMessage ?? review.message {
                Text(message)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("smart-basket-notice")
            }
            if let preview = review.preview {
                if preview.isExpired(at: now), review.receipt == nil, review.attempt == nil {
                    Text(SmartBasketError.expired.localizedDescription)
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.warning)
                }
                if preview.lines.isEmpty {
                    Text("There are no items to compare in this list.")
                        .font(ReasiTypography.body)
                        .foregroundStyle(Color.reasi.textMuted)
                } else {
                    costSummary(preview)
                    statusDetail(preview)
                    VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
                        ForEach(preview.lines) { line in
                            lineRow(line, preview: preview, now: now)
                            if line.id != preview.lines.last?.id {
                                Divider().overlay(Color.reasi.border)
                            }
                        }
                    }
                    priceDetails(preview)
                }
            }
            if review.receipt == nil, review.attempt == nil {
                Button("Refresh preview", systemImage: "arrow.clockwise") {
                    Task { await review.load(using: operations, flexibility: flexibility) }
                }
                .font(ReasiTypography.callout)
                .disabled(review.isApplying || currentContext == nil)
                .accessibilityIdentifier("smart-basket-refresh")
            }
        }
    }

    private func costSummary(_ preview: SmartBasketPreview) -> some View {
        let costs = preview.costs(selectedLineIDs: review.selectedLineIDs)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ReasiSpacing.s4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: ReasiSpacing.s4))
        return VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            Text("Estimated purchase costs")
                .font(ReasiTypography.headline)
                .foregroundStyle(Color.reasi.text)
            layout {
                costColumn("Current", cents: costs.currentTotalCents)
                costColumn("With selected swaps", cents: costs.proposedTotalCents)
            }
            if costs.currentTotalCents == nil || costs.proposedTotalCents == nil {
                Text("Full totals unconfirmed")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
                Text("Comparable items: \(preview.coverage.comparable) of \(preview.coverage.lineCount)")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
                layout {
                    costColumn("Current comparable subtotal", cents: costs.comparableCurrentCents)
                    costColumn("Selected comparable subtotal", cents: costs.comparableProposedCents)
                }
            }
            if let reduction = costs.estimatedReductionCents, !review.selectedLineIDs.isEmpty {
                Text("Estimated reduction: \(SmartBasketMoney.text(reduction))\(costs.currentTotalCents == nil ? " on comparable items" : "")")
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(Color.reasi.success)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("smart-basket-reduction")
            }
            Text("Estimates only. Prices and availability may change in store.")
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func costColumn(_ label: String, cents: Int?) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s1) {
            Text(label).font(ReasiTypography.caption).foregroundStyle(Color.reasi.muted)
            Text(SmartBasketMoney.text(cents))
                .font(ReasiTypography.headline)
                .monospacedDigit()
                .foregroundStyle(Color.reasi.text)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusDetail(_ preview: SmartBasketPreview) -> some View {
        if preview.coverage.comparable == 0 {
            VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                Text("Prices can't be compared yet")
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                Text("There aren't enough confirmed price details for these items. Your list stays unchanged.")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
            }
        } else if preview.status == "no_change" {
            Text("No lower-cost swaps were confirmed for this basket.")
                .font(ReasiTypography.body)
                .foregroundStyle(Color.reasi.textMuted)
        } else if preview.status == "partial" || preview.status == "needs_input" {
            Text("Some items couldn't be compared. Unconfirmed items will stay unchanged.")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
        } else if preview.status != "ready" {
            Text("No confirmed swaps are available right now.")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
        }
    }

    private func lineRow(_ line: SmartBasketLine, preview: SmartBasketPreview, now: Date) -> some View {
        let selectable = review.context.map { preview.selectableLineIDs(in: $0).contains(line.id) } ?? false
        return VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            Text("Needed: \(line.quantity)")
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
            if let baseline = line.baseline {
                choiceRow(baseline, label: "Current")
            } else {
                Text(line.displayName).font(ReasiTypography.bodyMedium).foregroundStyle(Color.reasi.text)
                Text("Current price unconfirmed").font(ReasiTypography.callout).foregroundStyle(Color.reasi.muted)
            }
            if selectable, let selected = line.selected {
                Toggle(isOn: Binding(
                    get: { review.selectedLineIDs.contains(line.id) },
                    set: { _ in review.toggleSelection(line.id) }
                )) {
                    choiceRow(selected, label: selected.matchLabel == "exact" ? "Same product" : "Proposed swap")
                }
                .tint(Color.reasi.success)
                .disabled(blockedMessage != nil || preview.isExpired(at: now) || review.isApplying || review.receipt != nil || review.attempt != nil || review.requiresPreviewRefresh)
                .accessibilityIdentifier("smart-basket-select-\(line.id)")
            } else {
                Text(review.context?.checkedLineIDs.contains(line.id) == true ? "Already picked; unchanged" : "No confirmed swap; unchanged")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choiceRow(_ choice: SmartBasketChoice, label: String) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s1) {
            Text(label).font(ReasiTypography.caption).foregroundStyle(Color.reasi.muted)
            Text(choice.name).font(ReasiTypography.bodyMedium).foregroundStyle(Color.reasi.text)
            Text(choice.purchaseLabel).font(ReasiTypography.callout).foregroundStyle(Color.reasi.textMuted)
            Text("\(choice.isWeightedEstimate ? "Estimated cost" : "Purchase cost"): \(SmartBasketMoney.text(choice.lineTotalCents))")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.text)
            if let surplus = choice.surplusAmount, surplus > 0, let unit = choice.surplusUnit {
                Text("Extra: \(surplus.formatted()) \(unit)")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func priceDetails(_ preview: SmartBasketPreview) -> some View {
        DisclosureGroup("Price dates and details") {
            VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
                Text("Compared \(SmartBasketDate.display(preview.asOf))")
                Text("Valid until \(SmartBasketDate.display(preview.expiresAt))")
                Text("\(preview.coverage.baselinePriced) current items priced and \(preview.coverage.candidatePriced) proposed items priced across \(preview.coverage.lineCount) items.")
                ForEach(preview.lines) { line in
                    ForEach(Array([line.baseline, line.selected].compactMap { $0 }.enumerated()), id: \.offset) { _, choice in
                        VStack(alignment: .leading, spacing: ReasiSpacing.s1) {
                            Text(choice.name).font(ReasiTypography.bodyMedium).foregroundStyle(Color.reasi.text)
                            Text("Captured \(SmartBasketDate.display(choice.capturedAt))")
                            Text(choice.trustDescription)
                            if choice.isWeightedEstimate {
                                Text("Weight-based estimate. Final weight and cost may differ.")
                            }
                            if !choice.uncertainties.isEmpty {
                                Text("Pack size, price conditions or availability need checking in store.")
                            }
                        }
                    }
                }
            }
            .font(ReasiTypography.callout)
            .foregroundStyle(Color.reasi.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, ReasiSpacing.s3)
        }
        .font(ReasiTypography.bodyMedium)
        .foregroundStyle(Color.reasi.text)
        .accessibilityIdentifier("smart-basket-price-details")
    }

    private func applyFooter(now: Date) -> some View {
        VStack(spacing: ReasiSpacing.s2) {
            if !review.didApply {
                Text("\(review.selectedLineIDs.count) \(review.selectedLineIDs.count == 1 ? "swap" : "swaps") selected")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
            }
            Button {
                if review.didApply {
                    dismiss()
                } else if review.requiresPreviewRefresh {
                    Task { await review.load(using: operations, flexibility: flexibility) }
                } else {
                    Task { await review.apply(using: operations) }
                }
            } label: {
                HStack(spacing: ReasiSpacing.s2) {
                    if review.isApplying { ProgressView() }
                    Text(review.didApply ? "Done" : review.receipt != nil ? "Reload list" : review.attempt != nil ? "Check saved swaps" : review.requiresPreviewRefresh ? "Refresh preview" : "Apply selected swaps")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, ReasiSpacing.s4)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ReasiPrimaryButtonStyle(allowsMultiline: true))
            .disabled(!review.didApply && (review.isApplying || review.isLoading ||
                (review.requiresPreviewRefresh ? currentContext == nil : review.receipt != nil || review.attempt != nil ? !review.canReconcile(in: currentContext) : !review.canApply(in: currentContext, at: now))))
            .accessibilityIdentifier("smart-basket-apply")
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.background)
    }
}
