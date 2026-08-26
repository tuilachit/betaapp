import PhotosUI
import SwiftUI
import UIKit
import Vision
import VisionKit

struct ShoppingListPlaceholderView: View {
    @Environment(AppState.self) private var appState
    @Environment(CoreLoopStore.self) private var coreLoop
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(NetworkMonitor.self) private var network
    @Environment(UserSettingsStore.self) private var userSettings
    @Environment(OnboardingStore.self) private var onboarding

    @State private var didTrackView = false
    @State private var showAddDialog = false
    @State private var showProductPhotoPicker = false
    @State private var showListPhotoPicker = false
    @State private var showProductCamera = false
    @State private var showListCamera = false
    @State private var selectedProductPhoto: PhotosPickerItem?
    @State private var selectedListPhoto: PhotosPickerItem?
    @State private var activeSheet: ShoppingListSheet?
    @State private var productSearchContext: ProductSearchContext?
    @State private var inlineError: String?
    @State private var inputIsBusy = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                    header
                    if !coreLoop.generationState.isGenerating,
                       let error = coreLoop.generationState.errorMessage {
                        generationFeedback(
                            error,
                            symbol: "exclamationmark.triangle.fill",
                            color: Color.reasi.warning
                        )
                    }
                    if !coreLoop.generationState.isGenerating,
                       let notice = coreLoop.generationState.noticeMessage {
                        generationFeedback(
                            notice,
                            symbol: "xmark.circle.fill",
                            color: Color.reasi.textMuted
                        )
                    }
                    if coreLoop.generationState.isGenerating && !coreLoop.hasPlan {
                        loadingSections
                    } else if !coreLoop.hasPlan {
                        emptyListState
                    } else {
                        if coreLoop.generationState.isGenerating {
                            generationProgressCard
                        }
                        progressView
                        addItemSurface

                        if coreLoop.isSwitchingStore {
                            storeSwitchLoading
                        }

                        if inputIsBusy {
                            inputLoadingCard
                        }

                        if let inlineError {
                            Text(inlineError)
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.warning)
                                .padding(ReasiSpacing.s4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
                        }


                        if let storeSwitchMessage = coreLoop.storeSwitchMessage {
                            VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                                Label(storeSwitchMessage, systemImage: "exclamationmark.triangle")
                                    .font(ReasiTypography.caption)
                                    .foregroundStyle(Color.reasi.warning)

                                if let failedStore = coreLoop.failedStoreSwitch {
                                    Button("Try \(failedStore.shortName) again") {
                                        coreLoop.requestStoreSwitch(
                                            to: failedStore,
                                            appState: appState,
                                            supabase: supabase,
                                            analytics: analytics,
                                            completion: syncConfirmedStore
                                        )
                                    }
                                    .buttonStyle(ReasiPrimaryButtonStyle())
                                }
                            }
                            .padding(ReasiSpacing.s4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
                        }

                        if coreLoop.plan.storeId != appState.selectedStore.id {
                            storeRouteUnavailableState
                        }

                        if coreLoop.plan.shoppingList.sections.isEmpty {
                            emptyShoppingItemsState
                        } else {
                            sections
                        }
                    }
                }
                .padding(.top, ReasiSpacing.s8)
                .padding(.bottom, 132)
            }
            .contentMargins(.horizontal, ReasiSpacing.s5, for: .scrollContent)

            if coreLoop.hasPlan {
                assistantButton
            }
        }
        .background(Color.reasi.background)
        .onAppear(perform: updateIdleTimer)
        .onChange(of: userSettings.keepScreenAwake) { _, _ in updateIdleTimer() }
        .onChange(of: coreLoop.hasPlan) { _, _ in updateIdleTimer() }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Add item", isPresented: $showAddDialog, titleVisibility: .visible) {
            Button("Search or paste product link") {
                productSearchContext = ProductSearchContext(
                    targetItemID: nil,
                    targetItemName: nil,
                    initialQuery: ""
                )
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take product photo") {
                    showProductCamera = true
                }
                Button("Take handwritten list photo") {
                    showListCamera = true
                }
            }
            Button("Choose product photo") {
                showProductPhotoPicker = true
            }
            Button("Choose handwritten list photo") {
                showListPhotoPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showProductCamera) {
            CameraCaptureView { image in
                showProductCamera = false
                guard let data = image?.jpegData(compressionQuality: 0.86) else { return }
                Task { await resolveProductImageData(data) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showListCamera) {
            CameraCaptureView { image in
                showListCamera = false
                guard let data = image?.jpegData(compressionQuality: 0.86) else { return }
                Task { await extractListImageData(data) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $productSearchContext) { context in
            ProductSearchView(
                context: context,
                store: FixtureStores.store(id: coreLoop.plan.storeId) ?? appState.selectedStore,
                recentCandidates: recentProductCandidates,
                searchProducts: { query in
                    try await searchCatalog(query)
                },
                importProductLink: { url in
                    try await importProductLink(url)
                },
                resolveBarcode: { barcode in
                    try await lookupBarcode(barcode)
                },
                addCandidate: { candidate, actualPriceAud in
                    await addSearchCandidate(
                        candidate,
                        actualPriceAud: actualPriceAud,
                        targetItemID: context.targetItemID
                    )
                },
                addManualItem: { text in
                    await addManualItem(text)
                }
            )
        }
        .photosPicker(isPresented: $showProductPhotoPicker, selection: $selectedProductPhoto, matching: .images)
        .photosPicker(isPresented: $showListPhotoPicker, selection: $selectedListPhoto, matching: .images)
        .onChange(of: selectedProductPhoto) { _, item in
            guard let item else { return }
            Task { await resolveProductPhoto(item) }
        }
        .onChange(of: selectedListPhoto) { _, item in
            guard let item else { return }
            Task { await extractListPhoto(item) }
        }
        .onChange(of: appState.shoppingListAddRequest) { _, _ in
            guard coreLoop.hasPlan, !inputIsBusy else { return }
            showAddDialog = true
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .textImport(let targetItemID, let initialQuery):
                ProductTextImportSheet(
                    initialText: initialQuery,
                    title: targetItemID == nil ? "Add item" : "Choose product",
                    allowsManualAdd: targetItemID == nil,
                    onAddManual: { text in
                        await addManualItem(text)
                    }
                ) { text in
                    await resolveTextInput(text, targetItemID: targetItemID)
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            case .review(let context):
                CandidateReviewSheet(
                    context: context,
                    onAdd: { row, actualPriceAud in
                        await addReviewed(row, actualPriceAud: actualPriceAud, context: context)
                    },
                    onCompare: { rows in
                        await compare(rows)
                    },
                    onDiscard: { method, confidence in
                        analytics.capture(.productCandidateDiscarded, properties: [
                            "method": .string(method),
                            "confidence": .string(confidence.rawValue)
                        ])
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .comparison(let result):
                ProductComparisonSheet(result: result)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .assistant:
                ShoppingAssistantSheet(
                    shoppingList: coreLoop.plan.shoppingList,
                    checkedItemIDs: coreLoop.checkedItemIDs,
                    supabase: supabase,
                    analytics: analytics
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .task {
            guard !didTrackView else { return }
            didTrackView = true
            coreLoop.markShoppingListViewed(analytics: analytics)
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = userSettings.keepScreenAwake && coreLoop.hasPlan
    }

    private var displayedStore: StoreSummary {
        guard coreLoop.hasPlan else { return appState.selectedStore }
        return FixtureStores.store(id: coreLoop.plan.shoppingList.storeId) ?? appState.selectedStore
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
            Text("Shopping list")
                .font(ReasiTypography.largeTitle)
                .foregroundStyle(Color.reasi.text)
            Menu {
                ForEach(FixtureStores.launchStores) { store in
                    Button {
                        selectStore(store)
                    } label: {
                        if store.id == displayedStore.id {
                            Label(store.name, systemImage: "checkmark")
                        } else {
                            Text(store.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: ReasiSpacing.s2) {
                    if coreLoop.isSwitchingStore {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.reasi.textMuted)
                    } else {
                        Image(systemName: "storefront")
                    }
                    Text(displayedStore.name)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.muted)
            }
            .accessibilityLabel("Choose shopping store")
        }
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            HStack {
                Text("\(coreLoop.checkedCount) of \(coreLoop.allShoppingItems.count) checked")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
                Spacer()
                Text("\(Int(coreLoop.shoppingProgress * 100))%")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.reasi.surfaceHigh)
                    Capsule()
                        .fill(Color.reasi.text)
                        .frame(width: proxy.size.width * coreLoop.shoppingProgress)
                        .animation(ReasiMotion.tactileSpring, value: coreLoop.shoppingProgress)
                }
            }
            .frame(height: 8)
        }
        .padding(ReasiSpacing.s5)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                .stroke(Color.reasi.border, lineWidth: 1)
        }
    }

    private func selectStore(_ store: StoreSummary) {
        guard store.id != displayedStore.id || store.id != appState.selectedStore.id else { return }
        ReasiHaptics.selection()
        analytics.capture(.storeSelected, properties: [
            "store_id": .string(store.id.rawValue),
            "store_name": .string(store.name)
        ])
        coreLoop.requestStoreSwitch(
            to: store,
            appState: appState,
            supabase: supabase,
            analytics: analytics,
            completion: syncConfirmedStore
        )
    }

    private var addItemSurface: some View {
        Button {
            ReasiHaptics.light()
            showAddDialog = true
        } label: {
            HStack(spacing: ReasiSpacing.s3) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add item")
                        .font(ReasiTypography.bodyMedium)
                    Text("Search, scan, or photograph")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.reasi.dim)
            }
            .foregroundStyle(Color.reasi.text)
            .padding(ReasiSpacing.s4)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                    .stroke(Color.reasi.border, lineWidth: 1)
            }
        }
        .buttonStyle(ReasiPressStyle())
        .disabled(inputIsBusy)
        .opacity(inputIsBusy ? 0.62 : 1)
    }

    private var inputLoadingCard: some View {
        HStack(spacing: ReasiSpacing.s3) {
            ProgressView()
                .tint(Color.reasi.text)
            VStack(alignment: .leading, spacing: 3) {
                Text("Checking product data")
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                Text("This can take a moment when Reasi is checking sources and freshness.")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.textMuted)
            }
        }
        .padding(ReasiSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }

    private var storeSwitchLoading: some View {
        HStack(spacing: ReasiSpacing.s3) {
            ProgressView()
                .tint(Color.reasi.text)
            VStack(alignment: .leading, spacing: 3) {
                Text("Updating item locations")
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                Text("Still showing \(displayedStore.shortName) until \(coreLoop.switchingStoreName ?? "the new route") is ready.")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.textMuted)
            }
        }
        .padding(ReasiSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }

    private var storeRouteUnavailableState: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            Text("This list is arranged for \(displayedStore.shortName)")
                .font(ReasiTypography.headline)
                .foregroundStyle(Color.reasi.text)
            Text("Your preferred store is \(appState.selectedStore.shortName). Update the route when you're ready.")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
            Button("Update to \(appState.selectedStore.shortName)") {
                coreLoop.requestStoreSwitch(
                    to: appState.selectedStore,
                    appState: appState,
                    supabase: supabase,
                    analytics: analytics,
                    completion: syncConfirmedStore
                )
            }
            .buttonStyle(ReasiPrimaryButtonStyle())
        }
        .padding(ReasiSpacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
    }

    private func syncConfirmedStore(_: Bool, _ store: StoreSummary) {
        onboarding.applyConfirmedStore(store)
    }

    private var emptyListState: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.reasi.textMuted)
            Text("No shopping list yet")
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)
            Text("A grouped list appears after your week is generated.")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)

            Button {
                Task {
                    coreLoop.startWeekPlanGeneration(
                        store: appState.selectedStore,
                        supabase: supabase,
                        analytics: analytics,
                        appState: appState,
                        network: network
                    )
                }
            } label: {
                Label("Plan my week", systemImage: "sparkles")
            }
            .buttonStyle(ReasiPrimaryButtonStyle())
        }
        .padding(ReasiSpacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
    }

    private var emptyShoppingItemsState: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            Text("This list is empty")
                .font(ReasiTypography.headline)
                .foregroundStyle(Color.reasi.text)
            Text("You can add an item above, or generate another week.")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
        }
        .padding(ReasiSpacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
    }

    private var assistantButton: some View {
        Button {
            ReasiHaptics.light()
            analytics.capture(.shoppingAssistantOpened, properties: [
                "shopping_list_id": .string(coreLoop.plan.shoppingList.id),
                "item_count": .int(coreLoop.allShoppingItems.count)
            ])
            activeSheet = .assistant
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.reasi.text)
                .frame(width: 58, height: 58)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(Color.reasi.borderStrong, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
        }
        .buttonStyle(ReasiPressStyle())
        .padding(.trailing, ReasiSpacing.s5)
        .padding(.bottom, 92)
        .accessibilityLabel("Open shopping assistant")
    }

    private var loadingSections: some View {
        VStack(spacing: ReasiSpacing.s4) {
            generationProgressCard
            ForEach(0..<4, id: \.self) { _ in
                VStack(spacing: ReasiSpacing.s3) {
                    SkeletonBlock(height: 18, radius: 9)
                    SkeletonBlock(height: 56, radius: ReasiRadius.md)
                    SkeletonBlock(height: 56, radius: ReasiRadius.md)
                }
                .padding(ReasiSpacing.s4)
                .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
            }
        }
    }

    private var generationProgressCard: some View {
        GenerationProgressCard(
            stage: coreLoop.generationStage,
            elapsedSeconds: coreLoop.generationElapsedSeconds,
            isCancelling: coreLoop.generationState.isCancelling,
            cancel: {
                coreLoop.cancelGeneration(
                    supabase: supabase,
                    analytics: analytics,
                    appState: appState
                )
            }
        )
    }

    private func generationFeedback(_ message: String, symbol: String, color: Color) -> some View {
        Label(message, systemImage: symbol)
            .font(ReasiTypography.callout)
            .foregroundStyle(color)
            .padding(ReasiSpacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.reasi.surface,
                in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous)
            )
    }

    private var sections: some View {
        VStack(spacing: ReasiSpacing.s4) {
            if userSettings.hideCompletedItems, coreLoop.checkedCount > 0 {
                Button {
                    userSettings.setHideCompletedItems(false)
                    ReasiHaptics.selection()
                    analytics.capture(.settingsUpdated, properties: [
                        "setting": .string("hide_completed_items"),
                        "enabled": .bool(false),
                        "source": .string("shopping_list")
                    ])
                } label: {
                    HStack(spacing: ReasiSpacing.s3) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.reasi.success)
                        Text("\(coreLoop.checkedCount) bought item\(coreLoop.checkedCount == 1 ? "" : "s") hidden")
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.textMuted)
                        Spacer()
                        Text("Show")
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.text)
                    }
                    .padding(ReasiSpacing.s4)
                    .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
                }
                .buttonStyle(ReasiPressStyle())
            }

            ForEach(visibleShoppingSections) { section in
                ShoppingSectionCard(
                    section: section,
                    checkedItemIDs: coreLoop.checkedItemIDs,
                    toggle: { item in
                        coreLoop.toggleItem(item, supabase: supabase, analytics: analytics)
                    },
                    chooseProduct: { item in
                        productSearchContext = ProductSearchContext(
                            targetItemID: item.id,
                            targetItemName: item.name,
                            initialQuery: item.name
                        )
                    },
                    scanBarcode: { item in
                        productSearchContext = ProductSearchContext(
                            targetItemID: item.id,
                            targetItemName: item.name,
                            initialQuery: "",
                            startsWithScanner: true
                        )
                    }
                )
            }
        }
    }

    private var visibleShoppingSections: [ShoppingListSection] {
        guard userSettings.hideCompletedItems else {
            return coreLoop.plan.shoppingList.sections
        }

        return coreLoop.plan.shoppingList.sections.compactMap { section in
            let visibleItems = section.items.filter { !coreLoop.checkedItemIDs.contains($0.id) }
            guard !visibleItems.isEmpty else { return nil }
            return ShoppingListSection(
                label: section.label,
                sortKey: section.sortKey,
                type: section.type,
                items: visibleItems
            )
        }
    }

    private func resolveTextInput(_ text: String, targetItemID: String?) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let isLink = URL(string: trimmed)?.scheme?.hasPrefix("http") == true
        let method = isLink ? "link" : "search"
        inlineError = nil
        inputIsBusy = true
        defer { inputIsBusy = false }
        ReasiHaptics.light()
        analytics.capture(.productInputStarted, properties: ["method": .string(method)])

        do {
            let result = try await supabase.resolveProduct(
                input: ResolveProductInput(
                    method: method,
                    storeId: coreLoop.plan.storeId,
                    query: isLink ? nil : trimmed,
                    url: isLink ? trimmed : nil,
                    uploadPath: nil
                )
            )
            analytics.capture(.productInputSucceeded, properties: [
                "method": .string(method),
                "candidate_count": .int(result.candidates.count)
            ])
            activeSheet = .review(
                ReviewContext(
                    method: method,
                    rows: result.candidates.map { ReviewCandidateRow(candidate: $0) },
                    targetItemID: targetItemID
                )
            )
        } catch {
            inlineError = supabase.userFacingMessage(
                for: error,
                fallback: "That product could not be checked just now. Please try again."
            )
            analytics.capture(.productInputFailed, properties: [
                "method": .string(method),
                "error": .string(error.localizedDescription)
            ])
            ReasiHaptics.warning()
        }
    }

    private var recentProductCandidates: [ProductCandidate] {
        var seen = Set<String>()
        return coreLoop.allShoppingItems.reversed().compactMap { item in
            guard item.clientId != nil,
                  let candidate = item.importedCandidate ?? restoredCandidate(from: item),
                  seen.insert(candidate.id).inserted else { return nil }
            return candidate
        }
    }

    private func restoredCandidate(from item: ShoppingListItem) -> ProductCandidate? {
        guard let product = item.product,
              let name = product.productName,
              !name.isEmpty else { return nil }

        return ProductCandidate(
            observationId: product.observationId,
            name: name,
            brand: product.brand,
            size: product.size,
            priceAud: product.actualPriceAud ?? product.priceAud,
            unitPriceAud: nil,
            unitQuantity: nil,
            unitMeasure: nil,
            comparablePrice: nil,
            imageUrl: product.imageUrl,
            productUrl: nil,
            sourceName: product.sourceName ?? "Saved product",
            sourceUrl: nil,
            capturedAt: product.capturedAt,
            freshnessLabel: "Previously selected",
            confidence: .medium,
            confidenceReason: "Restored from your saved shopping list.",
            uncertaintyText: "Search again if you need to confirm the current price.",
            sku: product.sku,
            barcode: product.barcode,
            retailer: nil,
            aisleLabel: item.aisleLabel,
            sectionLabel: nil,
            sectionSortKey: nil,
            sectionType: item.sectionType
        )
    }

    private func searchCatalog(_ query: String) async throws -> [ProductCandidate] {
        analytics.capture(.productInputStarted, properties: [
            "method": .string("search"),
            "store_id": .string(coreLoop.plan.storeId.rawValue)
        ])
        do {
            let candidates = try await supabase.searchProducts(
                query: query,
                storeId: coreLoop.plan.storeId
            )
            analytics.capture(.productInputSucceeded, properties: [
                "method": .string("search"),
                "candidate_count": .int(candidates.count),
                "store_id": .string(coreLoop.plan.storeId.rawValue)
            ])
            return candidates
        } catch {
            analytics.capture(.productInputFailed, properties: [
                "method": .string("search"),
                "error": .string(error.localizedDescription)
            ])
            throw error
        }
    }

    private func importProductLink(_ url: String) async throws -> [ProductCandidate] {
        analytics.capture(.productInputStarted, properties: ["method": .string("link")])
        do {
            let result = try await supabase.resolveProduct(
                input: ResolveProductInput(
                    method: "link",
                    storeId: coreLoop.plan.storeId,
                    query: nil,
                    url: url,
                    uploadPath: nil
                )
            )
            analytics.capture(.productInputSucceeded, properties: [
                "method": .string("link"),
                "candidate_count": .int(result.candidates.count)
            ])
            return result.candidates
        } catch {
            analytics.capture(.productInputFailed, properties: [
                "method": .string("link"),
                "error": .string(error.localizedDescription)
            ])
            throw error
        }
    }

    private func lookupBarcode(_ barcode: String) async throws -> [ProductCandidate] {
        analytics.capture(.productInputStarted, properties: ["method": .string("barcode")])
        do {
            let result = try await supabase.resolveProduct(
                input: ResolveProductInput(
                    method: "barcode",
                    storeId: coreLoop.plan.storeId,
                    query: nil,
                    url: nil,
                    uploadPath: nil,
                    barcode: barcode
                )
            )
            analytics.capture(.productInputSucceeded, properties: [
                "method": .string("barcode"),
                "candidate_count": .int(result.candidates.count)
            ])
            return result.candidates
        } catch {
            analytics.capture(.productInputFailed, properties: [
                "method": .string("barcode"),
                "error": .string(error.localizedDescription)
            ])
            throw error
        }
    }

    private func addSearchCandidate(
        _ candidate: ProductCandidate,
        actualPriceAud: Double?,
        targetItemID: String?
    ) async -> Bool {
        if let targetItemID,
           let item = coreLoop.allShoppingItems.first(where: { $0.id == targetItemID }) {
            do {
                try await coreLoop.selectProduct(
                    candidate,
                    for: item,
                    actualPriceAud: actualPriceAud,
                    supabase: supabase,
                    analytics: analytics
                )
                return true
            } catch {
                inlineError = supabase.userFacingMessage(
                    for: error,
                    fallback: "That product could not be attached to this item. Please try again."
                )
                ReasiHaptics.warning()
                return false
            }
        }

        return await coreLoop.addImportedCandidate(
            candidate,
            idempotencyKey: UUID().uuidString,
            analyticsMethod: "search",
            supabase: supabase,
            analytics: analytics
        )
    }

    private func addManualItem(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        analytics.capture(.productInputStarted, properties: ["method": .string("manual")])
        let candidate = ProductCandidate(
            observationId: nil,
            name: trimmed,
            brand: nil,
            size: nil,
            priceAud: nil,
            unitPriceAud: nil,
            unitQuantity: nil,
            unitMeasure: nil,
            comparablePrice: nil,
            imageUrl: nil,
            productUrl: nil,
            sourceName: "Manual entry",
            sourceUrl: nil,
            capturedAt: nil,
            freshnessLabel: "Added now",
            confidence: .low,
            confidenceReason: "Added exactly as written; no specific product has been selected yet.",
            uncertaintyText: "Search or scan a product when you pick it up to record the exact item and price."
        )
        let added = await coreLoop.addImportedCandidate(
            candidate,
            idempotencyKey: UUID().uuidString,
            analyticsMethod: "manual",
            supabase: supabase,
            analytics: analytics
        )
        analytics.capture(
            added ? .productInputSucceeded : .productInputFailed,
            properties: ["method": .string("manual")]
        )
        return added
    }

    private func resolveBarcode(_ barcode: String, for item: ShoppingListItem) async {
        inlineError = nil
        inputIsBusy = true
        defer { inputIsBusy = false }
        analytics.capture(.productInputStarted, properties: ["method": .string("barcode")])

        do {
            let result = try await supabase.resolveProduct(
                input: ResolveProductInput(
                    method: "barcode",
                    storeId: appState.selectedStore.id,
                    query: nil,
                    url: nil,
                    uploadPath: nil,
                    barcode: barcode
                )
            )
            analytics.capture(.productInputSucceeded, properties: [
                "method": .string("barcode"),
                "candidate_count": .int(result.candidates.count)
            ])
            activeSheet = .review(
                ReviewContext(
                    method: "barcode",
                    rows: result.candidates.map { ReviewCandidateRow(candidate: $0) },
                    targetItemID: item.id
                )
            )
        } catch {
            inlineError = supabase.userFacingMessage(
                for: error,
                fallback: "That barcode could not be matched. Try searching by the product name."
            )
            analytics.capture(.productInputFailed, properties: [
                "method": .string("barcode"),
                "error": .string(error.localizedDescription)
            ])
            ReasiHaptics.warning()
        }
    }

    private func resolveProductPhoto(_ item: PhotosPickerItem) async {
        await withImageData(from: item, method: "product_photo") { data in
            try await resolveProductImageSheet(data)
        }
    }

    private func extractListPhoto(_ item: PhotosPickerItem) async {
        await withImageData(from: item, method: "list_photo") { data in
            try await extractListImageSheet(data)
        }
    }

    private func resolveProductImageData(_ data: Data) async {
        await withPreparedImageData(data, method: "product_photo") { data in
            try await resolveProductImageSheet(data)
        }
    }

    private func extractListImageData(_ data: Data) async {
        await withPreparedImageData(data, method: "list_photo") { data in
            try await extractListImageSheet(data)
        }
    }

    private func resolveProductImageSheet(_ data: Data) async throws -> ShoppingListSheet {
        let uploadPath = try await supabase.uploadUserImage(data, kind: .productPhoto)
        let result = try await supabase.resolveProduct(
            input: ResolveProductInput(
                method: "product_photo",
                storeId: coreLoop.plan.storeId,
                query: nil,
                url: nil,
                uploadPath: uploadPath
            )
        )
        return .review(ReviewContext(method: "product_photo", rows: result.candidates.map { ReviewCandidateRow(candidate: $0) }))
    }

    private func extractListImageSheet(_ data: Data) async throws -> ShoppingListSheet {
        let uploadPath = try await supabase.uploadUserImage(data, kind: .shoppingListPhoto)
        let result = try await supabase.extractShoppingListPhoto(storeId: coreLoop.plan.storeId, uploadPath: uploadPath)
        analytics.capture(.shoppingListPhotoExtracted, properties: [
            "candidate_count": .int(result.items.count),
            "matched_count": .int(result.matched.count),
            "uncertain_count": .int(result.uncertain.count)
        ])
        let rows = result.items.map { item in
            ReviewCandidateRow(
                candidate: item.productCandidate ?? ProductCandidate(
                    observationId: nil,
                    name: item.extractedName,
                    brand: nil,
                    size: nil,
                    priceAud: nil,
                    unitPriceAud: nil,
                    unitQuantity: nil,
                    unitMeasure: nil,
                    comparablePrice: nil,
                    imageUrl: nil,
                    productUrl: nil,
                    sourceName: "Handwritten list",
                    sourceUrl: nil,
                    capturedAt: nil,
                    freshnessLabel: "Freshness unknown",
                    confidence: item.confidence,
                    confidenceReason: item.confidenceReason,
                    uncertaintyText: "I'm not certain of the current price for this."
                ),
                quantity: item.quantity ?? "1",
                group: item.group.rawValue
            )
        }
        return .review(ReviewContext(method: "list_photo", rows: rows))
    }

    private func withImageData(
        from item: PhotosPickerItem,
        method: String,
        work: (Data) async throws -> ShoppingListSheet
    ) async {
        inlineError = nil
        inputIsBusy = true
        defer { inputIsBusy = false }
        ReasiHaptics.light()
        analytics.capture(.productInputStarted, properties: ["method": .string(method)])

        do {
            guard let rawData = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: rawData),
                  let data = image.jpegData(compressionQuality: 0.86)
            else {
                throw ShoppingListFeatureError.invalidImage
            }

            let sheet = try await work(data)
            let candidateCount: Int
            if case .review(let context) = sheet {
                candidateCount = context.rows.count
            } else {
                candidateCount = 0
            }
            analytics.capture(.productInputSucceeded, properties: [
                "method": .string(method),
                "candidate_count": .int(candidateCount)
            ])
            activeSheet = sheet
        } catch {
            inlineError = supabase.userFacingMessage(
                for: error,
                fallback: "That photo could not be checked just now. Please try again."
            )
            analytics.capture(.productInputFailed, properties: [
                "method": .string(method),
                "error": .string(error.localizedDescription)
            ])
            ReasiHaptics.warning()
        }
    }

    private func withPreparedImageData(
        _ data: Data,
        method: String,
        work: (Data) async throws -> ShoppingListSheet
    ) async {
        inlineError = nil
        inputIsBusy = true
        defer { inputIsBusy = false }
        ReasiHaptics.light()
        analytics.capture(.productInputStarted, properties: ["method": .string(method)])

        do {
            let sheet = try await work(data)
            let candidateCount: Int
            if case .review(let context) = sheet {
                candidateCount = context.rows.count
            } else {
                candidateCount = 0
            }
            analytics.capture(.productInputSucceeded, properties: [
                "method": .string(method),
                "candidate_count": .int(candidateCount)
            ])
            activeSheet = sheet
        } catch {
            inlineError = supabase.userFacingMessage(
                for: error,
                fallback: "That photo could not be checked just now. Please try again."
            )
            analytics.capture(.productInputFailed, properties: [
                "method": .string(method),
                "error": .string(error.localizedDescription)
            ])
            ReasiHaptics.warning()
        }
    }

    private func addReviewed(
        _ row: ReviewCandidateRow,
        actualPriceAud: Double?,
        context: ReviewContext
    ) async -> Bool {
        analytics.capture(.productCandidateReviewed, properties: [
            "method": .string(row.group ?? "candidate"),
            "confidence": .string(row.candidate.confidence.rawValue)
        ])

        if let targetItemID = context.targetItemID,
           let item = coreLoop.allShoppingItems.first(where: { $0.id == targetItemID }) {
            do {
                try await coreLoop.selectProduct(
                    row.candidate,
                    for: item,
                    actualPriceAud: actualPriceAud,
                    supabase: supabase,
                    analytics: analytics
                )
                return true
            } catch {
                inlineError = supabase.userFacingMessage(
                    for: error,
                    fallback: "That product could not be attached to this item. Please try again."
                )
                ReasiHaptics.warning()
                return false
            }
        }

        return await coreLoop.addImportedCandidate(
            row.candidate,
            quantity: row.quantity,
            idempotencyKey: row.id,
            supabase: supabase,
            analytics: analytics
        )
    }

    private func compare(_ rows: [ReviewCandidateRow]) async {
        let ids = rows.compactMap(\.candidate.observationId)
        guard ids.count >= 2 else {
            inlineError = "Choose at least two sourced products to compare."
            ReasiHaptics.warning()
            return
        }

        analytics.capture(.productComparisonStarted, properties: ["candidate_count": .int(ids.count)])

        do {
            let result = try await supabase.compareProducts(observationIds: ids)
            analytics.capture(.productComparisonViewed, properties: [
                "candidate_count": .int(result.rows.count),
                "has_best_unit_value": .bool(result.bestUnitValueObservationId != nil)
            ])
            activeSheet = .comparison(result)
        } catch {
            inlineError = supabase.userFacingMessage(
                for: error,
                fallback: "Those products could not be compared just now. Please try again."
            )
            ReasiHaptics.warning()
        }
    }
}

