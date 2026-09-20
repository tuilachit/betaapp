import SwiftUI

struct ProductSearchContext: Identifiable, Hashable {
    let id = UUID().uuidString
    let targetItemID: String?
    let targetItemName: String?
    let initialQuery: String
    var startsWithScanner = false
}

struct ProductSearchView: View {
    @Environment(\.dismiss) private var dismiss

    let context: ProductSearchContext
    let store: StoreSummary
    let targetItem: ShoppingListItem?
    let basketSummary: BasketPriceSummary
    let budgetTargetAud: Double?
    let recentCandidates: [ProductCandidate]
    let searchProducts: (String) async throws -> [ProductCandidate]
    let importProductLink: (String) async throws -> [ProductCandidate]
    let resolveBarcode: (String) async throws -> [ProductCandidate]
    let addCandidate: (ProductCandidate, Double?) async -> Bool
    let addManualItem: (String) async -> Bool

    @State private var query: String
    @State private var results: [ProductCandidate] = []
    @State private var phase: ProductSearchPhase = .idle
    @State private var addedIDs: Set<String> = []
    @State private var addingID: String?
    @State private var selectedCandidate: ProductCandidate?
    @State private var isShowingScanner = false
    @State private var didPresentInitialScanner = false
    @State private var isShowingExternalLookup = false
    @State private var actionError: String?
    @FocusState private var searchIsFocused: Bool

