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
        recentCandidates: [ProductCandidate],
        searchProducts: @escaping (String) async throws -> [ProductCandidate],
        importProductLink: @escaping (String) async throws -> [ProductCandidate],
        resolveBarcode: @escaping (String) async throws -> [ProductCandidate],
        addCandidate: @escaping (ProductCandidate, Double?) async -> Bool,
        addManualItem: @escaping (String) async -> Bool
    ) {
        self.context = context
        self.store = store
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
                Divider().overlay(Color.reasi.border)
                resultsContent
            }
            .background(Color.reasi.background)
            .navigationTitle(context.targetItemID == nil ? "Add groceries" : "Choose product")
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

                ToolbarItem(placement: .topBarTrailing) {
                    Label(store.shortName, systemImage: "storefront")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.textMuted)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if context.startsWithScanner, !didPresentInitialScanner {
                didPresentInitialScanner = true
                isShowingScanner = true
            } else {
                searchIsFocused = true
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
            if let itemName = context.targetItemName {
                Text("Choose the exact product for \u{201c}\(itemName)\u{201d}")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
                    .lineLimit(1)
            } else {
                Label("Shopping at \(store.shortName)", systemImage: "storefront")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.textMuted)
                    .lineLimit(1)
            }

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
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.reasi.dim)
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
                        .frame(width: 40, height: 40)
                        .background(Color.reasi.surfaceHigh, in: Circle())
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
                Text("Products at \(store.shortName)")
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                Spacer()
                Text("\(results.count)")
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
        ProductSearchResultRow(
            candidate: candidate,
            isAdding: addingID == candidate.id,
            isAdded: addedIDs.contains(candidate.id),
            openDetails: {
                selectedCandidate = candidate
            },
            add: {
                Task { await performAdd(candidate, actualPrice: nil) }
            }
        )
    }

    private var loadingRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: ReasiSpacing.s3) {
                    SkeletonBlock(height: 64, radius: ReasiRadius.md)
                        .frame(width: 64)
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

private struct ProductSearchResultRow: View {
    let candidate: ProductCandidate
    let isAdding: Bool
    let isAdded: Bool
    let openDetails: () -> Void
    let add: () -> Void

    var body: some View {
        HStack(spacing: ReasiSpacing.s3) {
            Button(action: openDetails) {
                HStack(spacing: ReasiSpacing.s3) {
                    ProductThumbnail(url: candidate.imageUrl, size: 64)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(candidate.displayName)
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 5) {
                            if let size = candidate.size, !size.isEmpty {
                                Text(size)
                            }
                            if let comparablePrice = candidate.comparablePrice, !comparablePrice.isEmpty {
                                Text("\u{00b7}")
                                Text(comparablePrice.lowercased())
                            }
                        }
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                        .lineLimit(1)

                        if let aisle = candidate.aisleLabel, !aisle.isEmpty {
                            Text(aisle)
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.textMuted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .trailing, spacing: ReasiSpacing.s2) {
                if let price = candidate.priceAud {
                    Text("$\(price, specifier: "%.2f")")
                        .font(ReasiTypography.bodyMedium)
                        .foregroundStyle(Color.reasi.text)
                } else {
                    Text("No price")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                }

                Button(action: add) {
                    Group {
                        if isAdding {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: isAdded ? "checkmark" : "plus")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundStyle(isAdded ? Color.reasi.background : Color.reasi.text)
                    .frame(width: 38, height: 38)
                    .background(isAdded ? Color.reasi.success : Color.reasi.surfaceHigh, in: Circle())
                }
                .buttonStyle(ReasiPressStyle())
                .disabled(isAdding || isAdded)
                .accessibilityLabel(isAdded ? "Added \(candidate.displayName)" : "Add \(candidate.displayName)")
            }
        }
        .padding(.horizontal, ReasiSpacing.s5)
        .padding(.vertical, ReasiSpacing.s3)
        .background(Color.reasi.background)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(Color.reasi.border)
                .padding(.leading, 64 + ReasiSpacing.s5 + ReasiSpacing.s3)
        }
    }
}

private struct ProductThumbnail: View {
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
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.reasi.muted)
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
    let onAdd: (Double?) async -> Bool

    @State private var shelfPrice = ""
    @State private var isAdding = false

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
                                Text("$\(price, specifier: "%.2f")")
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

                    detailRow("Location", value: candidate.aisleLabel ?? "Location not certain", symbol: "mappin.and.ellipse")
                    detailRow("Source", value: candidate.sourceName, symbol: "checkmark.shield")
                    detailRow("Freshness", value: candidate.freshnessLabel, symbol: "clock")

                    if candidate.confidence != .high || candidate.priceAud == nil {
                        Label(candidate.uncertaintyText, systemImage: "exclamationmark.triangle")
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isFulfillingItem {
                        VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                            Text("Price on the shelf")
                                .font(ReasiTypography.headline)
                                .foregroundStyle(Color.reasi.text)
                            TextField("Optional", text: $shelfPrice)
                                .keyboardType(.decimalPad)
                                .font(ReasiTypography.body)
                                .foregroundStyle(Color.reasi.text)
                                .padding(ReasiSpacing.s4)
                                .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.md, style: .continuous))
                            Text("Only change this when the shelf price differs from the catalog.")
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.muted)
                        }
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
                    Task {
                        let added = await onAdd(parsedShelfPrice)
                        isAdding = false
                        if added { dismiss() }
                    }
                } label: {
                    HStack {
                        if isAdding { ProgressView().tint(Color.reasi.background) }
                        Text(isAdding ? "Saving" : (isFulfillingItem ? "Use and check item" : "Add to list"))
                    }
                }
                .buttonStyle(ReasiPrimaryButtonStyle())
                .disabled(isAdding)
                .padding(.horizontal, ReasiSpacing.s5)
                .padding(.vertical, ReasiSpacing.s3)
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
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

    private var parsedShelfPrice: Double? {
        let normalized = shelfPrice
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : Double(normalized)
    }
}