private enum ShoppingListSheet: Identifiable {
    case textImport(targetItemID: String?, initialQuery: String)
    case review(ReviewContext)
    case comparison(ProductComparisonResult)
    case assistant

    var id: String {
        switch self {
        case .textImport(let targetItemID, _):
            "textImport-\(targetItemID ?? "new")"
        case .review(let context):
            context.id
        case .comparison:
            "comparison"
        case .assistant:
            "assistant"
        }
    }
}

private struct ReviewContext: Identifiable, Hashable {
    let id = UUID().uuidString
    let method: String
    let rows: [ReviewCandidateRow]
    var targetItemID: String? = nil
}

private struct ReviewCandidateRow: Identifiable, Hashable {
    let id = UUID().uuidString
    let candidate: ProductCandidate
    var quantity: String = "1"
    var group: String? = nil
}

private enum ShoppingListFeatureError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "I could not read that image. Try a clearer photo."
        }
    }
}

private struct ProductTextImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isLoading = false
    @State private var isAddingManual = false
    let title: String
    let allowsManualAdd: Bool
    let onAddManual: (String) async -> Bool
    let onSubmit: (String) async -> Void

    init(
        initialText: String,
        title: String,
        allowsManualAdd: Bool,
        onAddManual: @escaping (String) async -> Bool,
        onSubmit: @escaping (String) async -> Void
    ) {
        _text = State(initialValue: initialText)
        self.title = title
        self.allowsManualAdd = allowsManualAdd
        self.onAddManual = onAddManual
        self.onSubmit = onSubmit
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ReasiSpacing.s5) {
                Text("Paste a product link or search by name.")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.muted)

                TextField("Greek yoghurt, milk, coles.com.au/...", text: $text, axis: .vertical)
                    .font(ReasiTypography.body)
                    .foregroundStyle(Color.reasi.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(ReasiSpacing.s4)
                    .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))

                Button {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    isLoading = true
                    Task {
                        await onSubmit(text)
                        isLoading = false
                    }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                        }
                        Text(isLoading ? "Checking..." : "Find product")
                            .font(ReasiTypography.bodyMedium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ReasiSpacing.s4)
                    .foregroundStyle(Color.reasi.background)
                    .background(Color.reasi.text, in: Capsule())
                }
                .disabled(isLoading || isAddingManual)
                .buttonStyle(ReasiPressStyle())

                if allowsManualAdd {
                    Button {
                        guard !trimmedText.isEmpty, !isLink else { return }
                        isAddingManual = true
                        Task {
                            let added = await onAddManual(trimmedText)
                            isAddingManual = false
                            if added { dismiss() }
                        }
                    } label: {
                        HStack {
                            if isAddingManual {
                                ProgressView()
                                    .tint(Color.reasi.text)
                            } else {
                                Image(systemName: "plus")
                            }
                            Text(isAddingManual ? "Adding..." : "Add as written")
                                .font(ReasiTypography.bodyMedium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ReasiSpacing.s4)
                        .foregroundStyle(Color.reasi.text)
                        .overlay {
                            Capsule().stroke(Color.reasi.border, lineWidth: 1)
                        }
                    }
                    .disabled(isLoading || isAddingManual || trimmedText.isEmpty || isLink)
                    .buttonStyle(ReasiPressStyle())
                }

                Spacer()
            }
            .padding(ReasiSpacing.s5)
            .background(Color.reasi.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isLink: Bool {
        URL(string: trimmedText)?.scheme?.hasPrefix("http") == true
    }
}