    init(
        context: ProductSearchContext,
        store: StoreSummary,
        targetItem: ShoppingListItem? = nil,
        basketSummary: BasketPriceSummary = BasketPriceSummary(items: []),
        budgetTargetAud: Double? = nil,
        recentCandidates: [ProductCandidate],
        searchProducts: @escaping (String) async throws -> [ProductCandidate],
        importProductLink: @escaping (String) async throws -> [ProductCandidate],
        resolveBarcode: @escaping (String) async throws -> [ProductCandidate],
        addCandidate: @escaping (ProductCandidate, Double?) async -> Bool,
        addManualItem: @escaping (String) async -> Bool
    ) {
        self.context = context
        self.store = store
        self.targetItem = targetItem
        self.basketSummary = basketSummary
        self.budgetTargetAud = budgetTargetAud
        self.recentCandidates = recentCandidates
        self.searchProducts = searchProducts
        self.importProductLink = importProductLink
        self.resolveBarcode = resolveBarcode
        self.addCandidate = addCandidate
        self.addManualItem = addManualItem
        _query = State(initialValue: context.initialQuery)
        _addedIDs = State(
            initialValue: context.targetItemID == nil
                ? Set(recentCandidates.map(\.id))
                : []
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchHeader
                resultsContent
            }
            .background(Color.reasi.background)
            .navigationTitle(context.targetItemID == nil ? "Add groceries" : "Change product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.reasi.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close product search")
                }

            }
        }
        .task {
            if context.startsWithScanner, !didPresentInitialScanner {
                didPresentInitialScanner = true
                isShowingScanner = true
            } else {
                searchIsFocused = context.initialQuery.isEmpty
            }
        }
        .task(id: query) {
            await searchForCurrentQuery()
        }
        .fullScreenCover(isPresented: $isShowingScanner) {
            BarcodeScannerScreen(
                itemName: context.targetItemName ?? "product",
                onScanned: { barcode in
                    isShowingScanner = false
                    Task { await loadBarcode(barcode) }
                },
                onCancel: {
                    isShowingScanner = false
                    searchIsFocused = true
                }
            )
        }
        .sheet(item: $selectedCandidate) { candidate in
            ProductCandidateDetailView(
                candidate: candidate,
                isFulfillingItem: context.targetItemID != nil,
                selectionSummary: { actualPrice in selectionDetail(for: candidate, actualPrice: actualPrice) },
                selectionIssue: { actualPrice in selectionIssue(for: candidate, actualPrice: actualPrice) },
                onAdd: { actualPrice in
                    await performAdd(candidate, actualPrice: actualPrice)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            HStack(spacing: ReasiSpacing.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.reasi.muted)

                TextField("Search products", text: $query)
                    .font(ReasiTypography.body)
                    .foregroundStyle(Color.reasi.text)
                    .focused($searchIsFocused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)

                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                        phase = .idle
                        isShowingExternalLookup = false
                        searchIsFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.reasi.dim)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Clear search")
                }

                Button {
                    searchIsFocused = false
                    ReasiHaptics.light()
                    isShowingScanner = true
                } label: {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.reasi.text)
                        .frame(width: 36, height: 36)
                        .background(Color.reasi.surfaceHigh, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Scan product barcode")
            }
            .padding(.leading, ReasiSpacing.s4)
            .padding(.trailing, ReasiSpacing.s2)
            .frame(height: 56)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous)
                    .stroke(searchIsFocused ? Color.reasi.borderStrong : Color.reasi.border, lineWidth: 1)
            }
        }
        .padding(.horizontal, ReasiSpacing.s5)
        .padding(.top, ReasiSpacing.s3)
        .padding(.bottom, ReasiSpacing.s4)
    }

    @ViewBuilder
    private var resultsContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let actionError {
                    Label(actionError, systemImage: "exclamationmark.circle")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.warning)
                        .padding(.horizontal, ReasiSpacing.s5)
                        .padding(.vertical, ReasiSpacing.s3)
                }

                if isProductLink {
                    productLinkAction
                } else if isShowingExternalLookup {
                    externalLookupContent
                } else if trimmedQuery.count < 2 {
                    discoveryContent
                } else {
                    switch phase {
                    case .idle, .loading:
                        loadingRows
                    case .loaded:
                        if results.isEmpty {
                            noResultsContent
                        } else {
                            resultRows
                        }
                    case .failed(let message):
                        searchError(message)
                    }
                }
            }
            .padding(.bottom, ReasiSpacing.s10)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("product-search-results")
    }

    private var discoveryContent: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            if !recentCandidates.isEmpty {
                Text("Recently chosen")
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)

                ForEach(Array(recentCandidates.prefix(6))) { candidate in
                    productRow(candidate)
                }
            } else {
                VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                    Image(systemName: "basket")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.reasi.textMuted)
                    Text("Search like you normally shop")
                        .font(ReasiTypography.title2)
                        .foregroundStyle(Color.reasi.text)
                    Text("Try a product, brand, or something broad like pasta sauce. Typos are okay.")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, ReasiSpacing.s6)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ReasiSpacing.s2) {
                        suggestion("Milk")
                        suggestion("Chicken thighs")
                        suggestion("Pasta sauce")
                    }
                }
            }
        }
        .padding(ReasiSpacing.s5)
    }

    private var resultRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(store.name, systemImage: "storefront")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.textMuted)
                Spacer()
                Text("\(results.count) options")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
            }
            .padding(.horizontal, ReasiSpacing.s5)
            .padding(.vertical, ReasiSpacing.s3)

            ForEach(results) { candidate in
                productRow(candidate)
            }

            if context.targetItemID == nil, !trimmedQuery.isEmpty {
                manualAddAction
            }
        }
    }

    @ViewBuilder
    private var externalLookupContent: some View {
        switch phase {
        case .idle, .loading:
            loadingRows
        case .loaded:
            if results.isEmpty {
                noResultsContent
            } else {
                resultRows
            }
        case .failed(let message):
            searchError(message)
        }
    }

    private func productRow(_ candidate: ProductCandidate) -> some View {
        let product = targetItem.map { ProductPurchaseEstimate.snapshot(candidate: candidate, item: $0) }
        let issue = selectionIssue(for: candidate, actualPrice: nil)
        let needsReview = issue != nil || (product != nil && (product?.purchaseQuantity == nil || product?.priceAud == nil))
        let isCurrent = candidate.sku != nil && candidate.sku == targetItem?.product?.sku
            && (candidate.retailer == nil || candidate.retailer == store.retailer)
        return ProductSearchResultRow(
            candidate: candidate,
            actionTitle: needsReview ? "Review" : targetItem == nil ? "Add" : "Choose",
            isOverBudget: { if case .overBudget = issue { return true }; return false }(),
            isCurrent: isCurrent,
            isAdding: addingID == candidate.id,
            isAdded: addedIDs.contains(candidate.id),
            openDetails: {
                selectedCandidate = candidate
            },
            add: {
                if needsReview {
                    selectedCandidate = candidate
                } else {
                    Task { await performAdd(candidate, actualPrice: nil) }
                }
            }
        )
    }

    private func selectionIssue(for candidate: ProductCandidate, actualPrice: Double?) -> ProductSelectionIssue? {
        guard let targetItem else { return nil }
        let product = ProductPurchaseEstimate.snapshot(candidate: candidate, item: targetItem, actualUnitPrice: actualPrice)
        return basketSummary.issueReplacing(targetItem, with: product, budget: budgetTargetAud)
    }

    private func selectionDetail(for candidate: ProductCandidate, actualPrice: Double? = nil) -> ProductPickerSelectionSummary? {
        guard let targetItem else { return nil }
        let product = ProductPurchaseEstimate.snapshot(candidate: candidate, item: targetItem, actualUnitPrice: actualPrice)
        let previous = targetItem.product?.actualPriceAud ?? targetItem.product?.priceAud ?? 0
        let after = product.priceAud.map { basketSummary.plannedTotalAud - previous + $0 }
        let totalLabel = basketSummary.pricedItemCount + (targetItem.product?.priceAud == nil ? 1 : 0) == basketSummary.totalItemCount ? "Basket" : "Priced subtotal"
        return ProductPickerSelectionSummary(requiredQuantity: targetItem.quantity, packCount: product.purchaseQuantity, total: product.priceAud, basketAfter: after, basketLabel: totalLabel)
    }

    private var loadingRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: ReasiSpacing.s3) {
                    SkeletonBlock(height: 56, radius: ReasiRadius.md)
                        .frame(width: 56)
                    VStack(spacing: ReasiSpacing.s2) {
                        SkeletonBlock(height: 16, radius: 8)
                        SkeletonBlock(height: 12, radius: 6)
                    }
                }
                .padding(.horizontal, ReasiSpacing.s5)
                .padding(.vertical, ReasiSpacing.s3)
            }
        }
    }

    private var noResultsContent: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.reasi.textMuted)
            Text("No close product matches")
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)
            Text("Try a shorter name or scan the barcode on the package.")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)

            if context.targetItemID == nil {
                manualAddButton
            }
        }
        .padding(ReasiSpacing.s5)
    }

    private func searchError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            Text("Search is unavailable")
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)
            Text(message)
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
            Button("Try again") {
                Task { await performSearch(trimmedQuery, debounce: false) }
            }
            .buttonStyle(ReasiPrimaryButtonStyle())
        }
        .padding(ReasiSpacing.s5)
    }

    private var productLinkAction: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            Label("Product link detected", systemImage: "link")
                .font(ReasiTypography.headline)
                .foregroundStyle(Color.reasi.text)
            Text(URL(string: trimmedQuery)?.host ?? trimmedQuery)
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
                .lineLimit(2)
            Button {
                Task { await loadProductLink() }
            } label: {
                Label(phase.isLoading ? "Checking link" : "Import product", systemImage: "arrow.down.circle")
            }
            .buttonStyle(ReasiPrimaryButtonStyle())
            .disabled(phase.isLoading)

            if !results.isEmpty {
                ForEach(results) { candidate in
                    productRow(candidate)
                }
            }
        }
        .padding(ReasiSpacing.s5)
    }

    private var manualAddAction: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            Divider().overlay(Color.reasi.border)
            Text("Can\u{2019}t find the exact product?")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
            manualAddButton
        }
        .padding(ReasiSpacing.s5)
    }

    private var manualAddButton: some View {
        Button {
            Task {
                let added = await addManualItem(trimmedQuery)
                if added { dismiss() }
            }
        } label: {
            Label("Add \u{201c}\(trimmedQuery)\u{201d} as written", systemImage: "plus")
                .font(ReasiTypography.bodyMedium)
                .foregroundStyle(Color.reasi.text)
        }
        .buttonStyle(ReasiPressStyle())
    }

    private func suggestion(_ value: String) -> some View {
        Button(value) {
            query = value
        }
        .font(ReasiTypography.caption)
        .foregroundStyle(Color.reasi.text)
        .padding(.horizontal, ReasiSpacing.s3)
        .frame(height: 36)
        .background(Color.reasi.surface, in: Capsule())
        .buttonStyle(ReasiPressStyle())
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isProductLink: Bool {
        guard let url = URL(string: trimmedQuery), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    private func searchForCurrentQuery() async {
        let term = trimmedQuery
        actionError = nil
        if isShowingExternalLookup, term.isEmpty {
            return
        }
        if !term.isEmpty {
            isShowingExternalLookup = false
        }
        if term.count < 2 || isProductLink {
            results = []
            phase = .idle
            return
        }
        await performSearch(term, debounce: true)
    }

    private func performSearch(_ term: String, debounce: Bool) async {
        do {
            if debounce {
                try await Task.sleep(for: .milliseconds(280))
            }
            try Task.checkCancellation()
            phase = .loading
            let found = try await searchProducts(term)
            try Task.checkCancellation()
            guard term == trimmedQuery else { return }
            withAnimation(ReasiMotion.fast) {
                results = found
                phase = .loaded
            }
        } catch is CancellationError {
            return
        } catch {
            guard term == trimmedQuery else { return }
            results = []
            phase = .failed("Check your connection and try again.")
        }
    }

    private func loadProductLink() async {
        phase = .loading
        actionError = nil
        do {
            results = try await importProductLink(trimmedQuery)
            phase = .loaded
        } catch {
            results = []
            phase = .failed("That link could not be read. Try searching by product name.")
        }
    }

    private func loadBarcode(_ barcode: String) async {
        isShowingExternalLookup = true
        phase = .loading
        actionError = nil
        searchIsFocused = false
        do {
            results = try await resolveBarcode(barcode)
            query = ""
            phase = .loaded
        } catch {
            results = []
            phase = .failed("That barcode was not found. Try searching by product name.")
        }
    }

    private func performAdd(_ candidate: ProductCandidate, actualPrice: Double?) async -> Bool {
        guard addingID == nil, !addedIDs.contains(candidate.id) else { return true }
        if let issue = selectionIssue(for: candidate, actualPrice: actualPrice) {
            actionError = issue.localizedDescription
            return false
        }
        addingID = candidate.id
        actionError = nil
        let added = await addCandidate(candidate, actualPrice)
        addingID = nil
        if added {
            _ = withAnimation(ReasiMotion.tactileSpring) {
                addedIDs.insert(candidate.id)
            }
            if context.targetItemID != nil {
                dismiss()
            }
            return true
        }
        actionError = "That product could not be added. Please try again."
        return false
    }
}

private enum ProductSearchPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

private enum ProductPickerFormatting {
    static func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: "AUD").locale(Locale(identifier: "en_AU")))
    }

    static func size(_ value: String) -> String {
        value.replacingOccurrences(of: #"^approx\.?\s*"#, with: "≈", options: [.regularExpression, .caseInsensitive])
    }
}

