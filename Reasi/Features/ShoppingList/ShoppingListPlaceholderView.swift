import PhotosUI
import SwiftUI
import UIKit

struct ShoppingListPlaceholderView: View {
    @Environment(AppState.self) private var appState
    @Environment(CoreLoopStore.self) private var coreLoop
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(NetworkMonitor.self) private var network

    @State private var didTrackView = false
    @State private var showAddDialog = false
    @State private var showProductPhotoPicker = false
    @State private var showListPhotoPicker = false
    @State private var showProductCamera = false
    @State private var showListCamera = false
    @State private var selectedProductPhoto: PhotosPickerItem?
    @State private var selectedListPhoto: PhotosPickerItem?
    @State private var activeSheet: ShoppingListSheet?
    @State private var inlineError: String?
    @State private var inputIsBusy = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                    header
                    if coreLoop.generationState.isGenerating {
                        loadingSections
                    } else if !coreLoop.hasPlan {
                        emptyListState
                    } else {
                        progressView
                        addItemSurface

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
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Add item", isPresented: $showAddDialog, titleVisibility: .visible) {
            Button("Search or paste product link") {
                activeSheet = .textImport
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .textImport:
                ProductTextImportSheet { text in
                    await resolveTextInput(text)
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            case .review(let context):
                CandidateReviewSheet(
                    context: context,
                    onAdd: { row in
                        await addReviewed(row)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
            Text("Shopping list")
                .font(ReasiTypography.largeTitle)
                .foregroundStyle(Color.reasi.text)
            Text(coreLoop.hasPlan ? coreLoop.plan.shoppingList.storeName : appState.selectedStore.name)
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.muted)
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
                    Text("Search, link, product photo, or handwritten list")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                }
                Spacer()
                Image(systemName: "chevron.up")
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
                    await coreLoop.generateWeekPlan(
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
            GenerationProgressCard(
                stage: coreLoop.generationStage,
                elapsedSeconds: coreLoop.generationElapsedSeconds,
                cancel: { coreLoop.cancelGeneration(analytics: analytics) }
            )
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

    private var sections: some View {
        VStack(spacing: ReasiSpacing.s4) {
            ForEach(coreLoop.plan.shoppingList.sections) { section in
                ShoppingSectionCard(
                    section: section,
                    checkedItemIDs: coreLoop.checkedItemIDs,
                    toggle: { item in
                        coreLoop.toggleItem(item, supabase: supabase, analytics: analytics)
                    }
                )
            }
        }
    }

    private func resolveTextInput(_ text: String) async {
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
            activeSheet = .review(ReviewContext(method: method, rows: result.candidates.map { ReviewCandidateRow(candidate: $0) }))
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

    private func addReviewed(_ row: ReviewCandidateRow) async -> Bool {
        analytics.capture(.productCandidateReviewed, properties: [
            "method": .string(row.group ?? "candidate"),
            "confidence": .string(row.candidate.confidence.rawValue)
        ])
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
    case textImport
    case review(ReviewContext)
    case comparison(ProductComparisonResult)
    case assistant

    var id: String {
        switch self {
        case .textImport:
            "textImport"
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
    let onSubmit: (String) async -> Void

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
                .disabled(isLoading)
                .buttonStyle(ReasiPressStyle())

                Spacer()
            }
            .padding(ReasiSpacing.s5)
            .background(Color.reasi.background)
            .navigationTitle("Add product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct CandidateReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let context: ReviewContext
    let onAdd: (ReviewCandidateRow) async -> Bool
    let onCompare: ([ReviewCandidateRow]) async -> Void
    let onDiscard: (String, ProductConfidence) -> Void
    @State private var selectedIDs: Set<String> = []
    @State private var addedIDs: Set<String> = []
    @State private var addingID: String?
    @State private var isComparing = false

    var selectedRows: [ReviewCandidateRow] {
        context.rows.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
                    Text("Review before adding. Prices and sources stay visible when Reasi is not certain.")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.muted)

                    ForEach(context.rows) { row in
                        CandidateReviewRow(
                            row: row,
                            isSelected: selectedIDs.contains(row.id),
                            isAdding: addingID == row.id,
                            isAdded: addedIDs.contains(row.id),
                            toggleSelection: {
                                if selectedIDs.contains(row.id) {
                                    selectedIDs.remove(row.id)
                                } else {
                                    selectedIDs.insert(row.id)
                                }
                            },
                            add: {
                                guard !addedIDs.contains(row.id), addingID == nil else { return }
                                addingID = row.id
                                if await onAdd(row) {
                                    addedIDs.insert(row.id)
                                }
                                addingID = nil
                            },
                            discard: {
                                onDiscard(context.method, row.candidate.confidence)
                            }
                        )
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
    let row: ReviewCandidateRow
    let isSelected: Bool
    let isAdding: Bool
    let isAdded: Bool
    let toggleSelection: () -> Void
    let add: () async -> Void
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            HStack(alignment: .top, spacing: ReasiSpacing.s3) {
                Button(action: toggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.reasi.success : Color.reasi.dim)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    Text(row.candidate.displayName)
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                    if let size = row.candidate.size {
                        Text(size)
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.textMuted)
                    }
                }

                Spacer()

                if let price = row.candidate.priceAud {
                    Text("$\(price, specifier: "%.2f")")
                        .font(ReasiTypography.bodyMedium)
                        .foregroundStyle(Color.reasi.text)
                } else {
                    Text("Price not certain")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.warning)
                }
            }

            HStack(spacing: ReasiSpacing.s2) {
                ConfidenceBadge(confidence: row.candidate.confidence)
                Text(row.candidate.sourceName)
                Text("·")
                Text(row.candidate.freshnessLabel)
            }
            .font(ReasiTypography.caption)
            .foregroundStyle(Color.reasi.muted)

            Text(row.candidate.confidenceReason)
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.textMuted)

            Text(row.candidate.uncertaintyText)
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.warning)

            HStack {
                Button {
                    Task { await add() }
                } label: {
                    Label(
                        isAdded ? "Added" : isAdding ? "Adding" : "Add",
                        systemImage: isAdded ? "checkmark" : "plus"
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
                            Text("\(row.sourceName) · \(row.freshnessLabel)")
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.muted)
                            Text(row.caveat)
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.warning)
                        }
                        .padding(ReasiSpacing.s4)
                        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
                    }

                    ForEach(result.caveats, id: \.self) { caveat in
                        Text(caveat)
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
                Text(message.content)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.text)

                ForEach(message.caveats, id: \.self) { caveat in
                    Text(caveat)
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
                Image(systemName: section.type == .numbered ? "number" : "leaf")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.reasi.dim)
                    .frame(width: 34, height: 34)
                    .background(Color.reasi.surfaceHigh, in: Circle())
            }

            VStack(spacing: ReasiSpacing.s2) {
                ForEach(section.items) { item in
                    Button {
                        toggle(item)
                    } label: {
                        ShoppingItemRow(item: item, isChecked: checkedItemIDs.contains(item.id))
                    }
                    .buttonStyle(ReasiPressStyle())
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
}

private struct ShoppingItemRow: View {
    let item: ShoppingListItem
    let isChecked: Bool

    var body: some View {
        HStack(spacing: ReasiSpacing.s3) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(isChecked ? Color.reasi.success : Color.reasi.dim)
                .symbolEffect(.bounce, value: isChecked)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(isChecked ? Color.reasi.muted : Color.reasi.text)
                    .strikethrough(isChecked, color: Color.reasi.muted)
                    .lineLimit(1)
                Text(detailText)
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
                    .lineLimit(1)
                if let imported = item.importedCandidate {
                    Text("\(imported.confidence.label) · \(imported.sourceName) · \(imported.freshnessLabel)")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(imported.confidence == .low ? Color.reasi.warning : Color.reasi.dim)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let price = item.product?.priceAud {
                Text("$\(price, specifier: "%.2f")")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.textMuted)
            }
        }
        .padding(.vertical, ReasiSpacing.s2)
        .padding(.horizontal, ReasiSpacing.s2)
        .background(
            isChecked ? Color.reasi.surfaceHigh.opacity(0.36) : Color.clear,
            in: RoundedRectangle(cornerRadius: ReasiRadius.md, style: .continuous)
        )
        .animation(ReasiMotion.fast, value: isChecked)
    }

    private var detailText: String {
        "\(item.quantity) · \(item.aisleLabel ?? "Unmatched")"
    }
}

#Preview {
    ShoppingListPlaceholderView()
        .environment(AppState())
        .environment(CoreLoopStore())
        .environment(SupabaseService())
        .environment(AnalyticsService())
        .environment(NetworkMonitor())
        .preferredColorScheme(.dark)
}