private struct CandidateReviewSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    let context: ReviewContext
    let onAdd: (ReviewCandidateRow, Double?) async -> Bool
    let onCompare: ([ReviewCandidateRow]) async -> Void
    let onDiscard: (String, ProductConfidence) -> Void
    @State private var selectedIDs: Set<String> = []
    @State private var addedIDs: Set<String> = []
    @State private var discardedIDs: Set<String> = []
    @State private var addingID: String?
    @State private var isComparing = false

    var selectedRows: [ReviewCandidateRow] {
        context.rows.filter { selectedIDs.contains($0.id) && !discardedIDs.contains($0.id) }
    }

    var visibleRows: [ReviewCandidateRow] {
        context.rows.filter { !discardedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
                    Text(
                        context.targetItemID == nil
                            ? "Choose what to add. Source and freshness stay visible."
                            : "Choose the product you picked, then add the shelf price if it changed."
                    )
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.muted)

                    ForEach(visibleRows) { row in
                        CandidateReviewRow(
                            row: row,
                            isSelected: selectedIDs.contains(row.id),
                            isAdding: addingID == row.id,
                            isAdded: addedIDs.contains(row.id),
                            isFulfillingItem: context.targetItemID != nil,
                            toggleSelection: {
                                if selectedIDs.contains(row.id) {
                                    selectedIDs.remove(row.id)
                                } else {
                                    selectedIDs.insert(row.id)
                                }
                            },
                            add: { actualPriceAud in
                                guard !addedIDs.contains(row.id), addingID == nil else { return }
                                addingID = row.id
                                if await onAdd(row, actualPriceAud) {
                                    addedIDs.insert(row.id)
                                }
                                addingID = nil
                            },
                            discard: {
                                onDiscard(context.method, row.candidate.confidence)
                                selectedIDs.remove(row.id)
                                withAnimation(reduceMotion ? nil : ReasiMotion.fast) {
                                    _ = discardedIDs.insert(row.id)
                                }
                            }
                        )
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }

                    if visibleRows.isEmpty {
                        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(Color.reasi.textMuted)
                            Text("No products left to review")
                                .font(ReasiTypography.headline)
                                .foregroundStyle(Color.reasi.text)
                            Text("Close this screen to try another search or photo.")
                                .font(ReasiTypography.callout)
                                .foregroundStyle(Color.reasi.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(ReasiSpacing.s5)
                        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
                    }
                }
                .padding(ReasiSpacing.s5)
                .padding(.bottom, ReasiSpacing.s8)
            }
            .background(Color.reasi.background)
            .navigationTitle("Review items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        isComparing = true
                        Task {
                            await onCompare(selectedRows)
                            isComparing = false
                        }
                    } label: {
                        Label(isComparing ? "Comparing" : "Compare selected", systemImage: "arrow.left.arrow.right")
                    }
                    .disabled(selectedRows.compactMap(\.candidate.observationId).count < 2 || isComparing)
                }
            }
        }
    }
}