private struct ProductPickerSelectionSummary {
    let requiredQuantity: String
    let packCount: Int?
    let total: Double?
    let basketAfter: Double?
    let basketLabel: String
}

private struct ProductSearchResultRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let candidate: ProductCandidate
    let actionTitle: String
    let isOverBudget: Bool
    let isCurrent: Bool
    let isAdding: Bool
    let isAdded: Bool
    let openDetails: () -> Void
    let add: () -> Void

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        layout {
            Button(action: openDetails) {
                HStack(spacing: 12) {
                    ProductThumbnail(url: candidate.imageUrl, size: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(candidate.displayName)
                            .font(ReasiTypography.font(size: 15, weight: .medium))
                            .foregroundStyle(Color.reasi.text)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let size = candidate.size, !size.isEmpty {
                            Text(ProductPickerFormatting.size(size))
                                .font(ReasiTypography.font(size: 12, relativeTo: .caption))
                                .foregroundStyle(Color.reasi.muted)
                        }
                        if isOverBudget {
                            Text("Over budget")
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.warning)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details for \(candidate.displayName)")

            VStack(alignment: .trailing, spacing: 0) {
                Text(candidate.priceAud.map(ProductPickerFormatting.money) ?? "—")
                    .font(ReasiTypography.callout)
                    .monospacedDigit()
                    .foregroundStyle(Color.reasi.text)
                    .accessibilityLabel(candidate.priceAud.map { "Price per pack \(ProductPickerFormatting.money($0))" } ?? "Price unconfirmed")

                Button(action: add) {
                    Group {
                        if isAdding {
                            ProgressView().controlSize(.small)
                        } else if isCurrent || isAdded {
                            Label(isCurrent ? "Current" : "Added", systemImage: "checkmark")
                        } else {
                            Text(actionTitle)
                        }
                    }
                    .font(ReasiTypography.caption)
                    .foregroundStyle(isCurrent || isAdded ? Color.reasi.success : Color.reasi.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isCurrent || isAdded ? Color.reasi.success.opacity(0.08) : Color.reasi.surfaceHigh, in: Capsule())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ReasiPressStyle())
                .disabled(isAdding || isAdded || isCurrent)
                .accessibilityLabel(isCurrent ? "Current product: \(candidate.displayName)" : isAdded ? "Added \(candidate.displayName)" : "\(actionTitle) \(candidate.displayName)")
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, ReasiSpacing.s5)
        .padding(.vertical, 12)
        .background(Color.reasi.background)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.reasi.border)
                .padding(.leading, 56 + ReasiSpacing.s5 + 12)
        }
    }
}

