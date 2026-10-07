import Foundation
import SimplifyCore

private func catalogMetadataCacheKey(nodeID: String, instrument: LibraryInstrument? = nil) -> String {
    let item = instrument.map { value in value.vendorID.map { "vendor:" + $0 } ?? "path:" + value.path } ?? ""
    return nodeID + "\0" + item
}

private func prewarmLibraryMetadata(_ report: ScanReport) async -> ([String: MusicalMetadata], [String: String]) {
    await Task.detached(priority: .utility) {
        var suggestions: [String: MusicalMetadata] = [:]
        var durableKeys: [String: String] = [:]
        for asset in report.assets where asset.kind == .library {
            guard let nodeID = asset.catalogID else { continue }
            let cacheKey = catalogMetadataCacheKey(nodeID: nodeID)
            durableKeys[cacheKey] = MetadataSubject(nodeID: nodeID).key
            for instrument in asset.libraryMetadata?.instruments ?? [] {
                let cacheKey = catalogMetadataCacheKey(nodeID: nodeID, instrument: instrument)
                suggestions[cacheKey] = MusicalMetadata.suggested(
                    name: instrument.name, tags: instrument.tags, kind: .library)
                durableKeys[cacheKey] = MetadataSubject(nodeID: nodeID, instrument: instrument).key
            }
        }
        return (suggestions, durableKeys)
    }.value
}

public enum RootKind: String, CaseIterable, Sendable {
    case plugins = "Plugins", samples = "Samples", libraries = "Libraries", projects = "Projects"
}
public enum CatalogAppearance: String, CaseIterable, Sendable {
    case light, dark, system
    public var title: String {
        switch self { case .light: "Light"; case .dark: "Dark"; case .system: "Match system preference" }
    }
}
public enum CatalogSort: String, CaseIterable, Sendable { case name = "Name", tags = "Tags", size = "Size", recency = "Last used", firstFound = "First found", format = "Format", installed = "Installed" }

public struct PluginSizePresentation: Sendable {
    public let completeBytes: Int?
    public let value: String
    public let detail: String
    public let accessibility: String
}

/// Positive host evidence is distinct from missing coverage. Unknown is never inactivity.
public enum CatalogUsageFilter: String, CaseIterable, Sendable {
    case all, unknown
    public var title: String { self == .all ? "Any usage history" : "Usage unknown" }
}

/// Browsing is session-only; accepted scan setup can be stored locally.
@MainActor public final class CatalogModel {
    public var category: AssetKind = .plugin { didSet { cachedVisible = nil; cachedOutline = nil; cachedSortTags = nil } }
    public var query = "" { didSet { cachedVisible = nil; cachedOutline = nil } }
    public var sort: CatalogSort = .name { didSet { if oldValue != sort { cachedVisible = nil; invalidateOutline() } } }
    public var sortReversed = false { didSet { if oldValue != sortReversed { cachedVisible = nil; invalidateOutline() } } }
    public var recentOnly = false { didSet { cachedVisible = nil; cachedOutline = nil } }
    public var usageFilter: CatalogUsageFilter = .all { didSet { cachedVisible = nil; cachedOutline = nil } }
    public var musicalFilter: [String: String] = [:] { didSet { cachedVisible = nil; cachedOutline = nil } }
    public private(set) var metadataOverrides: [String: MusicalMetadata] = [:]
    public private(set) var isSavingMetadata = false
    private var metadataUndo: [[(MetadataSubject, MusicalMetadata?)]] = []
    public var canUndoMetadata: Bool { !metadataUndo.isEmpty && !isBusy }
    public var navigationQuery: String {
        guard recentOnly || !musicalFilter.isEmpty || usageFilter != .all else { return query }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return query + "|filters:" + String(decoding: try! encoder.encode(musicalFilter), as: UTF8.self) + (recentOnly ? "|recent" : "") + "|usage:" + usageFilter.rawValue
    }
    public var hasFilters: Bool { !query.isEmpty || recentOnly || !musicalFilter.isEmpty || usageFilter != .all }
    private var tagRecords: [String: ProductTagRecord] = [:]
    private var tagCacheLoaded = false
    private let tagStore: ProductTagStore?
    private var tagSources: [ProductTagSource]
    private var tagSourcesByName: [String: [ProductTagSource]]
    private let sharedTagStore: SharedProductTagStore?
    private var sharedTagCacheLoaded = false
    private var sharedTagCacheTask: Task<SharedProductTagSnapshot?, Never>?
    public var appearance: CatalogAppearance = .light
    public var standardPlugins = true
    public private(set) var roots: [RootKind: [URL]] = [:]
    /// Legacy API name: holds Asset.selectionKey, not necessarily a filesystem path.
    public var selectedPath: String?
    public var selectedProductID: String?
    private var reportRevision = 0
    private var preparedIndexes: ReportIndexes?
    public private(set) var report: ScanReport? { didSet {
        reportRevision += 1
        if let preparedIndexes {
            self.preparedIndexes = nil
            installIndexes(preparedIndexes)
        } else { rebuildIndexes() }
    } }
    public private(set) var isScanning = false
    private var dirtyCategories: Set<AssetKind> = []
    public var configurationChanged: Bool { !dirtyCategories.isEmpty }
    public private(set) var scanningKinds: Set<AssetKind> = []
    public var onChange: (() -> Void)?
    public var onProgressChange: (() -> Void)?
    public private(set) var scanProgress: ScanProgress?
    public private(set) var scanStartedAt: Date?
    private var scanIdentifier = UUID()
    private var scanTask: Task<Void, Never>?
    public var isStoppingScan: Bool { isScanning && scanTask?.isCancelled == true }
    private var foregroundTask: Task<Void, Never>?
    public private(set) var isBackgroundScanning = false
    public private(set) var basicInventoryComplete = false
    private var inventorySequence = 0
    private var acceptingInventory = false
    private var cachedVisible: [Asset]?
    private var cachedOutline: CatalogOutline?
    private var outlineBases: [AssetKind: CatalogOutline] = [:]
    private var outlinePreparations: [AssetKind: (id: UUID, task: Task<Void, Never>)] = [:]
    public var isPreparingOutline: Bool { outlinePreparations[category] != nil }
    private var previousOutlineBases: [AssetKind: CatalogOutline] = [:]
    private var suggestedMetadataBySubject: [String: MusicalMetadata] = [:]
    private var durableMetadataSubjectsByCacheKey: [String: String] = [:]
    private var cachedSortTags: [String: String]?
    private var cachedQuerySource: String?
    private var cachedQueryTerms: [String] = []
    public let outlineState = CatalogOutlineState()
    private var assetsByKey: [String: Asset] = [:]
    private var inclusionsByPath: [String: SampleInclusion] = [:]
    public private(set) var pluginProducts: [PluginProduct] = []
    private var productsByPath: [String: PluginProduct] = [:]
    private var candidateProjects: [String: [ProjectReport]] = [:]
    public private(set) var isRemoving = false
    public var isBusy: Bool { isScanning || isRemoving || isSavingMetadata }
    private var categoryCounts: [AssetKind: Int] = [:]

    private struct ReportIndexes: Sendable {
        let assetsByKey: [String: Asset]
        let inclusionsByPath: [String: SampleInclusion]
        let categoryCounts: [AssetKind: Int]
        let pluginProducts: [PluginProduct]
        let productsByPath: [String: PluginProduct]
        let candidateProjects: [String: [ProjectReport]]
    }

    private func rebuildIndexes() {
        installIndexes(Self.makeIndexes(report: report, names: pluginProductNames))
    }

    private func installIndexes(_ indexes: ReportIndexes) {
        invalidateOutline()
        suggestedMetadataBySubject.removeAll(keepingCapacity: true)
        durableMetadataSubjectsByCacheKey.removeAll(keepingCapacity: true)
        cachedVisible = nil
        assetsByKey = indexes.assetsByKey
        inclusionsByPath = indexes.inclusionsByPath
        categoryCounts = indexes.categoryCounts
        pluginProducts = indexes.pluginProducts
        productsByPath = indexes.productsByPath
        candidateProjects = indexes.candidateProjects
    }