private struct CandidateReviewRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let row: ReviewCandidateRow
    let isSelected: Bool
    let isAdding: Bool
    let isAdded: Bool
    let isFulfillingItem: Bool
    let toggleSelection: () -> Void
    let add: (Double?) async -> Void
    let discard: () -> Void
    @State private var actualPriceText = ""
    @State private var showsSourceDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            HStack(alignment: .top, spacing: ReasiSpacing.s3) {
                Button(action: toggleSelection) {
                    CandidateProductArtwork(candidate: row.candidate)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.md, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.reasi.success : .white)
                                .background(.black.opacity(0.5), in: Circle())
                                .padding(6)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "Deselect \(row.candidate.displayName)" : "Select \(row.candidate.displayName)")

                VStack(alignment: .leading, spacing: 5) {
                    Text(row.candidate.displayName)
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                        .lineLimit(3)
                    if let size = row.candidate.size {
                        Text(size)
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.textMuted)
                    }

                    if let price = row.candidate.priceAud {
                        Text("$\(price, specifier: "%.2f")")
                            .font(ReasiTypography.bodyMedium)
                            .foregroundStyle(Color.reasi.text)
                    } else {
                        Label("Current price not certain", systemImage: "exclamationmark.triangle.fill")
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.warning)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: ReasiSpacing.s2) {
                ConfidenceBadge(confidence: row.candidate.confidence)
                Text("\(row.candidate.userFacingSourceName) · \(row.candidate.freshnessLabel)")
                    .lineLimit(1)
            }
            .font(ReasiTypography.caption)
            .foregroundStyle(Color.reasi.muted)

            if hasSourceDetails {
                Button {
                    withAnimation(reduceMotion ? nil : ReasiMotion.fast) {
                        showsSourceDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(showsSourceDetails ? "Hide source details" : "Source details")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(showsSourceDetails ? 180 : 0))
                    }
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.text)
                }
                .buttonStyle(ReasiPressStyle())

                if showsSourceDetails {
                    VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                        if !row.candidate.confidenceReason.isEmpty {
                            Text(row.candidate.confidenceReason.reasiUserFacingCopy)
                                .foregroundStyle(Color.reasi.textMuted)
                        }
                        if !row.candidate.uncertaintyText.isEmpty {
                            Text(row.candidate.uncertaintyText.reasiUserFacingCopy)
                                .foregroundStyle(Color.reasi.warning)
                        }
                    }
                    .font(ReasiTypography.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if isFulfillingItem {
                TextField("Shelf price (optional)", text: $actualPriceText)
                    .keyboardType(.decimalPad)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.text)
                    .padding(ReasiSpacing.s3)
                    .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.md, style: .continuous))
            }

            HStack {
                Button {
                    Task { await add(parsedActualPrice) }
                } label: {
                    Label(
                        isAdded
                            ? (isFulfillingItem ? "Selected" : "Added")
                            : isAdding
                                ? "Saving"
                                : (isFulfillingItem ? "Use & check" : "Add"),
                        systemImage: isAdded ? "checkmark" : (isFulfillingItem ? "barcode.viewfinder" : "plus")
                    )
                }
                .disabled(isAdding || isAdded)

                Button(role: .destructive) {
                    discard()
                } label: {
                    Label("Discard", systemImage: "xmark")
                }
            }
            .font(ReasiTypography.caption)
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                .stroke(Color.reasi.border, lineWidth: 1)
        }
    }

    private var parsedActualPrice: Double? {
        let normalized = actualPriceText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private var hasSourceDetails: Bool {
        !row.candidate.confidenceReason.isEmpty || !row.candidate.uncertaintyText.isEmpty
    }
}