struct ProductThumbnail: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: ReasiMotion.fast)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            case .empty:
                if url == nil {
                    placeholder
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.reasi.muted)
                }
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: ReasiRadius.md, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.md, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "basket")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Color.reasi.dim)
    }
}

private struct ProductCandidateDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let candidate: ProductCandidate
    let isFulfillingItem: Bool
    let selectionSummary: (Double?) -> ProductPickerSelectionSummary?
    let selectionIssue: (Double?) -> ProductSelectionIssue?
    let onAdd: (Double?) async -> Bool

    @State private var shelfPrice = ""
    @State private var isAdding = false
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ReasiSpacing.s5) {
                    HStack(alignment: .top, spacing: ReasiSpacing.s4) {
                        ProductThumbnail(url: candidate.imageUrl, size: 112)
                        VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                            Text(candidate.displayName)
                                .font(ReasiTypography.title2)
                                .foregroundStyle(Color.reasi.text)
                            if let size = candidate.size, !size.isEmpty {
                                Text(size)
                                    .font(ReasiTypography.callout)
                                    .foregroundStyle(Color.reasi.textMuted)
                            }
                            if let price = candidate.priceAud {
                                Text(ProductPickerFormatting.money(price))
                                    .font(ReasiTypography.title2)
                                    .foregroundStyle(Color.reasi.text)
                            } else {
                                Text("Current price not certain")
                                    .font(ReasiTypography.callout)
                                    .foregroundStyle(Color.reasi.warning)
                            }
                            if let unitValue = candidate.comparablePrice, !unitValue.isEmpty {
                                Text(unitValue)
                                    .font(ReasiTypography.caption)
                                    .foregroundStyle(Color.reasi.muted)
                            }
                        }
                    }

                    if let summary = selectionSummary(parsedShelfPrice) {
                        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                            summaryRow("Recipe needs", value: summary.requiredQuantity)
                            if let count = summary.packCount, let total = summary.total {
                                summaryRow("Buy", value: "\(count) \(count == 1 ? "pack" : "packs") · \(ProductPickerFormatting.money(total))")
                            } else {
                                Text("Quantity or price needs checking")
                                    .font(ReasiTypography.callout)
                                    .foregroundStyle(Color.reasi.warning)
                            }
                            if let after = summary.basketAfter {
                                summaryRow("\(summary.basketLabel) after change", value: ProductPickerFormatting.money(after))
                            }
                            if let issue = selectionIssue(parsedShelfPrice) {
                                Text(issue.localizedDescription)
                                    .font(ReasiTypography.callout)
                                    .foregroundStyle(Color.reasi.warning)
                            }
                        }
                        .padding(ReasiSpacing.s4)
                        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg))
                    }

                    detailRow("Location", value: candidate.aisleLabel ?? "Location not certain", symbol: "mappin.and.ellipse")
                    detailRow("Source", value: candidate.userFacingSourceName, symbol: "checkmark.shield")
                    detailRow("Freshness", value: candidate.freshnessLabel, symbol: "clock")

                    if candidate.confidence != .high || candidate.priceAud == nil {
                        Label(candidate.uncertaintyText.reasiUserFacingCopy, systemImage: "exclamationmark.triangle")
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isFulfillingItem {
                        DisclosureGroup("Different shelf price?") {
                            VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                                TextField("Optional", text: $shelfPrice)
                                    .accessibilityLabel("Shelf price per pack")
                                    .keyboardType(.decimalPad)
                                    .font(ReasiTypography.body)
                                    .foregroundStyle(Color.reasi.text)
                                    .padding(ReasiSpacing.s4)
                                    .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.md, style: .continuous))
                                Text(shelfPriceIsInvalid ? "Enter a valid price per pack." : "Enter the price of one pack.")
                                    .font(ReasiTypography.caption)
                                    .foregroundStyle(shelfPriceIsInvalid ? Color.reasi.warning : Color.reasi.muted)
                            }
                            .padding(.top, ReasiSpacing.s3)
                        }
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.text)
                    }
                    if saveFailed {
                        Text("Couldn’t save this product. Please try again.")
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.warning)
                    }
                }
                .padding(ReasiSpacing.s5)
                .padding(.bottom, 96)
            }
            .background(Color.reasi.background)
            .navigationTitle("Product details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard !isAdding else { return }
                    isAdding = true
                    saveFailed = false
                    Task {
                        let added = await onAdd(parsedShelfPrice)
                        isAdding = false
                        saveFailed = !added
                        if added { dismiss() }
                    }
                } label: {
                    HStack {
                        if isAdding { ProgressView().tint(Color.reasi.background) }
                        Text(isAdding ? "Saving" : (isFulfillingItem ? "Use this product" : "Add to list"))
                    }
                }
                .buttonStyle(ReasiPrimaryButtonStyle())
                .disabled(isAdding || shelfPriceIsInvalid || selectionIssue(parsedShelfPrice) != nil)
                .padding(.horizontal, ReasiSpacing.s5)
                .padding(.vertical, ReasiSpacing.s3)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func detailRow(_ title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: ReasiSpacing.s3) {
            Image(systemName: symbol)
                .foregroundStyle(Color.reasi.textMuted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
                Text(value)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.text)
            }
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ReasiSpacing.s3) {
            Text(title).foregroundStyle(Color.reasi.muted)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(Color.reasi.text).multilineTextAlignment(.trailing)
        }
        .font(ReasiTypography.callout)
    }

    private var shelfPriceIsInvalid: Bool {
        guard !shelfPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let price = parsedShelfPrice else { return true }
        return !price.isFinite || price < 0
    }

    private var parsedShelfPrice: Double? {
        let normalized = shelfPrice
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : Double(normalized)
    }
}