    nonisolated private static func makeIndexes(report: ScanReport?, names: [String: String]) -> ReportIndexes {
        var assetsByKey: [String: Asset] = [:], inclusionsByPath: [String: SampleInclusion] = [:]
        var categoryCounts: [AssetKind: Int] = [:], productsByPath: [String: PluginProduct] = [:]
        var candidateProjects: [String: [ProjectReport]] = [:]
        for asset in report?.assets ?? [] {
            assetsByKey[asset.kind.rawValue + ":" + asset.selectionKey] = asset
            categoryCounts[asset.kind, default: 0] += 1
        }
        for inclusion in report?.sampleInclusions ?? [] { inclusionsByPath[inclusion.samplePath] = inclusion }
        let pluginProducts = PluginProduct.group((report?.assets ?? []).filter { $0.kind == .plugin }, names: names)
        categoryCounts[.plugin] = pluginProducts.count
        let byName = Dictionary(grouping: pluginProducts, by: { PluginProduct.normalizedName($0.name) })
        for product in pluginProducts { for item in product.installations { productsByPath[item.path] = product } }
        for project in report?.projects ?? [] {
            var ids = Set<String>()
            for reference in project.references where reference.kind == .plugin {
                var name = reference.value
                if let range = name.range(of: #"^(VST3i?|VSTi?|AUi?|CLAPi?):\s*"#, options: .regularExpression) { name.removeSubrange(range) }
                if let range = name.range(of: #" \([^()]+\)$"#, options: .regularExpression) { name.removeSubrange(range) }
                if let products = byName[PluginProduct.normalizedName(name)], products.count == 1 { ids.insert(products[0].id) }
            }
            for id in ids { candidateProjects[id, default: []].append(project) }
        }
        return ReportIndexes(assetsByKey: assetsByKey, inclusionsByPath: inclusionsByPath,
                             categoryCounts: categoryCounts, pluginProducts: pluginProducts,
                             productsByPath: productsByPath, candidateProjects: candidateProjects)
    }
    private func invalidateOutline() {
        for preparation in outlinePreparations.values { preparation.task.cancel() }
        outlinePreparations.removeAll()
        for (category, outline) in outlineBases { previousOutlineBases[category] = outline }
        outlineBases = [:]; cachedOutline = nil; cachedSortTags = nil
    }
    private func prepareNameSortedLibraryOutline(_ report: ScanReport) -> (task: Task<CatalogOutline, Never>, reversed: Bool)? {
        guard sort == .name else { return nil }
        let assets = report.assets.filter { $0.kind == .library }
        guard !assets.isEmpty else { return nil }
        let reversed = sortReversed
        let task = Task.detached(priority: .utility) {
            CatalogOutline.build(assets: assets, category: .library, sort: .name, reversed: reversed)
        }
        return (task, reversed)
    }
    private func installNameSortedLibraryOutline(_ prepared: (task: Task<CatalogOutline, Never>, reversed: Bool)?,
                                                 identifier: UUID, scope: CatalogScope, reportRevision expectedRevision: Int) async {
        guard let prepared else { return }
        let outline = await prepared.task.value
        guard identifier == scanIdentifier, scope.roots == CatalogScope(scanRequest).roots,
              reportRevision == expectedRevision, sort == .name, sortReversed == prepared.reversed,
              outlineBases[.library] == nil else { return }
        outlineBases[.library] = outline
        if category == .library { cachedOutline = nil }
    }
    private var needsBackgroundOutline: Bool {
        if category == .sample { return categoryCounts[.sample, default: 0] > 5_000 }
        if category == .library {
            return (report?.assets ?? []).reduce(0) { $0 + ($1.libraryMetadata?.instruments.count ?? 0) } > 5_000
        }
        return false
    }

    private func prepareVisibleOutline() {
        let kind = category
        guard outlinePreparations[kind] == nil else { return }
        let id = UUID(), revision = reportRevision, selectedSort = sort, reversed = sortReversed
        let assets = report?.assets ?? [], sampleRoots = roots[.samples] ?? []
        let dates = sortDates, additions = sortAdditions, days = usageDays, tags = sortTags
        let task = Task { [weak self] in
            let outline = await CatalogOutline.prepare(assets: assets, category: kind, sampleRoots: sampleRoots,
                sort: selectedSort, reversed: reversed, recency: dates, additions: additions, usageDays: days, tags: tags)
            guard let self, !Task.isCancelled, self.outlinePreparations[kind]?.id == id,
                  self.reportRevision == revision, self.sort == selectedSort, self.sortReversed == reversed else { return }
            self.outlinePreparations.removeValue(forKey: kind)
            self.outlineState.reconcile(previous: self.previousOutlineBases[kind], current: outline, category: kind)
            self.outlineBases[kind] = outline; self.previousOutlineBases[kind] = nil
            self.cachedOutline = nil
            if self.category == kind { self.onChange?() }
        }
        outlinePreparations[kind] = (id, task)
    }

    public var outline: CatalogOutline {
        if !recentOnly, let cachedOutline { return cachedOutline }
        let base: CatalogOutline
        if let existing = outlineBases[category] { base = existing }
        else if needsBackgroundOutline {
            prepareVisibleOutline()
            // Keep the previous browsable tree while its replacement is prepared.
            // The window labels this state; a later generation cannot overwrite it.
            return previousOutlineBases[category] ?? CatalogOutline(roots: [])
        } else {
            base = CatalogOutline.build(
                assets: category == .plugin ? pluginProducts.map(\.representative) : (report?.assets ?? []),
                category: category, sampleRoots: roots[.samples] ?? [], sort: sort, reversed: sortReversed,
                recency: sortDates, additions: sortAdditions, usageDays: usageDays, formats: Dictionary(uniqueKeysWithValues: pluginProducts.map { ($0.representative.path, $0.formats) }),
                pluginProductIDs: Dictionary(uniqueKeysWithValues: pluginProducts.map { ($0.representative.path, $0.id) }),
                pluginNames: Dictionary(uniqueKeysWithValues: pluginProducts.map { ($0.representative.path, $0.name) }),
                pluginSizes: Dictionary(uniqueKeysWithValues: pluginProducts.map { ($0.representative.path, pluginSize($0.representative)) }),
                tags: sortTags)
            outlineState.reconcile(previous: previousOutlineBases[category], current: base, category: category)
            previousOutlineBases[category] = nil; outlineBases[category] = base
        }
        let result = base.filtered(query: query, sort: sort, reversed: sortReversed,
                                  recency: sortDates, additions: sortAdditions, usageDays: usageDays, tags: sortTags,
                                  pluginMatches: matchesRow, isFiltering: hasFilters,
                                  nodeMatches: matchesNode)
        cachedOutline = result
        return result
    }
    private func matchesQuery(_ asset: Asset) -> Bool {
        if asset.kind == .library {
            let metadata = effectiveMetadata(asset: asset)
            return matchesLibraryMetadata(asset, metadata: metadata)
                && matchesFacets(metadata) && (!recentOnly || isRecent(asset))
        }
        return matchesCatalogQuery(name: product(for: asset)?.name ?? asset.name,
                            other: [asset.libraryMetadata?.maker ?? "", effectiveMetadata(asset: asset).searchText].joined(separator: " "))
            && matchesFacets(effectiveMetadata(asset: asset)) && (!recentOnly || isRecent(asset))
    }

    private func matchesCatalogQuery(name: String, other: String) -> Bool {
        let nameWords = MusicalSearch.normalized(name).split(separator: " ")
        let allText = MusicalSearch.normalized(name + " " + other)
        let allWords = allText.split(separator: " ")
        return normalizedQueryTerms.allSatisfy { term in
            // Incremental one-letter name search should find Glow on "g"; typed
            // tag keys and numeric sample suffixes retain exact-token matching.
            (term.count == 1 && !term.allSatisfy(\.isNumber) && nameWords.contains { $0.hasPrefix(term) })
                || queryTerm(term, matches: allWords, in: allText)
        }
    }
    private func matchesLibraryMetadata(_ asset: Asset, metadata: MusicalMetadata) -> Bool {
        let identity = asset.libraryMetadata?.maker ?? ""
        // Patch identity remains searchable without promoting patch tags into
        // the product's displayed classification. One patch must satisfy all terms.
        return matchesCatalogQuery(name: asset.name, other: identity)
            || (asset.libraryMetadata?.instruments ?? []).contains {
                matchesCatalogQuery(name: $0.name, other: $0.tags.joined(separator: " "))
            }
            || metadata.fields.values.flatMap { $0 }.contains {
                matchesCatalogQuery(name: asset.name, other: identity + " " + $0)
            }
    }

    public private(set) var onboardingCompleted = false
    public private(set) var setupNotice: String?
    public private(set) var savedCatalogDate: Date?
    public private(set) var usingSavedCatalog = false
    public private(set) var isRestoringCatalog = false
    public private(set) var catalogNotice: String?
    public private(set) var catalogObservations: [String: CatalogObservation] = [:] { didSet { cachedVisible = nil; invalidateOutline() } }
    public private(set) var pluginProductDates: [String: Date] = [:] { didSet { cachedVisible = nil; invalidateOutline() } }
    public private(set) var pluginProductNames: [String: String] = [:] { didSet { cachedVisible = nil; invalidateOutline() } }
    public private(set) var pluginConfirmedAdditionDates: [String: Date] = [:] { didSet { cachedVisible = nil; invalidateOutline() } }
    public typealias InstallerRecordLoader = @Sendable (CatalogStore, [String], Date) async throws -> [Data: AssetDateEvidence]
    private let installerRecordLoader: InstallerRecordLoader?
    private var installerRecords: [Data: AssetDateEvidence] = [:]
    private var confirmedAdditionDates: [Data: Date] = [:]
    private var installerReadGeneration = UUID()
    public private(set) var isLoadingInstallerRecords = false
    public private(set) var installerRecordsUnavailable = false
    public private(set) var isCollectingInstallerRecords = false
    public typealias UsageCollector = @Sendable ([Asset], CatalogStore) async -> LiveUsageCollection
    public typealias UsageLoader = @Sendable (CatalogStore, [String], Date) async throws -> [Data: AssetDateEvidence]
    private let usageLoader: UsageLoader?
    private let usageCollector: UsageCollector?
    private let savedProjectUsageOnly: Bool
    private var usageTask: Task<Void, Never>?
    private var usageGeneration = UUID()
    private var usageReadGeneration = UUID()
    private var usageRecords: [Data: AssetDateEvidence] = [:]
    public private(set) var usageUnavailable = false
    public private(set) var itemUsageUnavailable = false
    public private(set) var isLoadingItemUsage = false
    public private(set) var isCollectingUsage = false
    public private(set) var usageCollection: LiveUsageCollection?

    public func reloadUsage() async {
        guard let catalogStore else { return }
        let generation = usageGeneration; let readGeneration = UUID(); usageReadGeneration = readGeneration
        let currentAssets = report?.assets ?? []
        var records: [Data: AssetDateEvidence] = [:]
        var pluginUnavailable = false, itemUnavailable = false
        let pluginIDs = currentAssets.filter { $0.kind == .plugin }.compactMap(\.catalogID)
        do {
            if let usageLoader { records = try await usageLoader(catalogStore, pluginIDs, Date()) }
            else {
                let products = try await catalogStore.latestProductUsage(for: pluginProducts.map(\.id), asOf: Date(), savedProjectOnly: savedProjectUsageOnly)
                var installations: [Data: AssetDateEvidence] = [:]
                for offset in stride(from: 0, to: pluginIDs.count, by: 2048) {
                    let batch = try await catalogStore.latestHostUsage(for: Array(pluginIDs[offset..<min(offset + 2048, pluginIDs.count)]), asOf: Date(), savedProjectOnly: savedProjectUsageOnly)
                    installations.merge(batch) { first, _ in first }
                }
                records = products.merging(installations) { product, _ in product }
            }
        } catch {
            pluginUnavailable = true
        }
        if usageLoader == nil {
            isLoadingItemUsage = true
            do {
                let parentIDs = currentAssets.filter { $0.kind != .plugin }.compactMap(\.catalogID)
                for offset in stride(from: 0, to: parentIDs.count, by: 2048) {
                    let batch = try await catalogStore.latestItemUsage(for: Array(parentIDs[offset..<min(offset + 2048, parentIDs.count)]), in: CatalogScope(scanRequest), asOf: Date(), savedProjectOnly: savedProjectUsageOnly)
                    records.merge(batch) { current, incoming in HostUsageOrdering.precedes(current, incoming) ? current : incoming }
                }
            } catch {
                itemUnavailable = true
            }
            isLoadingItemUsage = false
        }
        guard generation == usageGeneration, readGeneration == usageReadGeneration, !Task.isCancelled else { return }
        usageRecords = records; usageUnavailable = pluginUnavailable; itemUsageUnavailable = itemUnavailable
        cachedVisible = nil
        // Usage changes reorder recency views, but name-sorted outline identities
        // and hierarchy do not change. Keep their prebuilt trees for tab returns.
        if sort == .recency { invalidateOutline() } else { cachedOutline = nil }
        onChange?()
    }
    public func usageRecord(_ asset: Asset, grouped: Bool = true) -> AssetDateEvidence? {
        if asset.kind == .plugin, grouped, let productID = asset.pluginProductID,
           let record = usageRecords[Data(productID.utf8)] { return record }
        if asset.kind != .plugin, let id = asset.catalogID { return usageRecords[Data(id.utf8)] }
        let items = grouped ? product(for: asset)?.installations ?? [asset] : [asset]
        return items.compactMap { item -> AssetDateEvidence? in
            guard let id = item.catalogID, assetsByKey["plugin:" + item.selectionKey]?.catalogID == id else { return nil }
            return usageRecords[Data(id.utf8)]
        }.sorted { HostUsageOrdering.precedes($0, $1) }.first
    }
    private func usageDay(_ record: AssetDateEvidence) -> String {
        HostUsageOrdering.dayKey(record)
    }
    public func lastUsed(_ asset: Asset) -> UsageDatePresentation {
        let plugin = asset.kind == .plugin
        return UsageDatePresentation(record: usageRecord(asset), unavailable: plugin ? usageUnavailable : itemUsageUnavailable,
            checking: plugin ? (isCollectingUsage || (isScanning && scanningKinds.contains(.plugin)))
                : (isLoadingItemUsage || (isScanning && scanningKinds.contains(asset.kind == .library ? .library : .sample))),
            saved: usingSavedCatalog || asset.catalogStale == true,
            incomplete: plugin ? (usageCollection.map { $0.failures > 0 } ?? false) : false, formatCoverage: "")
    }
    public func instrumentUsageRecord(parent: Asset, instrument: LibraryInstrument) -> AssetDateEvidence? {
        guard let parentID = parent.catalogID else { return nil }
        let key = AssetUsageSubject.instrumentUsageKey(parentNodeID: parentID, instrument: instrument)
        return usageRecords[Data(key.utf8)]
    }
    public func instrumentLastUsed(_ parent: Asset, instrument: LibraryInstrument) -> UsageDatePresentation {
        UsageDatePresentation(record: instrumentUsageRecord(parent: parent, instrument: instrument),
            unavailable: itemUsageUnavailable, checking: isLoadingItemUsage || (isScanning && scanningKinds.contains(.library)),
            saved: usingSavedCatalog || instrument.catalogStale == true,
            incomplete: false)
    }
    private var usageDays: [String: String] {
        guard sort == .recency else { return [:] }
        var values = Dictionary((report?.assets ?? []).compactMap { asset in
            usageRecord(asset).map { (asset.path, usageDay($0)) }
        }, uniquingKeysWith: { first, _ in first })
        for library in report?.assets ?? [] where library.kind == .library {
            for instrument in library.libraryMetadata?.instruments ?? [] {
                if let record = instrumentUsageRecord(parent: library, instrument: instrument) {
                    guard let parentID = library.catalogID else { continue }
                    values[AssetUsageSubject.instrumentUsageKey(parentNodeID: parentID, instrument: instrument)] = usageDay(record)
                }
            }
        }
        return values
    }
    private func cancelUsageCollection() {
        usageGeneration = UUID(); usageReadGeneration = UUID(); usageTask?.cancel(); usageTask = nil; isCollectingUsage = false; usageCollection = nil
    }
    private func startUsageCollection() {
        guard let usageCollector, let catalogStore, !isScanning, !configurationChanged else { return }
        cancelUsageCollection()
        let generation = usageGeneration
        usageTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let inventory = self?.report?.assets, self?.usageGeneration == generation else { return }
                let assets = inventory.filter { $0.kind == .plugin }
                guard !Task.isCancelled, self?.usageGeneration == generation else { return }
                do {
                    self?.isCollectingUsage = true; self?.onChange?()
                    let result = await usageCollector(assets, catalogStore)
                    guard !Task.isCancelled, self?.usageGeneration == generation else { return }
                    self?.usageCollection = result; self?.isCollectingUsage = false
                    await self?.reloadUsage()
                }
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }
    public var dateColumnTitle: String { "Date added" }

    public func pluginSize(_ asset: Asset, grouped: Bool = true) -> PluginSizePresentation {
        let items = grouped ? product(for: asset)?.installations ?? [asset] : [asset]
        var subtotal = 0, known = 0, overflow = false
        for item in items {
            guard let bytes = item.logicalBytes, bytes >= 0 else { continue }
            let (next, didOverflow) = subtotal.addingReportingOverflow(bytes)
            if didOverflow { overflow = true; break }
            subtotal = next; known += 1
        }
        let complete = !overflow && known == items.count ? subtotal : nil
        func formatted(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
        let value = complete.map(formatted) ?? (known > 0 ? "Partial" : "Unknown")
        var detail = complete.map { "Measured bundle files: " + formatted($0) + "." }
            ?? (known > 0 ? "Known subtotal " + formatted(subtotal) + " across \(known) of \(items.count) installations; total unknown."
                : "Bundle size unavailable; see Scan details for file-access issues.")
        if usingSavedCatalog || items.contains(where: { $0.catalogStale == true }) {
            detail += complete == nil && known == 0
                ? " Saved collection; choose Check For Updates to measure bundle size."
                : " Saved size; choose Check For Updates to verify current files."
        }
        return PluginSizePresentation(completeBytes: complete, value: value, detail: detail,
                                      accessibility: "Size, " + value + ". " + detail)
    }

    public func additionEvidence(_ asset: Asset, grouped: Bool = true) -> AdditionDateEvidence? {
        if asset.kind != .plugin, let date = asset.finderDateAdded,
           let id = asset.catalogID,
           assetsByKey[asset.kind.rawValue + ":" + asset.selectionKey]?.catalogID == id {
            return try? AdditionDateEvidence(basis: .exact, lower: date, upper: date)
        }
        if asset.kind == .plugin, let productID = asset.pluginProductID, let known = pluginConfirmedAdditionDates[productID] {
            return try? AdditionDateEvidence(basis: .exact, lower: known, upper: known)
        }
        if asset.kind == .plugin, let productID = asset.pluginProductID, let known = pluginProductDates[productID] {
            return try? AdditionDateEvidence(basis: .exact, lower: known, upper: known)
        }
        let items = grouped && asset.kind == .plugin ? product(for: asset)?.installations ?? [asset] : [asset]
        if asset.kind == .plugin {
            let finderDates = items.compactMap { item -> Date? in
                guard let id = item.catalogID,
                      let current = assetsByKey[item.kind.rawValue + ":" + item.selectionKey]?.catalogID,
                      id.utf8.elementsEqual(current.utf8) else { return nil }
                return item.finderDateAdded
            }
            if let earliest = finderDates.min() {
                return try? AdditionDateEvidence(basis: .exact, lower: earliest, upper: earliest)
            }
        }
        let dates = items.map { item -> Date? in
            guard let id = item.catalogID,
                  let current = assetsByKey[item.kind.rawValue + ":" + item.selectionKey]?.catalogID,
                  id.utf8.elementsEqual(current.utf8) else { return nil }
            return confirmedAdditionDates[Data(id.utf8)]
        }
        guard dates.count == items.count, dates.allSatisfy({ $0 != nil }), let earliest = dates.compactMap({ $0 }).min() else { return nil }
        return try? AdditionDateEvidence(basis: .exact, lower: earliest, upper: earliest)
    }

    public func additionDate(_ asset: Asset, grouped: Bool = true) -> AdditionDatePresentation {
        let items = grouped && asset.kind == .plugin ? product(for: asset)?.installations ?? [asset] : [asset]
        let known = items.filter { additionEvidence($0, grouped: false) != nil }.count
        let coverage = items.count > 1 && known > 0 && known < items.count
            ? "Original dates known for \(known) of \(items.count) formats." : ""
        let saved = usingSavedCatalog || items.contains { assetsByKey[$0.kind.rawValue + ":" + $0.selectionKey]?.catalogStale == true }
        let finderCount = asset.kind == .plugin ? items.filter { item in
            guard let id = item.catalogID,
                  let current = assetsByKey[item.kind.rawValue + ":" + item.selectionKey]?.catalogID,
                  id.utf8.elementsEqual(current.utf8) else { return false }
            return item.finderDateAdded != nil
        }.count : 0
        let observations = items.compactMap { item -> (String, CatalogObservation)? in
            guard let id = item.catalogID, let observation = catalogObservations[id] else { return nil }
            return (PluginProduct.formatName(item.format), observation)
        }
        let observation: String
        if observations.count > 1,
           let first = observations.first?.1,
           observations.allSatisfy({ Calendar.current.isDate($0.1.firstSeen, inSameDayAs: first.firstSeen) && $0.1.addition?.basis != .observedArrival }) {
            observation = "First indexed " + first.firstSeen.formatted(date: .abbreviated, time: .omitted)
                + " across \(observations.count) formats; scan does not establish the original date."
        } else {
            observation = observations.map { format, item in
                let prefix = items.count > 1 ? format + ": " : ""
                if item.addition?.basis == .observedArrival, let lower = item.addition?.lower, let upper = item.addition?.upper {
                    return prefix + "Observed arrival " + lower.formatted(date: .abbreviated, time: .omitted)
                        + "–" + upper.formatted(date: .abbreviated, time: .omitted) + "; original date unknown."
                }
                return prefix + "First indexed " + item.firstSeen.formatted(date: .abbreviated, time: .omitted)
                    + "; scan does not establish the original date."
            }.joined(separator: "\n")
        }
        let hasFinderDate = asset.finderDateAdded != nil || asset.pluginProductID.flatMap { pluginProductDates[$0] } != nil || finderCount > 0
        let hasConfirmedOriginal = asset.kind == .plugin && asset.pluginProductID.flatMap { pluginConfirmedAdditionDates[$0] } != nil
        let source = hasConfirmedOriginal && hasFinderDate
            ? "A qualified original-addition record takes precedence over Finder Date Added, which describes entry into the current location."
            : hasFinderDate
            ? (asset.kind == .plugin
               ? "Finder Date Added is when a file moved into its current location; earliest available format date. It does not prove installation."
               : "Earliest filesystem Date Added recorded for this item, retained across moves. It does not prove purchase or original installation.")
            : ""
        let arrivals = observations.compactMap { item -> (Date, Date)? in
            guard item.1.addition?.basis == .observedArrival,
                  let lower = item.1.addition?.lower, let upper = item.1.addition?.upper else { return nil }
            return (lower, upper)
        }
        let history: String
        if asset.kind == .plugin, !arrivals.isEmpty,
           let lower = arrivals.map(\.0).min(), let upper = arrivals.map(\.1).max() {
            history = "Observed arrival " + lower.formatted(date: .abbreviated, time: .omitted)
                + "–" + upper.formatted(date: .abbreviated, time: .omitted)
                + "; a move or restored copy is possible."
        } else if asset.kind == .plugin, let firstSeen = observations.map({ $0.1.firstSeen }).min() {
            history = "First indexed " + firstSeen.formatted(date: .abbreviated, time: .omitted)
                + "; scan does not establish Date added."
        } else { history = observation }
        return AdditionDatePresentation(evidence: additionEvidence(asset, grouped: grouped), coverage: hasFinderDate ? "" : coverage, saved: saved,
                                        checking: isScanning && scanningKinds.contains(asset.kind), observation: [source, history].filter { !$0.isEmpty }.joined(separator: "\n"),
                                        finderDateAdded: hasFinderDate && !hasConfirmedOriginal, finderSourceExpected: asset.kind == .plugin)
    }
    public func instrumentAdditionDate(_ instrument: LibraryInstrument) -> AdditionDatePresentation {
        let evidence = instrument.finderDateAdded.flatMap { try? AdditionDateEvidence(basis: .exact, lower: $0, upper: $0) }
        return AdditionDatePresentation(evidence: evidence,
                                        observation: evidence == nil ? "" : "Earliest filesystem Date Added recorded for this patch, retained across moves. It does not prove purchase or original installation.",
                                        finderDateAdded: evidence != nil,
                                        finderSourceExpected: true)
    }

    /// Reload one atomic, bounded projection. Late reads cannot publish into a new scope.
    public func reloadInstallerRecords() async {
        let generation = UUID(); installerReadGeneration = generation
        let scopeGeneration = receiptGeneration
        guard let catalogStore else { return }
        let ids = (report?.assets ?? []).filter { $0.kind == .plugin }.compactMap(\.catalogID)
        isLoadingInstallerRecords = true; onChange?()
        do {
            let values: [Data: AssetDateEvidence]
            if let installerRecordLoader { values = try await installerRecordLoader(catalogStore, ids, Date()) }
            else { values = try await catalogStore.latestInstallerRecords(for: ids, asOf: Date()) }
            let additionIDs = (report?.assets ?? []).compactMap(\.catalogID)
            var additions: [Data: Date] = [:]
            for start in stride(from: 0, to: additionIDs.count, by: 2_048) {
                let end = min(start + 2_048, additionIDs.count)
                let batch = try await catalogStore.confirmedAdditionDates(for: Array(additionIDs[start..<end]), asOf: Date())
                additions.merge(batch) { first, _ in first }
            }
            let productAdditions = try await catalogStore.productConfirmedAdditionDates(for: pluginProducts.map(\.id), asOf: Date())
            guard installerReadGeneration == generation, receiptGeneration == scopeGeneration, !Task.isCancelled else { return }
            installerRecords = values; confirmedAdditionDates = additions; pluginConfirmedAdditionDates = productAdditions; installerRecordsUnavailable = false
        } catch {
            guard installerReadGeneration == generation, receiptGeneration == scopeGeneration, !Task.isCancelled else { return }
            installerRecords = [:]; confirmedAdditionDates = [:]; pluginConfirmedAdditionDates = [:]; installerRecordsUnavailable = true
        }
        isLoadingInstallerRecords = false; cachedVisible = nil; invalidateOutline(); onChange?()
    }

    private func installerRecord(_ asset: Asset) -> AssetDateEvidence? {
        guard let id = asset.catalogID, let current = assetsByKey["plugin:" + asset.path]?.catalogID,
              id.utf8.elementsEqual(current.utf8) else { return nil }
        return installerRecords[Data(id.utf8)]
    }

    public func installerDate(_ asset: Asset, grouped: Bool = true) -> InstallerDatePresentation {
        guard asset.kind == .plugin else {
            return InstallerDatePresentation(date: nil, value: "Unknown", detail: "Original Date added is unknown.", accessibility: "Date added unknown")
        }
        let checking = isLoadingInstallerRecords || isCollectingInstallerRecords || (isScanning && scanningKinds.contains(.plugin))
        if isScanning && scanningKinds.contains(.plugin) {
            return InstallerDatePresentation(date: nil, value: "Checking…", detail: "Checking current installations…", accessibility: "Installer record checking current installations")
        }
        var seen = Set<Data>()
        let items = (grouped ? product(for: asset)?.installations ?? [asset] : [asset]).filter {
            seen.insert(Data(($0.catalogID ?? ("path:" + $0.path)).utf8)).inserted
        }
        let known = items.compactMap { item -> (Asset, AssetDateEvidence)? in installerRecord(item).map { (item, $0) } }.sorted { a, b in
            if a.1.eventDate != b.1.eventDate { return a.1.eventDate! > b.1.eventDate! }
            let left = [a.1.subjectID, a.1.sourceID, a.1.evidenceID], right = [b.1.subjectID, b.1.sourceID, b.1.evidenceID]
            for (x, y) in zip(left, right) where !x.utf8.elementsEqual(y.utf8) { return x.utf8.lexicographicallyPrecedes(y.utf8) }
            return false
        }
        let coverage = "Records for \(known.count) of \(items.count) installations"
        var detail: [String] = []
        if let (item, record) = known.first, let date = record.eventDate {
            detail.append("Latest installer record   " + date.formatted(date: .abbreviated, time: .omitted))
            detail.append(PluginProduct.formatName(item.format) + " · " + coverage)
        } else {
            detail.append("Installer record   " + (installerRecordsUnavailable ? "Unavailable" : checking ? "Checking…" : "Unknown"))
        }
        if installerRecordsUnavailable { detail.append("Saved installer records could not be read. Choose Check For Updates to retry.") }
        else if checking { detail.append(known.isEmpty ? "Checking installer records…" : "Checking for newer records…") }
        else if receiptCollection?.status == .incomplete || receiptCollection?.status == .cancelled {
            detail.append("Installer records could not be fully checked. Choose Check For Updates to retry.")
        } else if known.isEmpty { detail.append("No matching installer record available.") }
        if !known.isEmpty {
            detail.append("May record an install or update; separate from Finder Date Added.")
            if usingSavedCatalog || items.contains(where: { assetsByKey["plugin:" + $0.path]?.catalogStale == true }) {
                detail.append("Saved record; current installation not verified.")
            }
        }
        let date = known.first?.1.eventDate
        let value = date?.formatted(date: .numeric, time: .omitted) ?? (installerRecordsUnavailable ? "Unavailable" : checking ? "Checking…" : "Unknown")
        let accessible = "Latest installer record, " + (date?.formatted(date: .complete, time: .omitted) ?? value) + "; " + coverage + ". " + detail.joined(separator: ". ")
        return InstallerDatePresentation(date: date, value: value, detail: detail.joined(separator: "\n"), accessibility: accessible)
    }

    public func installerRecordDetail(_ asset: Asset) -> String {
        let presentation = installerDate(asset, grouped: false)
        guard let record = installerRecord(asset), let provenance = record.packageReceipt,
              presentation.date != nil else { return presentation.detail }
        return presentation.detail
            + "\nRecorded " + record.eventDate!.formatted(date: .abbreviated, time: .shortened)
            + "\nPackage version " + provenance.packageVersion + " · " + provenance.packageID
    }

    public typealias ReceiptCollector = @Sendable ([Asset], CatalogStore) async -> PackageReceiptCollection
    public private(set) var receiptCollection: PackageReceiptCollection?
    private let receiptCollector: ReceiptCollector?
    private var receiptTask: Task<Void, Never>?
    private var receiptGeneration = UUID()

    deinit {
        receiptTask?.cancel(); usageTask?.cancel(); scanTask?.cancel(); foregroundTask?.cancel()
        for preparation in outlinePreparations.values { preparation.task.cancel() }
    }

    private func cancelReceiptCollection() {
        cancelUsageCollection()
        receiptGeneration = UUID(); receiptTask?.cancel(); receiptTask = nil; receiptCollection = nil
        installerReadGeneration = UUID(); isLoadingInstallerRecords = false; isCollectingInstallerRecords = false
    }
    private func collectReceipts(_ assets: [Asset]) {
        guard let receiptCollector, let catalogStore, !assets.isEmpty else { return }
        let generation = receiptGeneration
        isCollectingInstallerRecords = true
        receiptTask = Task { [weak self] in
            let worker = Task.detached(priority: .utility) { await receiptCollector(assets, catalogStore) }
            let result = await withTaskCancellationHandler(operation: {
                if Task.isCancelled { worker.cancel() }
                return await worker.value
            }, onCancel: { worker.cancel() })
            guard let self, !Task.isCancelled, self.receiptGeneration == generation else { return }
            self.isCollectingInstallerRecords = false
            await self.reloadInstallerRecords()
            guard !Task.isCancelled, self.receiptGeneration == generation else { return }
            self.receiptCollection = result; self.receiptTask = nil; self.onChange?()
        }
    }

    private let catalogStore: CatalogStore?
    private let store: SetupStore?
    private var setupWasMissing = false
    private let sineDatabase: URL

    public init(store: SetupStore? = nil, sineDatabase: URL = LibraryMetadataReader.sineDatabase, catalogStore: CatalogStore? = nil,
                receiptCollector: ReceiptCollector? = nil, usageCollector: UsageCollector? = nil, usageLoader: UsageLoader? = nil,
                installerRecordLoader: InstallerRecordLoader? = nil,
                tagStore: ProductTagStore? = nil, tagSources: [ProductTagSource] = ProductTagSources.all,
                sharedTagStore: SharedProductTagStore? = .application, savedProjectUsageOnly: Bool = false) {
        self.tagStore = tagStore
        self.sharedTagStore = sharedTagStore
        let acceptedSources = tagSources.count <= ProductTagSources.maximumSources ? tagSources : []
        self.tagSources = acceptedSources
        var sourceIndex: [String: [ProductTagSource]] = [:]
        for source in acceptedSources {
            for name in source.names {
                let key = source.kind.rawValue + ":" + ProductTagSource.identity(name)
                sourceIndex[key, default: []].append(source)
            }
        }
        self.tagSourcesByName = sourceIndex
        self.usageLoader = usageLoader; self.usageCollector = usageCollector
        self.savedProjectUsageOnly = savedProjectUsageOnly
        self.catalogStore = catalogStore; self.receiptCollector = receiptCollector; self.installerRecordLoader = installerRecordLoader
        self.store = store; self.sineDatabase = sineDatabase
        do {
            let savedSetup = try store?.load()
            setupWasMissing = store != nil && savedSetup == nil
            if let values = savedSetup {
                standardPlugins = values["standard_plugins"] as? Bool ?? true
                appearance = CatalogAppearance(rawValue: values["appearance"] as? String ?? "light") ?? .light
                onboardingCompleted = values["onboarding_completed"] as? Bool ?? false
                for (key, paths) in values["roots"] as? [String: [String]] ?? [:] {
                    if let kind = RootKind(rawValue: key) { roots[kind] = paths.map { URL(fileURLWithPath: $0) } }
                }
            }
        } catch { setupNotice = error.localizedDescription }
    }

    public func productTagSource(_ asset: Asset) -> ProductTagSource? {
        let installations = asset.kind == .plugin ? product(for: asset)?.installations ?? [asset] : [asset]
        var matches: [String: ProductTagSource] = [:]
        for installation in installations {
            let key = installation.kind.rawValue + ":" + ProductTagSource.identity(installation.name)
            for source in tagSourcesByName[key] ?? [] where source.matches(installation, libraryRoots: roots[.libraries] ?? []) {
                matches[source.id] = source
            }
        }
        let curated = matches.values.filter { $0.provenance == .curated }
        if curated.count == 1 { return curated[0] }
        if curated.count > 1 { return nil }
        return matches.count == 1 ? matches.values.first : nil
    }
    public func productTagProvenance(_ asset: Asset) -> String {
        var details: [String] = []
        if let source = productTagSource(asset) {
            let label = source.provenance == .automatic ? "Automatic official-source suggestion " : "Reviewed metadata record "
            if let record = tagRecords[source.id] {
                details.append(label + source.reviewRecordID + " v\(source.taxonomyVersion), refreshed " + record.fetchedAt.formatted(date: .abbreviated, time: .shortened) + "\n" + source.page.absoluteString
                    + "\nFetched " + record.fetchedAt.formatted(date: .abbreviated, time: .shortened)
                    + (record.isFresh() ? "" : " · cached; refresh needed"))
            } else {
                details.append(label + source.reviewRecordID + " v\(source.taxonomyVersion), " +
                    (source.provenance == .automatic ? "identified " : "reviewed ") + source.reviewedAt + "\n" + source.page.absoluteString)
            }
            if let fact = source.sourceFact { details.append(fact) }
        }
        let installations = product(for: asset)?.installations ?? [asset]
        let categories = Set(installations.flatMap { $0.vst3Categories?.subCategories ?? [] }).sorted()
        if !categories.isEmpty { details.append("Vendor VST3 moduleinfo.json categories (exact/shared Audio Module class facts): " + categories.joined(separator: ", ")) }
        return details.isEmpty ? "No reviewed or vendor category metadata for this product." : details.joined(separator: "\n\n")
    }
    private func loadTagCaches() async {
        if !tagCacheLoaded {
            tagRecords = (try? await tagStore?.load()) ?? [:]
            tagCacheLoaded = true
        }
        await loadSharedTagCache()
    }

    private func installSharedSources(_ remote: [ProductTagSource]) {
        var byID = Dictionary(uniqueKeysWithValues: tagSources.map { ($0.id, $0) })
        let retiredDuplicateIDs: Set<String> = [
            "external-p-9640216ff252", "external-p-5993ed435e63", "external-p-f3830ef59264"
        ]
        for source in remote {
            // Historical cache entries for these merged sources must not resurrect duplicates.
            guard !retiredDuplicateIDs.contains(source.id), byID[source.id] == nil else { continue }
            byID[source.id] = source
        }
        guard byID.count <= ProductTagSources.maximumSources else { return }
        tagSources = byID.values.sorted { $0.id < $1.id }
        var index: [String: [ProductTagSource]] = [:]
        for source in tagSources {
            for name in source.names {
                index[source.kind.rawValue + ":" + ProductTagSource.identity(name), default: []].append(source)
            }
        }
        tagSourcesByName = index
        suggestedMetadataBySubject.removeAll(keepingCapacity: true)
        invalidateOutline(); cachedVisible = nil; onChange?()
    }

    /// Load only previously saved, validated facts; this path performs no requests.
    private func loadSharedTagCache() async {
        guard !sharedTagCacheLoaded else { return }
        guard let sharedTagStore else { sharedTagCacheLoaded = true; return }
        if sharedTagCacheTask == nil {
            sharedTagCacheTask = Task { try? await sharedTagStore.load() }
        }
        let snapshot = await sharedTagCacheTask!.value
        guard !sharedTagCacheLoaded else { return }
        sharedTagCacheLoaded = true; sharedTagCacheTask = nil
        guard let snapshot else { return }
        var sources: [ProductTagSource] = []
        if let body = snapshot.catalogData,
           let cached = try? ProductTagSources.importSharedCatalog(body) { sources += cached }
        for body in snapshot.identifiedRecords.values {
            if let cached = try? ProductTagSources.importSharedCatalog(body) { sources += cached }
        }
        if !sources.isEmpty { installSharedSources(sources) }
    }

    public func setupDraft() -> CatalogModel {
        let draft = CatalogModel(sineDatabase: sineDatabase)
        draft.standardPlugins = standardPlugins; draft.roots = roots; draft.appearance = appearance
        return draft
    }

    public func acceptSetup(_ draft: CatalogModel, remember: Bool, completeOnboarding: Bool = true) throws {
        guard !isBusy else { return }
        if report != nil {
            for kind in RootKind.allCases where roots[kind] != draft.roots[kind] { draft.dirtyCategories.formUnion(affectedCategories(kind)) }
            if standardPlugins != draft.standardPlugins { draft.dirtyCategories.insert(.plugin) }
        }
        var values = draft.stateSnapshot; values["onboarding_completed"] = completeOnboarding || onboardingCompleted
        if remember { try store?.save(values) }
        if standardPlugins != draft.standardPlugins || roots != draft.roots { cancelReceiptCollection() }
        standardPlugins = draft.standardPlugins; roots = draft.roots; appearance = draft.appearance
        invalidateOutline()
        onboardingCompleted = completeOnboarding || onboardingCompleted; dirtyCategories.formUnion(draft.dirtyCategories)
        setupNotice = remember ? nil : "Setup is being used for this session only."
        onChange?()
    }

    public func reset() {
        guard !isBusy else { return }
        catalogStore?.clearDiscoveryJournals()
        cancelReceiptCollection()
        installerRecords = [:]; confirmedAdditionDates = [:]; installerRecordsUnavailable = false
        usageRecords = [:]; usageUnavailable = false; itemUsageUnavailable = false; isLoadingItemUsage = false
        recentOnly = false; usageFilter = .all; musicalFilter = [:]; metadataOverrides = [:]; metadataUndo = []
        scanIdentifier = UUID(); usingSavedCatalog = false; savedCatalogDate = nil; catalogObservations = [:]; catalogNotice = nil
        outlineState.reset(); outlineBases = [:]; previousOutlineBases = [:]; cachedOutline = nil
        category = .plugin; query = ""; sort = .name; sortReversed = false; standardPlugins = true; appearance = .light
        roots = [:]; selectedPath = nil; selectedProductID = nil; report = nil; pluginProductDates = [:]; pluginProductNames = [:]; dirtyCategories = []; scanningKinds = []; onboardingCompleted = false; setupNotice = nil; scanProgress = nil; scanStartedAt = nil; basicInventoryComplete = false; isBackgroundScanning = false
        onChange?()
    }

    public func addRoots(_ urls: [URL], kind: RootKind) {
        guard !isBusy else { return }
        cancelReceiptCollection()
        for raw in urls {
            let url = raw.standardizedFileURL
            if !(roots[kind] ?? []).contains(url) { roots[kind, default: []].append(url) }
        }
        invalidateOutline()
        if report != nil { dirtyCategories.formUnion(affectedCategories(kind)) }
        onChange?()
    }

    public func removeRoot(_ url: URL, kind: RootKind) {
        guard !isBusy else { return }
        cancelReceiptCollection()
        roots[kind]?.removeAll { $0 == url }
        invalidateOutline()
        if report != nil { dirtyCategories.formUnion(affectedCategories(kind)) }
        onChange?()
    }

    public func setStandardPlugins(_ enabled: Bool) {
        guard !isBusy else { return }
        if standardPlugins != enabled { cancelReceiptCollection() }
        standardPlugins = enabled; if report != nil { dirtyCategories.insert(.plugin) }; onChange?()
    }

    private func affectedCategories(_ kind: RootKind) -> Set<AssetKind> {
        switch kind { case .plugins: [.plugin]; case .samples, .libraries: [.sample, .library]; case .projects: [.sample] }
    }

    private var scanRequest: ScanRequest {
        var request = ScanRequest()
        request.plugins = (standardPlugins ? ScanRequest.standardPluginRoots : []) + (roots[.plugins] ?? [])
        if standardPlugins {
            let configured = Set((roots[.plugins] ?? []).map { $0.standardizedFileURL.path })
            request.optionalPluginRoots = ScanRequest.standardPluginRoots.filter { !configured.contains($0.standardizedFileURL.path) }
        }
        request.samples = roots[.samples] ?? []; request.libraries = roots[.libraries] ?? []
        request.projects = roots[.projects] ?? []
        return request
    }

    /// Restore without blocking native interaction; late results cannot replace a scan/setup change.
    public func restoreSavedCatalog() async {
        guard let catalogStore, report == nil, !isScanning, !isRestoringCatalog else { return }
        let identifier = scanIdentifier
        var intendedScope = CatalogScope(scanRequest)
        isRestoringCatalog = true
        defer { isRestoringCatalog = false; onChange?() }
        await loadTagCaches()
        do {
            if setupWasMissing && !onboardingCompleted && roots.values.allSatisfy(\.isEmpty),
               let savedScope = try await catalogStore.mostRecentSavedScope() {
                let standard = Set(ScanRequest.standardPluginRoots.map { $0.standardizedFileURL.path })
                let savedPlugins = Set(savedScope.roots["plugins"] ?? [])
                standardPlugins = standard.isSubset(of: savedPlugins)
                roots[.plugins] = (savedPlugins.subtracting(standardPlugins ? standard : [])).sorted().map { URL(fileURLWithPath: $0) }
                for (kind, key) in [(RootKind.samples, "samples"), (.libraries, "libraries"), (.projects, "projects")] {
                    roots[kind] = (savedScope.roots[key] ?? []).map { URL(fileURLWithPath: $0) }
                }
            }
            let scope = CatalogScope(scanRequest)
            intendedScope = scope
            let snapshot = try await catalogStore.load(scope: scope)
            guard identifier == scanIdentifier, scope.roots == CatalogScope(scanRequest).roots, report == nil else { return }
            if let snapshot {
                let (enriched, indexes) = await Task.detached(priority: .utility) {
                    let assets = KontaktCategoryReader.enrich(snapshot.report.assets)
                    let withVST3 = VST3ModuleInfoReader.enrich(assets, cacheBaseURL: catalogStore.url)
                    let report = snapshot.report.replacingAssets(withVST3)
                    return (report, Self.makeIndexes(report: report, names: snapshot.pluginProductNames))
                }.value
                let preparedLibrary = prepareNameSortedLibraryOutline(enriched)
                let (suggestions, durableKeys) = await prewarmLibraryMetadata(enriched)
                guard identifier == scanIdentifier, scope.roots == CatalogScope(scanRequest).roots, report == nil else { return }
                pluginProductNames = snapshot.pluginProductNames
                preparedIndexes = indexes
                report = enriched; suggestedMetadataBySubject = suggestions
                let publishedRevision = reportRevision
                durableMetadataSubjectsByCacheKey = durableKeys; savedCatalogDate = snapshot.savedAt
                onboardingCompleted = true
                catalogObservations = snapshot.observations; metadataOverrides = snapshot.metadata; pluginProductDates = snapshot.pluginProductDates; usingSavedCatalog = true
                await reloadInstallerRecords(); await reloadUsage()
                guard identifier == scanIdentifier, scope.roots == CatalogScope(scanRequest).roots, !isScanning else { return }
                await installNameSortedLibraryOutline(preparedLibrary, identifier: identifier, scope: scope,
                                                      reportRevision: publishedRevision)
                guard identifier == scanIdentifier, scope.roots == CatalogScope(scanRequest).roots, !isScanning else { return }
                startUsageCollection()
            }
        } catch {
            guard identifier == scanIdentifier, intendedScope.roots == CatalogScope(scanRequest).roots else { return }
            catalogNotice = error.localizedDescription
        }
    }

    private func applyInventory(_ update: InventorySnapshot, identifier: UUID,
                                priorReport: ScanReport?, scannedKinds: Set<AssetKind>,
                                preserveExisting: Bool) async {
        // Let the active view finish before replacing its source. Faster producer
        // updates coalesce in the one-element stream instead of starving display.
        if let preparation = outlinePreparations[category] { await preparation.task.value }
        guard isScanning, acceptingInventory, scanIdentifier == identifier, !Task.isCancelled,
              update.sequence > inventorySequence else { return }
        // Each update is cumulative. Preserve identities against the stable
        // pre-scan report, with the large merge on a worker.
        let names = pluginProductNames
        let (next, indexes) = await Task.detached(priority: .utility) {
            let next: ScanReport
            if let prior = priorReport {
            func key(_ asset: Asset) -> String { asset.kind.rawValue + ":" + asset.path + ":" + (asset.libraryMetadata?.identity?.productID ?? "") }
            var merged = Dictionary(prior.assets.filter { preserveExisting || !scannedKinds.contains($0.kind) }
                .map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
            for var asset in update.assets {
                if asset.kind == .plugin {
                    if let previous = merged[key(asset)], let identity = asset.fileIdentity,
                       previous.fileIdentity == identity, previous.bundleIdentifier == asset.bundleIdentifier {
                        asset.catalogID = previous.catalogID; asset.pluginProductID = previous.pluginProductID
                    }
                } else { asset.catalogID = merged[key(asset)]?.catalogID }
                merged[key(asset)] = asset
            }
                next = ScanReport(inventory: update).merging(previous: priorReport, scannedKinds: scannedKinds)
                .replacingAssets(Array(merged.values))
            } else { next = ScanReport(inventory: update) }
            return (next, Self.makeIndexes(report: next, names: names))
        }.value
        guard isScanning, acceptingInventory, scanIdentifier == identifier, !Task.isCancelled,
              update.sequence > inventorySequence else { return }
        preparedIndexes = indexes
        report = next
        inventorySequence = update.sequence; basicInventoryComplete = update.discoveryComplete
        isBackgroundScanning = true
        onChange?()
    }

    public func scan(scannedKinds: Set<AssetKind> = Set(AssetKind.allCases)) {
        guard !scannedKinds.isEmpty else { return }
        guard !isBusy else { return }
        cancelReceiptCollection()
        let request = scanRequest
        scanningKinds = scannedKinds
        let priorReport = report
        scanIdentifier = UUID(); let identifier = scanIdentifier
        scanStartedAt = Date(); scanProgress = nil; catalogNotice = nil; inventorySequence = 0; basicInventoryComplete = false
        isBackgroundScanning = report != nil
        foregroundTask?.cancel()
        foregroundTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, self.isScanning, self.scanIdentifier == identifier else { return }
            self.isBackgroundScanning = true; self.onChange?()
        }
        isScanning = true; acceptingInventory = true; onChange?()
        let snapshot = request; let database = sineDatabase; let journalBaseURL = catalogStore?.url
        let preserveExisting = dirtyCategories.isDisjoint(with: scannedKinds)
        let updates = AsyncStream<InventorySnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        scanTask = Task { [weak self] in
            // One consumer, one pending snapshot. The producer replaces pending
            // inventory before scheduling UI work, so a slow frame cannot queue
            // many retained copies of the entire collection.
            let inventoryTask = Task { @MainActor [weak self] in
                for await update in updates.stream {
                    guard !Task.isCancelled else { break }
                    await self?.applyInventory(update, identifier: identifier, priorReport: priorReport,
                                               scannedKinds: scannedKinds, preserveExisting: preserveExisting)
                    await Task.yield()
                }
            }
            defer { updates.continuation.finish(); inventoryTask.cancel() }
            let worker = Task.detached(priority: .utility) { [weak self] in
                defer { updates.continuation.finish() }
                let context = AdditionScanContext(scope: CatalogScope(snapshot))
                let result = Scanner(sineDatabase: database, journalBaseURL: journalBaseURL).scan(snapshot,
                    scannedKinds: scannedKinds, previousProjects: priorReport?.projects ?? [], inventory: { update in
                    updates.continuation.yield(update)
                }) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self, self.isScanning, self.scanIdentifier == identifier,
                              update.sequence > (self.scanProgress?.sequence ?? 0) else { return }
                        self.scanProgress = update; self.onProgressChange?()
                    }
                }
                return (result, context)
            }
            let (result, additionContext) = await withTaskCancellationHandler(operation: {
                if Task.isCancelled { worker.cancel() }
                return await worker.value
            }, onCancel: { worker.cancel(); updates.continuation.finish(); inventoryTask.cancel() })
            await inventoryTask.value
            guard let self else { return }
            guard self.scanIdentifier == identifier, !Task.isCancelled else {
                if self.scanIdentifier == identifier { self.finishCancelledScan(priorReport: priorReport) }
                return
            }
            self.acceptingInventory = false
            let enrichedResult = await Task.detached(priority: .utility) {
                result.replacingAssets(VST3ModuleInfoReader.enrich(result.assets, cacheBaseURL: journalBaseURL))
            }.value
            guard self.scanIdentifier == identifier, !Task.isCancelled else {
                if self.scanIdentifier == identifier { self.finishCancelledScan(priorReport: priorReport) }
                return
            }
            let selectedAsset = self.selectedAsset
            var preparedLibrary: (task: Task<CatalogOutline, Never>, reversed: Bool)?
            var publishedRevision: Int?
            if priorReport == nil || self.catalogStore == nil {
                let names = self.pluginProductNames
                let (published, indexes) = await Task.detached(priority: .utility) {
                    let published = enrichedResult.merging(previous: priorReport, scannedKinds: scannedKinds)
                    return (published, Self.makeIndexes(report: published, names: names))
                }.value
                guard self.scanIdentifier == identifier, !Task.isCancelled else {
                    if self.scanIdentifier == identifier { self.finishCancelledScan(priorReport: priorReport) }
                    return
                }
                self.preparedIndexes = indexes
                self.report = published
                self.usingSavedCatalog = false
                self.onChange?()
            }
            if let catalogStore = self.catalogStore {
                do {
                    let saved = try await catalogStore.ingest(enrichedResult, scope: CatalogScope(snapshot), scannedKinds: scannedKinds, additionContext: additionContext, libraryJournalSource: database)
                    guard self.scanIdentifier == identifier, !Task.isCancelled else {
                        if self.scanIdentifier == identifier { self.finishCancelledScan(priorReport: priorReport) }
                        return
                    }
                    let names = saved.pluginProductNames
                    let (finalReport, indexes) = await Task.detached(priority: .utility) {
                        let fresh = Dictionary((enrichedResult.assets + (priorReport?.assets.filter { !scannedKinds.contains($0.kind) } ?? []))
                            .filter { $0.kind == .plugin }
                            .map { ($0.kind.rawValue + ":" + $0.selectionKey, $0) }, uniquingKeysWith: { first, _ in first })
                        var assets = saved.report.assets
                        // Only current scan evidence can authorize removal.
                        for index in assets.indices where assets[index].catalogStale != true && assets[index].kind == .plugin {
                            let key = assets[index].kind.rawValue + ":" + assets[index].path
                            assets[index].fileIdentity = fresh[key]?.fileIdentity
                        }
                        let finalReport = saved.report.replacingAssets(assets)
                        return (finalReport, Self.makeIndexes(report: finalReport, names: names))
                    }.value
                    guard self.scanIdentifier == identifier, !Task.isCancelled else {
                        if self.scanIdentifier == identifier { self.finishCancelledScan(priorReport: priorReport) }
                        return
                    }
                    if scannedKinds.contains(.plugin) {
                        let observedPaths = Set(enrichedResult.assets.filter { $0.kind == .plugin }.map { Data($0.path.utf8) })
                        self.collectReceipts(finalReport.assets.filter { $0.kind == .plugin && $0.catalogStale != true && observedPaths.contains(Data($0.path.utf8)) })
                    }
                    self.pluginProductNames = saved.pluginProductNames
                    preparedLibrary = self.prepareNameSortedLibraryOutline(finalReport)
                    let (suggestions, durableKeys) = await prewarmLibraryMetadata(finalReport)
                    guard self.scanIdentifier == identifier, !Task.isCancelled else {
                        if self.scanIdentifier == identifier { self.finishCancelledScan(priorReport: priorReport) }
                        return
                    }
                    self.preparedIndexes = indexes
                    self.report = finalReport
                    publishedRevision = self.reportRevision
                    self.suggestedMetadataBySubject = suggestions
                    self.durableMetadataSubjectsByCacheKey = durableKeys
                    self.usingSavedCatalog = false
                    self.savedCatalogDate = saved.savedAt; self.catalogObservations = saved.observations; self.metadataOverrides = saved.metadata; self.pluginProductDates = saved.pluginProductDates
                    if let selectedAsset, selectedAsset.kind == .plugin,
                       let id = selectedAsset.pluginProductID,
                       let current = finalReport.assets.first(where: { $0.pluginProductID == id }) {
                        self.selectedProductID = id; self.selectedPath = current.selectionKey
                    } else if let selectedAsset, let current = finalReport.assets.first(where: { $0.kind == selectedAsset.kind && $0.path == selectedAsset.path && $0.libraryMetadata?.identity?.productID == selectedAsset.libraryMetadata?.identity?.productID }) { self.selectedPath = current.selectionKey }
                } catch is CancellationError {
                    self.finishCancelledScan(priorReport: priorReport); return
                } catch CatalogStoreError.sourceChanged {
                    self.finishScanWithoutCommit(priorReport: priorReport,
                                                 notice: CatalogStoreError.sourceChanged.localizedDescription)
                    return
                } catch {
                    self.catalogNotice = error.localizedDescription
                }
            }
            self.isScanning = false; self.scanTask = nil; self.dirtyCategories.subtract(scannedKinds); self.scanningKinds = []; self.isBackgroundScanning = false; self.basicInventoryComplete = true; self.foregroundTask?.cancel()
            if let selected = self.selectedPath, !(self.report?.assets ?? []).contains(where: { $0.selectionKey == selected && $0.kind == self.category }) {
                self.selectedPath = nil
            }
            await self.loadTagCaches()
            self.onChange?()
            await self.reloadInstallerRecords(); await self.reloadUsage()
            guard self.scanIdentifier == identifier, CatalogScope(snapshot).roots == CatalogScope(self.scanRequest).roots, !self.isScanning else { return }
            if let publishedRevision {
                await self.installNameSortedLibraryOutline(preparedLibrary, identifier: identifier,
                    scope: CatalogScope(snapshot), reportRevision: publishedRevision)
            }
            guard self.scanIdentifier == identifier, CatalogScope(snapshot).roots == CatalogScope(self.scanRequest).roots, !self.isScanning else { return }
            self.startUsageCollection()
        }
    }

    /// Stop discovery after its current filesystem operation; committed directory
    /// checkpoints remain available for the next scan of this exact collection.
    public func cancelScan() {
        scanTask?.cancel()
        for preparation in outlinePreparations.values { preparation.task.cancel() }
        outlinePreparations.removeAll()
        onChange?()
    }

    private func finishCancelledScan(priorReport: ScanReport?) {
        finishScanWithoutCommit(priorReport: priorReport, notice: "Refresh stopped. Choose Check For Updates to check your collection again.")
    }

    private func finishScanWithoutCommit(priorReport: ScanReport?, notice: String) {
        report = priorReport
        isScanning = false; scanTask = nil; acceptingInventory = false; scanningKinds = []
        isBackgroundScanning = false; basicInventoryComplete = false; foregroundTask?.cancel()
        catalogNotice = notice
        onChange?()
    }

    public var visibleAssets: [Asset] {
        if !recentOnly, let cachedVisible { return cachedVisible }
        let source = category == .plugin ? pluginProducts.map(\.representative) : (report?.assets ?? [])
        let dates = sortDates; let reportedDays = usageDays; let tags = sortTags
        let result = source.filter { $0.kind == category && matchesRow($0) }.sorted { left, right in
            CatalogOrdering.precedes(title: product(for: left)?.name ?? left.name, id: left.selectionKey,
                size: category == .plugin ? pluginSize(left).completeBytes : left.logicalBytes,
                date: dates[left.path], format: product(for: left)?.formats ?? left.libraryMetadata?.player ?? left.format.uppercased(),
                otherTitle: product(for: right)?.name ?? right.name, otherID: right.selectionKey,
                otherSize: category == .plugin ? pluginSize(right).completeBytes : right.logicalBytes,
                otherDate: dates[right.path], otherFormat: product(for: right)?.formats ?? right.libraryMetadata?.player ?? right.format.uppercased(),
                sort: sort, reversed: sortReversed, addition: sort == .installed ? additionEvidence(left) : nil, otherAddition: sort == .installed ? additionEvidence(right) : nil, usageDay: reportedDays[left.path], otherUsageDay: reportedDays[right.path], tags: tags[left.path], otherTags: tags[right.path])
        }
        cachedVisible = result
        return result
    }

    private var sortAdditions: [String: AdditionDateEvidence] {
        guard sort == .installed else { return [:] }
        var values = Dictionary((report?.assets ?? []).filter { $0.kind == category }.compactMap { asset in
            additionEvidence(asset).map { (asset.path, $0) }
        }, uniquingKeysWith: { first, _ in first })
        if category == .library {
            for asset in report?.assets.filter({ $0.kind == .library }) ?? [] {
                for instrument in asset.libraryMetadata?.instruments ?? [] {
                    if let date = instrument.finderDateAdded,
                       let evidence = try? AdditionDateEvidence(basis: .exact, lower: date, upper: date) { values[instrument.path] = evidence }
                }
            }
        }
        return values
    }
    private var sortDates: [String: Date] {
        if sort == .installed {
            var values = Dictionary((report?.assets ?? []).filter { $0.kind == category }.compactMap { asset in
                additionEvidence(asset).map { (asset.path, $0.upper) }
            }, uniquingKeysWith: { first, _ in first })
            if category == .library {
                for asset in report?.assets.filter({ $0.kind == .library }) ?? [] {
                    for instrument in asset.libraryMetadata?.instruments ?? [] {
                        if let date = instrument.finderDateAdded { values[instrument.path] = date }
                    }
                }
            }
            return values
        }
        if sort != .firstFound { return category == .sample ? inclusionsByPath.compactMapValues(\.latestReferencingProjectModifiedAt) : [:] }
        return Dictionary((report?.assets ?? []).compactMap { asset in firstFound(asset).map { (asset.path, $0) } }, uniquingKeysWith: { first, _ in first })
    }
    public var nextRecentExpiration: Date? {
        let now = Date()
        return catalogObservations.values.filter { $0.isRecent(at: now) }
            .map { $0.firstSeen.addingTimeInterval(30 * 86400 + 0.1) }.min()
    }
    public func firstFound(_ asset: Asset) -> Date? {
        let items = product(for: asset)?.installations ?? [asset]
        let dates = items.compactMap { $0.catalogID.flatMap { catalogObservations[$0]?.firstSeen } }
        return dates.count == items.count ? dates.min() : nil
    }
    public func isRecent(_ asset: Asset, at now: Date = Date()) -> Bool {
        let items = product(for: asset)?.installations ?? [asset]
        return !items.isEmpty && items.allSatisfy { item in
            item.catalogID.flatMap { catalogObservations[$0]?.isRecent(at: now) } == true
        }
    }
    public func subject(asset: Asset, instrument: LibraryInstrument? = nil) -> MetadataSubject? {
        (asset.kind == .plugin ? asset.pluginProductID : asset.catalogID).map { MetadataSubject(nodeID: $0, instrument: instrument) }
    }
    public func suggestedMetadata(asset: Asset, instrument: LibraryInstrument? = nil) -> MusicalMetadata {
        let nodeID = asset.kind == .plugin ? asset.pluginProductID : asset.catalogID
        let cacheKey = nodeID.map { catalogMetadataCacheKey(nodeID: $0, instrument: instrument) }
        if let cacheKey, let cached = suggestedMetadataBySubject[cacheKey] { return cached }
        let items = asset.kind == .plugin && instrument == nil ? product(for: asset)?.installations ?? [asset] : [asset]
        var fallback = MusicalMetadata()
        var vendor = MusicalMetadata()
        var reviewed = MusicalMetadata()
        for item in items {
            let source = instrument == nil ? productTagSource(item) : nil
            let sourceTags = instrument?.tags
                ?? (item.kind == .library ? item.libraryMetadata?.productTags(productName: item.name) : item.libraryMetadata?.tags)
            let local = MusicalMetadata.suggested(name: instrument?.name ?? item.name,
                tags: sourceTags ?? [], kind: item.kind,
                suppressInstrumentFamilyGuess: source?.metadata[.instrument]?.contains("synth") == true
                    || item.vst3Categories?.metadata[.instrument]?.contains("synth") == true)
            Self.mergeMetadata(local, into: &fallback)
            if let exact = item.vst3Categories?.metadata { Self.mergeMetadata(exact, into: &vendor) }
            if let source { Self.mergeMetadata(source.metadata, into: &reviewed) }
        }
        var combined = fallback
        for facet in MusicalFacet.allCases {
            if let exact = vendor[facet], !exact.isEmpty { combined[facet] = exact }
            if let current = reviewed[facet] { combined[facet] = current }
        }
        if let cacheKey { suggestedMetadataBySubject[cacheKey] = combined }
        return combined
    }
    private static func mergeMetadata(_ source: MusicalMetadata, into destination: inout MusicalMetadata) {
        for (key, values) in source.fields {
            destination.fields[key] = Array(Set((destination.fields[key] ?? []) + values)).sorted()
        }
    }
    public func effectiveMetadata(asset: Asset, instrument: LibraryInstrument? = nil) -> MusicalMetadata {
        let nodeID = asset.kind == .plugin ? asset.pluginProductID : asset.catalogID
        let override: MusicalMetadata?
        if let nodeID {
            let cacheKey = catalogMetadataCacheKey(nodeID: nodeID, instrument: instrument)
            let stableKey = durableMetadataSubjectsByCacheKey[cacheKey]
                ?? MetadataSubject(nodeID: nodeID, instrument: instrument).key
            durableMetadataSubjectsByCacheKey[cacheKey] = stableKey
            override = metadataOverrides[stableKey]
        } else { override = nil }
        return suggestedMetadata(asset: asset, instrument: instrument).applying(override)
    }
    public func tagSortKey(asset: Asset, instrument: LibraryInstrument? = nil) -> String? {
        let values = effectiveMetadata(asset: asset, instrument: instrument).fields.values.flatMap { $0 }
            .map(MusicalSearch.normalized).filter { !$0.isEmpty }.sorted()
        return values.isEmpty ? nil : values.joined(separator: " ")
    }
    private var sortTags: [String: String] {
        guard sort == .tags else { return [:] }
        if let cachedSortTags { return cachedSortTags }
        var values = Dictionary((report?.assets ?? []).compactMap { asset in
            tagSortKey(asset: asset).map { (asset.path, $0) }
        }, uniquingKeysWith: { first, _ in first })
        if category == .library {
            for asset in report?.assets.filter({ $0.kind == .library }) ?? [] {
                for instrument in asset.libraryMetadata?.instruments ?? [] {
                    values[instrument.path] = tagSortKey(asset: asset, instrument: instrument)
                }
            }
        }
        cachedSortTags = values
        return values
    }
    private var normalizedQueryTerms: [String] {
        if cachedQuerySource != query {
            cachedQuerySource = query
            cachedQueryTerms = MusicalSearch.normalized(query).split(separator: " ").map(String.init)
        }
        return cachedQueryTerms
    }
    private func queryTerm(_ term: String, matches normalizedText: String) -> Bool {
        queryTerm(term, matches: normalizedText.split(separator: " "), in: normalizedText)
    }
    private func queryTerm(_ term: String, matches words: [Substring], in normalizedText: String) -> Bool {
        if term.allSatisfy(\.isNumber) || term.count == 1 { return words.contains(Substring(term)) }
        return normalizedText.contains(term)
    }
    private func matchesFacets(_ metadata: MusicalMetadata) -> Bool {
        musicalFilter.allSatisfy { field, value in
            (metadata.fields[field] ?? []).contains { MusicalSearch.normalized($0) == MusicalSearch.normalized(value) }
        }
    }
    private func matchesNode(_ node: CatalogOutlineNode) -> Bool {
        guard let asset = node.asset else { return false }
        if node.kind == .plugin { return matchesRow(asset) }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && musicalFilter.isEmpty {
            return !recentOnly || isRecent(asset)
        }
        if node.kind == .sample && musicalFilter.isEmpty {
            // Sample suggestions are derived solely from its filename. Searching
            // that name plus explicit edits has the same matches without rebuilding
            // the full suggested facet vocabulary for every keystroke.
            let edited = subject(asset: asset).flatMap { metadataOverrides[$0.key]?.searchText } ?? ""
            return matchesCatalogQuery(name: node.title, other: edited) && (!recentOnly || isRecent(asset))
        }
        let metadata = effectiveMetadata(asset: asset, instrument: node.instrument)
        if node.kind == .library {
            return matchesLibraryMetadata(asset, metadata: metadata)
                && matchesFacets(metadata) && (!recentOnly || isRecent(asset))
        }
        if let instrument = node.instrument, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let singleton = instrument.articulationCoverage.status == .indexed && instrument.articulations.count == 1
                ? instrument.articulations.first?.name : nil
            let localName = node.articulation.map { instrument.name + " " + $0.name }
                ?? ([node.title, singleton].compactMap { $0 }.joined(separator: " "))
            // One patch and at most one of its articulations participate. A
            // sibling's title or a library's aggregate tags cannot fill a term.
            let localText = MusicalSearch.normalized(localName + " " + metadata.searchText)
            let nameWords = MusicalSearch.normalized(localName).split(separator: " ")
            let localWords = localText.split(separator: " ")
            guard normalizedQueryTerms.contains(where: { term in
                (term.count == 1 && !term.allSatisfy(\.isNumber) && nameWords.contains { $0.hasPrefix(term) })
                    || queryTerm(term, matches: localWords, in: localText)
            }) else { return false }
        }
        // Only literal identity context inherits. Aggregate sibling tags do not.
        let singleton = node.instrument.flatMap {
            $0.articulationCoverage.status == .indexed && $0.articulations.count == 1
                ? $0.articulations.first?.name : nil
        }
        let displayName = node.articulation.map { (node.instrument?.name ?? "") + " " + $0.name }
            ?? ([node.title, singleton].compactMap { $0 }.joined(separator: " "))
        let identityText = [displayName, asset.name, asset.libraryMetadata?.maker ?? ""]
        return matchesCatalogQuery(name: displayName, other: (identityText + [metadata.searchText]).joined(separator: " "))
            && matchesFacets(metadata) && (!recentOnly || isRecent(asset))
    }
    public func facetValues(_ facet: MusicalFacet) -> [String] {
        var values = Set<String>()
        for asset in report?.assets ?? [] where asset.kind == category {
            values.formUnion(effectiveMetadata(asset: asset)[facet] ?? [])
            for instrument in asset.libraryMetadata?.instruments ?? [] {
                values.formUnion(effectiveMetadata(asset: asset, instrument: instrument)[facet] ?? [])
            }
        }
        return values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    public func canEditMetadata(_ node: CatalogOutlineNode?) -> Bool {
        catalogStore != nil && !isBusy && node?.isGroup == false && node?.asset?.catalogID != nil
    }
    public func saveMetadata(_ value: MusicalMetadata?, subject: MetadataSubject) async throws {
        guard let catalogStore, !isBusy else { throw CatalogStoreError.busy }
        isSavingMetadata = true; onChange?()
        defer { isSavingMetadata = false; onChange?() }
        let prior = metadataOverrides[subject.key]
        let clean = try value?.validated()
        try await catalogStore.saveMetadata(clean, for: subject)
        metadataUndo.append([(subject, prior)]); metadataOverrides[subject.key] = clean
        invalidateOutline(); cachedVisible = nil
    }
    public func undoMetadata() async throws {
        guard let catalogStore, !isBusy, let edits = metadataUndo.last else { return }
        isSavingMetadata = true; onChange?()
        defer { isSavingMetadata = false; onChange?() }
        try await catalogStore.saveMetadataBatch(edits)
        metadataUndo.removeLast()
        for (subject, prior) in edits { metadataOverrides[subject.key] = prior }
        invalidateOutline(); cachedVisible = nil
    }
    /// Edit one visible tag across the current product installations as one durable, undoable action.
    public func changeTag(_ value: String, facet: MusicalFacet, removing: Bool, node: CatalogOutlineNode) async throws {
        guard let catalogStore, canEditMetadata(node), let asset = node.asset,
              MusicalFacet.fields(for: asset.kind).contains(facet) else { throw CatalogStoreError.busy }
        guard let current = report?.assets.first(where: { $0.catalogID == asset.catalogID && $0.path == asset.path }) else { throw CatalogStoreError.invalid }
        if let instrument = node.instrument {
            guard current.libraryMetadata?.instruments.contains(where: { $0.path == instrument.path && $0.vendorID == instrument.vendorID }) == true else { throw CatalogStoreError.invalid }
        }
        let clean = try MusicalMetadata(fields: [facet.rawValue: [value]]).validated()[facet]?.first ?? ""
        guard !clean.isEmpty else { throw CatalogStoreError.invalid }
        let targets = [asset]
        var edits: [(MetadataSubject, MusicalMetadata?)] = []
        for target in targets {
            guard let subject = subject(asset: target, instrument: node.instrument) else { throw CatalogStoreError.invalid }
            let values = effectiveMetadata(asset: target, instrument: node.instrument)[facet] ?? []
            let contains = values.contains { MusicalSearch.normalized($0) == MusicalSearch.normalized(clean) }
            guard removing ? contains : !contains else { continue }
            var next = metadataOverrides[subject.key] ?? MusicalMetadata()
            next[facet] = removing ? values.filter { MusicalSearch.normalized($0) != MusicalSearch.normalized(clean) } : values + [clean]
            edits.append((subject, try next.validated()))
        }
        guard !edits.isEmpty else { return }
        isSavingMetadata = true; onChange?()
        defer { isSavingMetadata = false; onChange?() }
        let prior = edits.map { ($0.0, metadataOverrides[$0.0.key]) }
        try await catalogStore.saveMetadataBatch(edits)
        for (subject, value) in edits { metadataOverrides[subject.key] = value }
        metadataUndo.append(prior); invalidateOutline(); cachedVisible = nil
    }

    public func tags(for node: CatalogOutlineNode) -> [(MusicalFacet, String)] {
        guard let asset = node.asset, !node.isGroup else { return [] }
        let targets = node.kind == .plugin ? (product(for: asset)?.installations ?? [asset]) : [asset]
        var seen = Set<String>(); var result: [(MusicalFacet, String)] = []
        for facet in MusicalFacet.fields(for: asset.kind) {
            for target in targets {
                for value in effectiveMetadata(asset: target, instrument: node.instrument)[facet] ?? [] {
                    if seen.insert(facet.rawValue + ":" + MusicalSearch.normalized(value)).inserted { result.append((facet, value)) }
                }
            }
        }
        return result
    }

    public func metadataDetail(_ node: CatalogOutlineNode) -> String {
        guard let asset = node.asset else { return "" }
        let targets = node.kind == .plugin ? (product(for: asset)?.installations ?? [asset]) : [asset]
        var sections: [String] = []
        for target in targets {
            let effective = effectiveMetadata(asset: target, instrument: node.instrument)
            let override = subject(asset: target, instrument: node.instrument).flatMap { metadataOverrides[$0.key] }
            let lines = MusicalFacet.fields(for: target.kind).compactMap { facet -> String? in
                let values = effective[facet] ?? []
                guard !values.isEmpty || override?[facet] != nil else { return nil }
                return facet.title + ": " + (values.isEmpty ? "None" : values.map(MusicalTagDisplay.title).joined(separator: ", ")) + (override?[facet] != nil ? " (edited)" : node.instrument == nil && productTagSource(target)?.metadata[facet] != nil ? " (reviewed product metadata)" : " (suggested from local labels)")
            }
            if !lines.isEmpty { sections.append((targets.count > 1 ? PluginProduct.formatName(target.format) + "\n" : "") + lines.joined(separator: "\n")) }
        }
        if let date = firstFound(asset) {
            let baseline = asset.catalogID.flatMap { catalogObservations[$0]?.baseline } ?? true
            sections.append((baseline ? "First indexed: " : "First found: ") + date.formatted(date: .abbreviated, time: .omitted) + "\nObservation date; not Date added or an installer record.")
        }
        return sections.joined(separator: "\n\n")
    }

    /// A compact discovery summary; edits retain their installation-specific scope.
    public func tagSummary(_ node: CatalogOutlineNode) -> String {
        guard let asset = node.asset, !node.isGroup else { return "" }
        let targets = node.kind == .plugin ? (product(for: asset)?.installations ?? [asset]) : [asset]
        var values: [String] = []
        var seen = Set<String>()
        for target in targets {
            let metadata = effectiveMetadata(asset: target, instrument: node.instrument)
            for facet in MusicalFacet.fields(for: target.kind) {
                for value in metadata[facet] ?? [] where seen.insert(MusicalSearch.normalized(value)).inserted {
                    values.append(value)
                }
            }
        }
        return values.isEmpty ? "No tags yet" : values.prefix(3).map(MusicalTagDisplay.title).joined(separator: " · ") + (values.count > 3 ? " · +\(values.count - 3)" : "")
    }

    public var selectedAsset: Asset? {
        if category == .plugin, let selectedProductID,
           let asset = pluginProducts.first(where: { $0.id == selectedProductID })?.representative,
           matchesRow(asset) { return asset }
        guard let selectedPath, let asset = assetsByKey[category.rawValue + ":" + selectedPath], matchesRow(asset) else { return nil }
        return asset
    }
    private func matchesRow(_ asset: Asset) -> Bool {
        if usageFilter == .unknown && usageRecord(asset) != nil { return false }
        if asset.kind == .plugin, let product = productsByPath[asset.path] { return matchesQuery(product.representative) }
        return matchesQuery(asset)
    }
    public func product(for asset: Asset) -> PluginProduct? { asset.kind == .plugin ? productsByPath[asset.path] : nil }
    public var selectedPlugin: PluginProduct? { selectedAsset.flatMap { product(for: $0) } }
    public func pluginReferenceDetail(_ product: PluginProduct) -> String {
        if isScanning { return "Project references are still being checked." }
        let projects = candidateProjects[product.id] ?? []
        let prefix = projects.isEmpty ? "No saved plugin references identified. Last used is unknown." : "Candidate saved-project matches:\n" + projects.map(\.path).joined(separator: "\n")
        return prefix + "\n\nName matches do not identify a specific installed format. See Scan details for coverage by project. Missing matches do not establish that a plugin is unused."
    }
    public func canReviewRemoval(_ asset: Asset) -> Bool {
        !isBusy && !usingSavedCatalog && asset.catalogStale != true && asset.fileIdentity != nil
    }
    /// Explicitly reviewed installation paths only. Caller must present confirmation first.
    public func trashPlugins(_ reviewed: [Asset]) async -> [PluginRemovalResult] {
        let paths = Set(reviewed.map(\.path))
        guard !isBusy, !usingSavedCatalog, !paths.isEmpty, reviewed.allSatisfy({ $0.catalogStale != true && $0.fileIdentity != nil }) else { return [] }
        let selected = selectedPlugin
        let current = (report?.assets ?? []).filter { $0.kind == .plugin && paths.contains($0.path) }
        guard reviewed.count == paths.count, current.count == paths.count,
              reviewed.allSatisfy({ item in current.contains { $0.path == item.path && $0.fileIdentity == item.fileIdentity && $0.bundleIdentifier == item.bundleIdentifier } }) else { return [] }
        cancelReceiptCollection()
        let targets = reviewed
        isRemoving = true; onChange?()
        if let catalogStore {
            do { try await catalogStore.recordRemovalIntent(paths: paths) }
            catch { catalogNotice = error.localizedDescription; isRemoving = false; onChange?(); return [] }
        }
        let result = await Task.detached(priority: .utility) { PluginRemoval.moveToTrash(targets) }.value
        let removed = Set(result.filter(\.succeeded).map(\.path))
        if let catalogStore {
            do { try await catalogStore.finalizePluginRemoval(attempted: paths, succeeded: removed, scope: CatalogScope(scanRequest)) }
            catch { catalogNotice = error.localizedDescription }
        }
        report = report?.removingPluginPaths(removed)
        if let selected, let replacement = selected.installations.first(where: { !removed.contains($0.path) }) { selectedPath = replacement.path; selectedProductID = selected.id }
        else if let selectedPath, removed.contains(selectedPath) { self.selectedPath = nil; selectedProductID = nil }
        isRemoving = false; onChange?()
        return result
    }
    public var locationSummary: String {
        let kind: RootKind = category == .sample ? .samples : category == .library ? .libraries : .plugins
        let count = roots[kind]?.count ?? 0
        if report == nil { return count > 0 ? "\(count) saved location(s). Choose Check For Updates to load this collection in the current session." : "Add one or more folders to get started." }
        let configured = roots[kind] ?? []
        if report!.issues.contains(where: { $0.reason.contains("Entry limit") }) { return "The scan reached its entry limit. Some locations may not have been inspected. Open Scan details; try a smaller set of folders." }
        let issues = report!.issues.filter { issue in configured.contains { issue.path == $0.path || issue.path.hasPrefix($0.path + "/") } }
        if !issues.isEmpty { return "\(count) configured location(s), with \(issues.count) scan issue(s). Open Scan details to see what couldn't be read." }
        return count == 0 ? "No custom folders selected for this collection. Add folders in Settings." : "No matching items were found in \(count) configured location(s). Add sample folders or parent folders containing your libraries, then scan again."
    }
    public var totalCount: Int { categoryCounts[category, default: 0] }

    public func referenceText(_ asset: Asset) -> String {
        if asset.kind == .plugin, let product = productsByPath[asset.path] {
            if isScanning { return "Checking…" }
            _ = product
            return "Unknown"
        }
        if asset.kind == .library {
            return isScanning ? "Checking…" : "Unknown"
        }
        guard asset.kind == .sample else { return "Not available" }
        if isScanning { return "Checking…" }
        guard let inclusion = inclusionsByPath[asset.path],
              let date = inclusion.latestReferencingProjectModifiedAt else { return "Not established" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    public var status: String {
        if let catalogNotice { return catalogNotice }
        if usingSavedCatalog, !isScanning, let date = savedCatalogDate { return "Saved collection · \(date.formatted(date: .abbreviated, time: .shortened)) · Choose Check For Updates to verify availability and references." }
        if isRemoving { return "Moving selected plugin installations to Trash…" }
        if isScanning { return basicInventoryComplete ? "Collection ready. Project references are being checked in the background." : "Discovering your collection in the background. More items may appear." }
        if configurationChanged { return "Folder selection changed. Choose Check For Updates to update results." }
        guard let report else {
            let count = roots.values.reduce(0) { $0 + $1.count }
            return count == 0 ? "Choose folders, then scan your collection. Standard plugin folders are included by default." : "\(count) folders selected. Scan to build your collection."
        }
        let failed = report.projects.filter { $0.coverage != "partial" }.count
        let stale = report.assets.filter { $0.catalogStale == true }.count
        return "\(report.assets.count) entries · \(stale) not observed in latest scan · \(report.projects.count) projects · \(report.issues.count) scan issues · \(failed) unsupported or failed projects. Reference coverage is partial."
    }

    public var detail: String {
        guard let asset = selectedAsset else { return "Select an item to see its tags and usage." }
        var lines = [asset.name, "", asset.path, "", "Format: \(asset.format.isEmpty ? "Folder" : asset.format.uppercased())",
                     "Type: \(asset.kind == .plugin ? "Plugin installation" : asset.kind == .sample ? "Audio file" : "Library candidate")",
                     "Size: \(asset.kind == .plugin ? pluginSize(asset).value : asset.logicalBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "Size unavailable")"]
        if asset.kind == .sample {
            let inclusion = inclusionsByPath[asset.path]
            if isScanning {
                lines += ["", "Project references are still being checked. This item's reference history is not established yet."]
            } else if asset.catalogStale == true || inclusion == nil {
                lines += ["", "Reference coverage unavailable for this not-observed or unverified sample. Choose Check For Updates when its location is available."]
            } else if let inclusion, !inclusion.projectPaths.isEmpty {
                lines += ["", "Referencing projects:"] + inclusion.projectPaths
                lines += ["", "Project recency: \(referenceText(asset)). This uses the latest referencing project's modification date, not when the sample was added or played."]
            } else {
                if (roots[.projects] ?? []).isEmpty {
                    lines += ["", "Add project folders to check references."]
                } else if report?.projects.isEmpty ?? true {
                    lines += ["", "Project reference coverage unavailable; no supported saved projects were read. See Scan details."]
                } else {
                    lines += ["", "No references found in scanned projects. Unsupported formats and unresolved paths may hide references."]
                }
            }
        } else { lines += ["", "Reference matching is not available for plugins or libraries in this preview."] }
        lines += ["", "This is a discovered candidate, not a recommendation to remove it."]
        return lines.joined(separator: "\n")
    }

    public var coverageDetail: String {
        guard let report else { return "No scan yet." }
        var lines = [isScanning ? "Scan is still running; project coverage is pending." : "Scan issues", ""]
        let pluginsWithDate = pluginProducts.filter { additionEvidence($0.representative) != nil }.count
        let pluginsWithUse = pluginProducts.filter { usageRecord($0.representative) != nil }.count
        let samples = report.assets.filter { $0.kind == .sample }
        let libraries = report.assets.filter { $0.kind == .library }
        let instruments = libraries.flatMap { $0.libraryMetadata?.instruments ?? [] }
        lines += ["Collection facts",
                  "Plugins: \(pluginProducts.count) products, \(pluginsWithDate) with Date added, \(pluginsWithUse) with qualified Last used.",
                  "Samples: \(samples.count), \(samples.filter { additionEvidence($0) != nil }.count) with Date added, \(samples.filter { usageRecord($0) != nil }.count) with qualified saved-project Last used.",
                  "Libraries: \(libraries.count), \(libraries.filter { additionEvidence($0) != nil }.count) with Date added, \(libraries.filter { usageRecord($0) != nil }.count) with qualified Last used; \(instruments.count) instruments, \(instruments.filter { $0.finderDateAdded != nil }.count) with Date added. Kontakt saved-state use is library-level only.",
                  "Missing dates or use can mean the source has no qualified history; scan issues are listed below.", ""]
        lines += report.issues.map { "\($0.path)\n\($0.reason)\n" }
        lines += ["", "Project coverage", ""]
        lines += report.projects.map { project in
            let states = (project.kontaktStates ?? []).map { state in
                let outcomes = (project.kontaktOutcomes ?? []).filter { $0.instanceOrdinal == state.instanceOrdinal }
                    .map { "\($0.libraryID): \($0.status)" }.joined(separator: ", ")
                return "Kontakt instance \(state.instanceOrdinal + 1): \(state.classification)"
                    + (outcomes.isEmpty ? "" : " (\(outcomes))")
            }.joined(separator: "\n")
            return "\(project.path)\n\(project.adapter): \(project.coverage), \(project.references.count) reference candidates"
                + (states.isEmpty ? "" : "\n" + states)
                + "\n\(project.limitations.joined(separator: " "))\n"
        }
        return lines.joined(separator: "\n")
    }

    public var stateSnapshot: [String: Any] {
        ["category": category.rawValue, "query": query, "sort": sort.rawValue, "sort_reversed": sortReversed,
         "standard_plugins": standardPlugins, "appearance": appearance.rawValue, "roots": Dictionary(uniqueKeysWithValues: roots.map { ($0.key.rawValue, $0.value.map(\.path)) }),
         "selection": selectedPath as Any? ?? NSNull(), "onboarding_completed": onboardingCompleted,
         "outline_state": outlineState.snapshot, "recent_only": recentOnly, "musical_filter": musicalFilter, "usage_filter": usageFilter.rawValue]
    }
}

@MainActor public enum CatalogStateRegistry {
    public static var persistedIDs: Set<String> { Set(definitions.filter { $0["persisted"] as? Bool == true }.compactMap { $0["id"] as? String }) }
    public static let definitions: [[String: Any]] = [
        ["id": "category", "value_type": "enumeration", "default": "plugin"],
        ["id": "query", "value_type": "string", "default": ""],
        ["id": "sort", "value_type": "enumeration", "default": "Name"],
        ["id": "sort_reversed", "value_type": "boolean", "default": false],
        ["id": "appearance", "value_type": "enumeration", "default": "light", "persisted": true],
        ["id": "standard_plugins", "value_type": "boolean", "default": true, "persisted": true],
        ["id": "roots", "value_type": "object", "default": [String: [String]](), "persisted": true],
        ["id": "onboarding_completed", "value_type": "boolean", "default": false, "persisted": true],
        ["id": "selection", "value_type": "string", "default": NSNull()],
        ["id": "usage_filter", "value_type": "enumeration", "default": "all"],
        ["id": "recent_only", "value_type": "boolean", "default": false],
        ["id": "musical_filter", "value_type": "object", "default": [String: String]()],
        ["id": "outline_state", "value_type": "object", "default": [String: Any]()],
    ]
}