private struct CandidateProductArtwork: View {
    let candidate: ProductCandidate

    var body: some View {
        ZStack {
            Color.reasi.surfaceHigh

            if let imageURL = candidate.imageUrl {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.reasi.textMuted)
                    case .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .clipped()
    }

    private var fallback: some View {
        Image(systemName: "basket")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(Color.reasi.textMuted)
    }
}

private struct ProductComparisonSheet: View {
    let result: ProductComparisonResult

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
                    ForEach(result.rows) { row in
                        VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                            HStack {
                                Text(row.name)
                                    .font(ReasiTypography.headline)
                                    .foregroundStyle(Color.reasi.text)
                                Spacer()
                                if result.bestUnitValueObservationId == row.observationId {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(Color.reasi.success)
                                }
                            }
                            Text(row.size ?? "Size not certain")
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.muted)
                            HStack {
                                Text(row.priceAud.map { String(format: "$%.2f", $0) } ?? "Current price not certain")
                                Spacer()
                                Text(row.unitValueText)
                            }
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.textMuted)
                            Text("\(row.userFacingSourceName) · \(row.freshnessLabel)")
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.muted)
                            Text(row.caveat.reasiUserFacingCopy)
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.warning)
                        }
                        .padding(ReasiSpacing.s4)
                        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
                    }

                    ForEach(result.caveats, id: \.self) { caveat in
                        Text(caveat.reasiUserFacingCopy)
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.muted)
                    }
                }
                .padding(ReasiSpacing.s5)
            }
            .background(Color.reasi.background)
            .navigationTitle("Compare products")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ShoppingAssistantSheet: View {
    let shoppingList: ShoppingList
    let checkedItemIDs: Set<String>
    let supabase: SupabaseService
    let analytics: AnalyticsService
    @State private var threadId: String?
    @State private var messages: [AssistantMessage] = [
        AssistantMessage(
            id: "assistant-welcome",
            role: .assistant,
            content: "What can I help you find or compare?",
            cards: [],
            caveats: [],
            createdAt: nil
        )
    ]
    @State private var draft = ""
    @State private var isSending = false

    private var shoppingListId: String { shoppingList.id }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                        ForEach(messages) { message in
                            AssistantMessageBubble(message: message)
                        }
                        if isSending {
                            HStack(spacing: ReasiSpacing.s2) {
                                ProgressView()
                                    .tint(Color.reasi.textMuted)
                                Text("Checking your list")
                                    .font(ReasiTypography.caption)
                                    .foregroundStyle(Color.reasi.textMuted)
                            }
                            .padding(ReasiSpacing.s4)
                            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
                            .transition(.opacity)
                        }
                    }
                    .padding(ReasiSpacing.s5)
                }

                HStack(spacing: ReasiSpacing.s3) {
                    TextField("Ask about your list", text: $draft, axis: .vertical)
                        .font(ReasiTypography.body)
                        .foregroundStyle(Color.reasi.text)
                        .lineLimit(1...4)
                        .padding(ReasiSpacing.s3)
                        .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))

                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: isSending ? "hourglass" : "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .foregroundStyle(Color.reasi.background)
                            .background(Color.reasi.text, in: Circle())
                    }
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(ReasiSpacing.s4)
                .background(Color.reasi.backgroundElevated)
            }
            .background(Color.reasi.background)
            .navigationTitle("Shopping assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        draft = ""
        isSending = true
        messages.append(
            AssistantMessage(
                id: UUID().uuidString,
                role: .user,
                content: text,
                cards: [],
                caveats: [],
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
        )
        analytics.capture(.shoppingAssistantMessageSent, properties: ["shopping_list_id": .string(shoppingListId)])

        do {
            let response = try await supabase.askShoppingAssistant(
                shoppingList: shoppingList,
                checkedItemIDs: checkedItemIDs,
                threadId: threadId,
                message: text
            )
            threadId = response.threadId
            messages.append(response.message)
            analytics.capture(.shoppingAssistantResponseReceived, properties: [
                "shopping_list_id": .string(shoppingListId),
                "has_cards": .bool(!response.message.cards.isEmpty)
            ])
            ReasiHaptics.selection()
        } catch {
            let message = supabase.userFacingMessage(
                for: error,
                fallback: "I couldn't answer that just now. Please try again."
            )
            messages.append(
                AssistantMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: "I couldn’t answer that. I won’t guess product facts without reliable data.",
                    cards: [],
                    caveats: [message],
                    createdAt: ISO8601DateFormatter().string(from: Date())
                )
            )
            analytics.capture(.shoppingAssistantFailed, properties: [
                "shopping_list_id": .string(shoppingListId),
                "error": .string(error.localizedDescription)
            ])
            ReasiHaptics.warning()
        }

        isSending = false
    }
}

private struct AssistantMessageBubble: View {
    let message: AssistantMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 52) }

            VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                Text(message.content.reasiUserFacingCopy)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.text)

                ForEach(message.caveats, id: \.self) { caveat in
                    Text(caveat.reasiUserFacingCopy)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.warning)
                }
            }
            .padding(ReasiSpacing.s4)
            .background(
                message.role == .user ? Color.reasi.surfaceHigh : Color.reasi.surface,
                in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
            )

            if message.role == .assistant { Spacer(minLength: 52) }
        }
    }
}

private struct ConfidenceBadge: View {
    let confidence: ProductConfidence

    var body: some View {
        Text(confidence.rawValue.capitalized)
            .font(ReasiTypography.caption)
            .foregroundStyle(confidence == .low ? Color.reasi.warning : Color.reasi.textMuted)
            .padding(.horizontal, ReasiSpacing.s2)
            .padding(.vertical, 3)
            .background(Color.reasi.surfaceHigh, in: Capsule())
    }
}

struct BarcodeScannerScreen: View {
    let itemName: String
    let onScanned: (String) -> Void
    let onCancel: () -> Void
    @State private var manualBarcode = ""

    var body: some View {
        ZStack {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                LiveBarcodeScanner(onScanned: onScanned)
                    .ignoresSafeArea()
            } else {
                Color.reasi.background.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scan product")
                            .font(ReasiTypography.title2)
                            .foregroundStyle(.white)
                        Text(itemName)
                            .font(ReasiTypography.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, ReasiSpacing.s5)
                .padding(.top, ReasiSpacing.s7)

                Spacer()

                RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 2)
                    .frame(height: 190)
                    .padding(.horizontal, ReasiSpacing.s7)
                    .overlay {
                        Text("Hold the barcode inside the frame")
                            .font(ReasiTypography.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, ReasiSpacing.s3)
                            .padding(.vertical, ReasiSpacing.s2)
                            .background(.black.opacity(0.58), in: Capsule())
                    }

                Spacer()

                VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                    if !DataScannerViewController.isSupported || !DataScannerViewController.isAvailable {
                        Text("Camera scanning is unavailable. You can enter the digits below.")
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.textMuted)
                    }
                    HStack(spacing: ReasiSpacing.s3) {
                        TextField("Barcode number", text: $manualBarcode)
                            .keyboardType(.numberPad)
                            .font(ReasiTypography.body)
                            .foregroundStyle(Color.reasi.text)
                            .padding(ReasiSpacing.s3)
                            .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.md, style: .continuous))

                        Button {
                            onScanned(normalizedManualBarcode)
                        } label: {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.reasi.background)
                                .frame(width: 44, height: 44)
                                .background(Color.reasi.text, in: Circle())
                        }
                        .disabled(!manualBarcodeIsValid)
                        .opacity(manualBarcodeIsValid ? 1 : 0.45)
                    }
                }
                .padding(ReasiSpacing.s5)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
                .padding(ReasiSpacing.s5)
            }
        }
        .background(Color.black)
    }

    private var normalizedManualBarcode: String {
        manualBarcode.filter(\.isNumber)
    }

    private var manualBarcodeIsValid: Bool {
        (8...14).contains(normalizedManualBarcode.count)
    }
}

private struct LiveBarcodeScanner: UIViewControllerRepresentable {
    let onScanned: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13, .ean8, .upce, .code128])
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScanned: (String) -> Void
        private var didScan = false

        init(onScanned: @escaping (String) -> Void) {
            self.onScanned = onScanned
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didScan else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue else { continue }
                let digits = payload.filter(\.isNumber)
                guard (8...14).contains(digits.count) else { continue }
                didScan = true
                dataScanner.stopScanning()
                ReasiHaptics.success()
                onScanned(digits)
                return
            }
        }
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onComplete: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onComplete: (UIImage?) -> Void

        init(onComplete: @escaping (UIImage?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onComplete(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }
    }
}

private struct ShoppingSectionCard: View {
    let section: ShoppingListSection
    let checkedItemIDs: Set<String>
    let toggle: (ShoppingListItem) -> Void
    let chooseProduct: (ShoppingListItem) -> Void
    let scanBarcode: (ShoppingListItem) -> Void

    var checkedCount: Int {
        section.items.filter { checkedItemIDs.contains($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.label)
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                    Text("\(checkedCount) of \(section.items.count) items")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                }
                Spacer()
                Image(systemName: sectionSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.reasi.dim)
                    .frame(width: 34, height: 34)
                    .background(Color.reasi.surfaceHigh, in: Circle())
            }

            VStack(spacing: ReasiSpacing.s2) {
                ForEach(section.items) { item in
                    HStack(spacing: ReasiSpacing.s3) {
                        Button {
                            toggle(item)
                        } label: {
                            HStack(spacing: ReasiSpacing.s3) {
                                Image(systemName: checkedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 23, weight: .semibold))
                                    .foregroundStyle(checkedItemIDs.contains(item.id) ? Color.reasi.success : Color.reasi.dim)
                                    .symbolEffect(.bounce, value: checkedItemIDs.contains(item.id))

                                ShoppingItemRow(item: item, isChecked: checkedItemIDs.contains(item.id))
                            }
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(checkedItemIDs.contains(item.id) ? "Uncheck \(item.name)" : "Check \(item.name)")
                        .accessibilityHint("Double-tap anywhere on this item to update it")

                        Menu {
                            Button {
                                chooseProduct(item)
                            } label: {
                                Label("Search exact product", systemImage: "magnifyingglass")
                            }
                            Button {
                                scanBarcode(item)
                            } label: {
                                Label("Scan barcode", systemImage: "barcode.viewfinder")
                            }
                            Button {
                                toggle(item)
                            } label: {
                                Label(
                                    checkedItemIDs.contains(item.id) ? "Mark not bought" : "Mark bought without product",
                                    systemImage: checkedItemIDs.contains(item.id) ? "arrow.uturn.backward" : "checkmark"
                                )
                            }
                        } label: {
                            Image(systemName: item.product?.sku != nil || item.product?.barcode != nil ? "checkmark.seal.fill" : "barcode.viewfinder")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(item.product?.sku != nil || item.product?.barcode != nil ? Color.reasi.success : Color.reasi.textMuted)
                                .frame(width: 44, height: 44)
                                .background(Color.reasi.surfaceHigh, in: Circle())
                        }
                        .accessibilityLabel("Product options for \(item.name)")
                    }
                    .padding(.vertical, ReasiSpacing.s1)
                    .padding(.horizontal, ReasiSpacing.s2)
                    .background(
                        checkedItemIDs.contains(item.id) ? Color.reasi.surfaceHigh.opacity(0.36) : Color.clear,
                        in: RoundedRectangle(cornerRadius: ReasiRadius.md, style: .continuous)
                    )
                }
            }
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                .stroke(Color.reasi.border, lineWidth: 1)
        }
    }

    private var sectionSymbol: String {
        switch section.type {
        case .numbered:
            "number"
        case .perimeter:
            "leaf"
        case .unknown:
            "questionmark"
        }
    }
}

private struct ShoppingItemRow: View {
    let item: ShoppingListItem
    let isChecked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(isChecked ? Color.reasi.muted : Color.reasi.text)
                    .strikethrough(isChecked, color: Color.reasi.muted)
                    .lineLimit(2)
                Text(detailText)
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
                    .lineLimit(1)
                if let imported = item.importedCandidate {
                    Text("\(imported.confidence.label) · \(imported.userFacingSourceName) · \(imported.freshnessLabel)")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(imported.confidence == .low ? Color.reasi.warning : Color.reasi.dim)
                        .lineLimit(2)
                }
                if let productName = item.product?.productName,
                   productName.localizedCaseInsensitiveCompare(item.name) != .orderedSame {
                    Text(productName)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.textMuted)
                        .lineLimit(1)
                }
                if let price = item.product?.actualPriceAud ?? item.product?.priceAud {
                    Text("$\(price, specifier: "%.2f")\(item.product?.actualPriceAud == nil ? " catalog" : " paid")")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.textMuted)
                }
            }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(ReasiMotion.fast, value: isChecked)
    }

    private var detailText: String {
        "\(item.quantity) · \(locationLabel)"
    }

    private var locationLabel: String {
        guard let aisleLabel = item.aisleLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !aisleLabel.isEmpty else {
            return "Location not certain"
        }
        return aisleLabel
    }
}

#Preview {
    ShoppingListPlaceholderView()
        .environment(AppState())
        .environment(CoreLoopStore())
        .environment(SupabaseService())
        .environment(AnalyticsService())
        .environment(NetworkMonitor())
        .environment(UserSettingsStore())
        .preferredColorScheme(.dark)
}
