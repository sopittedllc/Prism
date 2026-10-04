import Foundation
import SimplifyCore

public enum RootKind: String, CaseIterable, Sendable {
    case plugins = "Plugins", samples = "Samples", libraries = "Libraries", projects = "Projects"
}
public enum CatalogAppearance: String, CaseIterable, Sendable {
    case light, dark, system
    public var title: String {
        switch self { case .light: "Light"; case .dark: "Dark"; case .system: "Match system preference" }
    }
}
public enum CatalogSort: String, CaseIterable, Sendable { case name = "Name", size = "Size", recency = "Last used", firstFound = "First found", format = "Format", installed = "Installed" }

/// Positive host evidence is distinct from missing coverage. Unknown is never inactivity.
public enum CatalogUsageFilter: String, CaseIterable, Sendable {
    case all, unknown
    public var title: String { self == .all ? "Any usage history" : "Usage unknown" }
}

/// Browsing is session-only; accepted scan setup can be stored locally.
@MainActor public final class CatalogModel {
    public var category: AssetKind = .plugin { didSet { cachedVisible = nil; cachedOutline = nil } }
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
    public private(set) var onlineTags = false
    public private(set) var isFetchingTags = false
    public private(set) var tagFetchStatus = "Online product tags are off."
    private var tagRecords: [String: ProductTagRecord] = [:]
    private var tagCacheLoaded = false
    private var tagTask: Task<Void, Never>?
    private var tagGeneration = UUID()
    private let tagStore: ProductTagStore?
    private let tagSources: [ProductTagSource]
    private let tagFetcher: @Sendable (ProductTagSource) async throws -> ProductTagRecord
    public var appearance: CatalogAppearance = .light
    public var standardPlugins = true
    public private(set) var roots: [RootKind: [URL]] = [:]
    /// Legacy API name: holds Asset.selectionKey, not necessarily a filesystem path.
    public var selectedPath: String?
    public private(set) var report: ScanReport? { didSet { rebuildIndexes() } }
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
    private var foregroundTask: Task<Void, Never>?
    public private(set) var isBackgroundScanning = false
    public private(set) var basicInventoryComplete = false
    private var inventorySequence = 0
    private var acceptingInventory = false
    private var cachedVisible: [Asset]?
    private var cachedOutline: CatalogOutline?
    private var outlineBases: [AssetKind: CatalogOutline] = [:]
    private var previousOutlineBases: [AssetKind: CatalogOutline] = [:]
    public let outlineState = CatalogOutlineState()
    private var assetsByKey: [String: Asset] = [:]
    private var inclusionsByPath: [String: SampleInclusion] = [:]
    public private(set) var pluginProducts: [PluginProduct] = []
    private var productsByPath: [String: PluginProduct] = [:]
    private var candidateProjects: [String: [ProjectReport]] = [:]
    public private(set) var isRemoving = false
    public var isBusy: Bool { isScanning || isRemoving || isSavingMetadata }
    private var categoryCounts: [AssetKind: Int] = [:]

    private func rebuildIndexes() {
        invalidateOutline()
        cachedVisible = nil; assetsByKey = [:]; inclusionsByPath = [:]; categoryCounts = [:]
        for asset in report?.assets ?? [] {
            assetsByKey[asset.kind.rawValue + ":" + asset.selectionKey] = asset
            categoryCounts[asset.kind, default: 0] += 1
        }
        for inclusion in report?.sampleInclusions ?? [] { inclusionsByPath[inclusion.samplePath] = inclusion }
        pluginProducts = PluginProduct.group(report?.assets ?? []); productsByPath = [:]; candidateProjects = [:]
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
    }
    private func invalidateOutline() {
        for (category, outline) in outlineBases { previousOutlineBases[category] = outline }
        outlineBases = [:]; cachedOutline = nil
    }
    public var outline: CatalogOutline {
        if !recentOnly, let cachedOutline { return cachedOutline }
        let base: CatalogOutline
        if let existing = outlineBases[category] { base = existing }
        else {
            base = CatalogOutline.build(
                assets: category == .plugin ? pluginProducts.map(\.representative) : (report?.assets ?? []),
                category: category, sampleRoots: roots[.samples] ?? [], sort: sort, reversed: sortReversed,
                recency: sortDates, additions: sortAdditions, usageDays: usageDays, formats: Dictionary(uniqueKeysWithValues: pluginProducts.map { ($0.representative.path, $0.formats) }),
                pluginProductIDs: Dictionary(uniqueKeysWithValues: pluginProducts.map { ($0.representative.path, $0.id) }))
            outlineState.reconcile(previous: previousOutlineBases[category], current: base, category: category)
            previousOutlineBases[category] = nil; outlineBases[category] = base
        }
        let result = base.filtered(query: query, sort: sort, reversed: sortReversed,
                                  recency: sortDates, additions: sortAdditions, usageDays: usageDays,
                                  pluginMatches: matchesRow, isFiltering: hasFilters,
                                  nodeMatches: matchesNode)
        cachedOutline = result
        return result
    }
    private func matchesQuery(_ asset: Asset) -> Bool {
        MusicalSearch.matches(query, in: [asset.name, asset.libraryMetadata?.maker ?? "", effectiveMetadata(asset: asset).searchText].joined(separator: " "))
            && matchesFacets(effectiveMetadata(asset: asset)) && (!recentOnly || isRecent(asset))
    }

    public private(set) var onboardingCompleted = false
    public private(set) var setupNotice: String?
    public private(set) var savedCatalogDate: Date?
    public private(set) var usingSavedCatalog = false
    public private(set) var isRestoringCatalog = false
    public private(set) var catalogNotice: String?
    public private(set) var catalogObservations: [String: CatalogObservation] = [:] { didSet { cachedVisible = nil; invalidateOutline() } }
    public typealias InstallerRecordLoader = @Sendable (CatalogStore, [String], Date) async throws -> [Data: AssetDateEvidence]
    private let installerRecordLoader: InstallerRecordLoader?
    private var installerRecords: [Data: AssetDateEvidence] = [:]
    private var installerReadGeneration = UUID()
    public private(set) var isLoadingInstallerRecords = false
    public private(set) var installerRecordsUnavailable = false
    public private(set) var isCollectingInstallerRecords = false
    public typealias UsageCollector = @Sendable ([Asset], CatalogStore) async -> LiveUsageCollection
    public typealias UsageLoader = @Sendable (CatalogStore, [String], Date) async throws -> [Data: AssetDateEvidence]
    private let usageLoader: UsageLoader?
    private let usageCollector: UsageCollector?
    private var usageTask: Task<Void, Never>?
    private var usageGeneration = UUID()
    private var usageReadGeneration = UUID()
    private var usageRecords: [Data: AssetDateEvidence] = [:]
    public private(set) var usageUnavailable = false
    public private(set) var isCollectingUsage = false
    public private(set) var usageCollection: LiveUsageCollection?

    public func reloadUsage() async {
        guard let catalogStore else { return }
        let generation = usageGeneration; let readGeneration = UUID(); usageReadGeneration = readGeneration
        do {
            let ids = (report?.assets ?? []).filter { $0.kind == .plugin }.compactMap(\.catalogID)
            let records: [Data: AssetDateEvidence]
            if let usageLoader { records = try await usageLoader(catalogStore, ids, Date()) }
            else { records = try await catalogStore.latestHostUsage(for: ids, asOf: Date()) }
            guard generation == usageGeneration, readGeneration == usageReadGeneration, !Task.isCancelled else { return }
            usageRecords = records; usageUnavailable = false
        } catch {
            guard generation == usageGeneration, readGeneration == usageReadGeneration, !Task.isCancelled else { return }
            usageRecords = [:]; usageUnavailable = true
        }
        cachedVisible = nil; invalidateOutline(); onChange?()
    }
    public func usageRecord(_ asset: Asset, grouped: Bool = true) -> AssetDateEvidence? {
        guard asset.kind == .plugin, !(isScanning && scanningKinds.contains(.plugin)) else { return nil }
        let items = grouped ? product(for: asset)?.installations ?? [asset] : [asset]
        return items.compactMap { item -> AssetDateEvidence? in
            guard let id = item.catalogID, assetsByKey["plugin:" + item.selectionKey]?.catalogID == id else { return nil }
            return usageRecords[Data(id.utf8)]
        }.sorted { a, b in
            if usageDay(a) != usageDay(b) { return usageDay(a) > usageDay(b) }
            if let ap = a.proToolsUsage, let bp = b.proToolsUsage {
                if ap.localTime != bp.localTime {
                    return (ap.localTime?.canonical ?? "") > (bp.localTime?.canonical ?? "")
                }
                if ap.runHash != bp.runHash { return (ap.runHash ?? "") < (bp.runHash ?? "") }
                if ap.sourceSeconds != bp.sourceSeconds { return ap.sourceSeconds > bp.sourceSeconds }
            }
            return a.evidenceID.utf8.lexicographicallyPrecedes(b.evidenceID.utf8)
        }.first
    }
    private func usageDay(_ record: AssetDateEvidence) -> String {
        record.hostUsage?.localTime.dayKey ?? record.cubaseUsage?.reportedDate.formatted(.iso8601.year().month().day()) ?? record.proToolsUsage?.localTime?.dayKey ?? record.logicUsage?.reportedDate.formatted(.iso8601.year().month().day()) ?? ""
    }
    public func lastUsed(_ asset: Asset) -> UsageDatePresentation {
        guard asset.kind == .plugin else { return UsageDatePresentation(record: nil) }
        let items = product(for: asset)?.installations ?? [asset]
        let total = Set(items.map(\.format)).count
        let covered = Set(items.filter { usageRecord($0, grouped: false) != nil }.map(\.format)).count
        return UsageDatePresentation(record: usageRecord(asset), unavailable: usageUnavailable,
            checking: isCollectingUsage || (isScanning && scanningKinds.contains(.plugin)), saved: usingSavedCatalog || asset.catalogStale == true,
            incomplete: usageCollection.map { $0.failures > 0 } ?? false, formatCoverage: "History associated with \(covered) of \(total) formats.")
    }
    private var usageDays: [String: String] {
        guard sort == .recency else { return [:] }
        return Dictionary((report?.assets ?? []).compactMap { asset in
            usageRecord(asset).map { (asset.path, usageDay($0)) }
        }, uniquingKeysWith: { first, _ in first })
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

    public func additionEvidence(_ asset: Asset, grouped: Bool = true) -> AdditionDateEvidence? {
        guard !(isScanning && scanningKinds.contains(asset.kind)) else { return nil }
        let items = grouped && asset.kind == .plugin ? product(for: asset)?.installations ?? [asset] : [asset]
        return try? AdditionDateEvidence.group(items.map { item in
            guard let id = item.catalogID,
                  let current = assetsByKey[item.kind.rawValue + ":" + item.selectionKey]?.catalogID,
                  id.utf8.elementsEqual(current.utf8) else { return nil }
            return catalogObservations[id]?.addition
        })
    }

    public func additionDate(_ asset: Asset, grouped: Bool = true) -> AdditionDatePresentation {
        let items = grouped && asset.kind == .plugin ? product(for: asset)?.installations ?? [asset] : [asset]
        let known = items.filter { additionEvidence($0, grouped: false) != nil }.count
        let coverage = items.count > 1 ? "Dates available for \(known) of \(items.count) installations." : ""
        let saved = usingSavedCatalog || items.contains { assetsByKey[$0.kind.rawValue + ":" + $0.selectionKey]?.catalogStale == true }
        return AdditionDatePresentation(evidence: additionEvidence(asset, grouped: grouped), coverage: coverage, saved: saved,
                                        checking: isScanning && scanningKinds.contains(asset.kind))
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
            guard installerReadGeneration == generation, receiptGeneration == scopeGeneration, !Task.isCancelled else { return }
            installerRecords = values; installerRecordsUnavailable = false
        } catch {
            guard installerReadGeneration == generation, receiptGeneration == scopeGeneration, !Task.isCancelled else { return }
            installerRecords = [:]; installerRecordsUnavailable = true
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
        if installerRecordsUnavailable { detail.append("Saved installer records could not be read. Scan to retry.") }
        else if checking { detail.append(known.isEmpty ? "Checking installer records…" : "Checking for newer records…") }
        else if receiptCollection?.status == .incomplete || receiptCollection?.status == .cancelled {
            detail.append("Installer records could not be fully checked. Scan to retry.")
        } else if known.isEmpty { detail.append("No matching installer record available.") }
        if !known.isEmpty {
            detail.append("May record an install or update; not original Date added.")
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

    deinit { receiptTask?.cancel(); usageTask?.cancel() }

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
    private let sineDatabase: URL

    public init(store: SetupStore? = nil, sineDatabase: URL = LibraryMetadataReader.sineDatabase, catalogStore: CatalogStore? = nil,
                receiptCollector: ReceiptCollector? = nil, usageCollector: UsageCollector? = nil, usageLoader: UsageLoader? = nil,
                installerRecordLoader: InstallerRecordLoader? = nil,
                tagStore: ProductTagStore? = nil, tagSources: [ProductTagSource] = ProductTagSources.all,
                tagFetcher: @escaping @Sendable (ProductTagSource) async throws -> ProductTagRecord = ProductTagClient.fetch) {
        self.tagStore = tagStore; self.tagSources = Array(tagSources.prefix(64)); self.tagFetcher = tagFetcher
        self.usageLoader = usageLoader; self.usageCollector = usageCollector
        self.catalogStore = catalogStore; self.receiptCollector = receiptCollector; self.installerRecordLoader = installerRecordLoader
        self.store = store; self.sineDatabase = sineDatabase
        do {
            if let values = try store?.load() {
                standardPlugins = values["standard_plugins"] as? Bool ?? true
                onlineTags = values["online_tags"] as? Bool ?? false
                appearance = CatalogAppearance(rawValue: values["appearance"] as? String ?? "light") ?? .light
                onboardingCompleted = values["onboarding_completed"] as? Bool ?? false
                for (key, paths) in values["roots"] as? [String: [String]] ?? [:] {
                    if let kind = RootKind(rawValue: key) { roots[kind] = paths.map { URL(fileURLWithPath: $0) } }
                }
            }
        } catch { setupNotice = error.localizedDescription }
    }

    public func productTagSource(_ asset: Asset) -> ProductTagSource? {
        guard onlineTags else { return nil }
        let matches = tagSources.filter { $0.matches(asset) }
        return matches.count == 1 ? matches[0] : nil
    }
    public func productTagProvenance(_ asset: Asset) -> String {
        guard let source = productTagSource(asset) else { return onlineTags ? "No reviewed online source for this product." : "Online product tags are off." }
        guard let record = tagRecords[source.id] else { return "Official product tags have not been fetched yet." }
        return "Vendor product suggestions (not individual patch claims)\n" + source.page.absoluteString
            + "\nFetched " + record.fetchedAt.formatted(date: .abbreviated, time: .shortened)
            + (record.isFresh() ? "" : " · cached; refresh needed")
    }
    public func setOnlineTags(_ enabled: Bool) {
        let previous = onlineTags; onlineTags = enabled
        do { if let store { try store.save(stateSnapshot) } }
        catch { onlineTags = previous; tagFetchStatus = "Couldn’t save online tag preference: " + error.localizedDescription; onChange?(); return }
        applyOnlineTags(enabled)
    }
    private func applyOnlineTags(_ enabled: Bool) {
        onlineTags = enabled
        tagGeneration = UUID(); tagTask?.cancel(); isFetchingTags = false
        cachedOutline = nil; cachedVisible = nil
        if enabled { refreshProductTags() } else { tagFetchStatus = "Online product tags are off." }
        onChange?()
    }
    /// Each finite snapshot attempts every distinct source once, even after earlier failures.
    public func refreshProductTags(force: Bool = false) {
        guard onlineTags, !isFetchingTags else { return }
        guard let report, !isScanning else { tagFetchStatus = "Product tags will fetch when the collection scan finishes."; return }
        let assets = report.assets
        let sources = tagSources.filter { source in assets.contains { productTagSource($0)?.id == source.id } }
        let generation = UUID(); tagGeneration = generation; isFetchingTags = true
        tagFetchStatus = "Checking official product tags…"; onChange?()
        tagTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.tagGeneration == generation { self.isFetchingTags = false; self.onChange?() } }
            do {
                if !self.tagCacheLoaded {
                    let saved = try await self.tagStore?.load() ?? [:]
                    guard self.tagGeneration == generation, self.onlineTags, !Task.isCancelled else { return }
                    self.tagRecords = saved; self.tagCacheLoaded = true
                }
                var completed = 0, failed = 0
                var lastError: String?
                for source in sources {
                    guard self.tagGeneration == generation, self.onlineTags, !Task.isCancelled else { return }
                    if force || self.tagRecords[source.id]?.isFresh() != true {
                        do {
                            let record = try await self.tagFetcher(source)
                            guard self.tagGeneration == generation, self.onlineTags, !Task.isCancelled else { return }
                            guard record.sourceID == source.id, record.descriptionDigest == source.descriptionDigest else { throw ProductTagError.changed }
                            var next = self.tagRecords; next[source.id] = record
                            try await self.tagStore?.save(next)
                            guard self.tagGeneration == generation, self.onlineTags, !Task.isCancelled else { return }
                            self.tagRecords = next
                        } catch is CancellationError { return }
                        catch {
                            guard self.tagGeneration == generation, self.onlineTags, !Task.isCancelled else { return }
                            failed += 1; lastError = error.localizedDescription
                        }
                    }
                    completed += 1; self.cachedOutline = nil; self.cachedVisible = nil
                    self.tagFetchStatus = "Product tags: \(completed) of \(sources.count) checked"; self.onChange?()
                }
                self.cachedOutline = nil; self.cachedVisible = nil
                self.tagFetchStatus = sources.isEmpty ? "No supported product matches. Local tags remain available."
                    : "Product tags: \(completed - failed) of \(sources.count) verified."
                if let lastError { self.tagFetchStatus += " \(failed) failed. " + lastError }
            } catch {
                guard self.tagGeneration == generation, self.onlineTags, !Task.isCancelled else { return }
                self.tagFetchStatus = error.localizedDescription
            }
        }
    }

    public func setupDraft() -> CatalogModel {
        let draft = CatalogModel(sineDatabase: sineDatabase)
        draft.standardPlugins = standardPlugins; draft.roots = roots; draft.onlineTags = onlineTags; draft.appearance = appearance
        return draft
    }

    public func acceptSetup(_ draft: CatalogModel, remember: Bool, onlineTags preference: Bool? = nil) throws {
        guard !isBusy else { return }
        if report != nil {
            for kind in RootKind.allCases where roots[kind] != draft.roots[kind] { draft.dirtyCategories.formUnion(affectedCategories(kind)) }
            if standardPlugins != draft.standardPlugins { draft.dirtyCategories.insert(.plugin) }
        }
        var values = draft.stateSnapshot; values["onboarding_completed"] = true
        values["online_tags"] = preference ?? onlineTags
        if remember { try store?.save(values) }
        if standardPlugins != draft.standardPlugins || roots != draft.roots { cancelReceiptCollection() }
        standardPlugins = draft.standardPlugins; roots = draft.roots; appearance = draft.appearance
        if let preference, preference != onlineTags { applyOnlineTags(preference) }
        invalidateOutline()
        onboardingCompleted = true; dirtyCategories.formUnion(draft.dirtyCategories)
        setupNotice = remember ? nil : "Setup is being used for this session only."
        onChange?()
    }

    public func reset() {
        guard !isBusy else { return }
        cancelReceiptCollection()
        installerRecords = [:]; installerRecordsUnavailable = false
        tagGeneration = UUID(); tagTask?.cancel(); isFetchingTags = false; onlineTags = false; tagFetchStatus = "Online product tags are off."
        usageRecords = [:]; usageUnavailable = false
        recentOnly = false; usageFilter = .all; musicalFilter = [:]; metadataOverrides = [:]; metadataUndo = []
        scanIdentifier = UUID(); usingSavedCatalog = false; savedCatalogDate = nil; catalogObservations = [:]; catalogNotice = nil
        outlineState.reset(); outlineBases = [:]; previousOutlineBases = [:]; cachedOutline = nil
        category = .plugin; query = ""; sort = .name; sortReversed = false; standardPlugins = true; appearance = .light
        roots = [:]; selectedPath = nil; report = nil; dirtyCategories = []; scanningKinds = []; onboardingCompleted = false; setupNotice = nil; scanProgress = nil; scanStartedAt = nil; basicInventoryComplete = false; isBackgroundScanning = false
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
        request.samples = roots[.samples] ?? []; request.libraries = roots[.libraries] ?? []
        request.projects = roots[.projects] ?? []
        return request
    }

    /// Restore without blocking native interaction; late results cannot replace a scan/setup change.
    public func restoreSavedCatalog() async {
        guard let catalogStore, report == nil, !isScanning, !isRestoringCatalog else { return }
        let scope = CatalogScope(scanRequest); let identifier = scanIdentifier
        isRestoringCatalog = true
        defer { isRestoringCatalog = false; refreshProductTags(); onChange?() }
        do {
            let snapshot = try await catalogStore.load(scope: scope)
            guard identifier == scanIdentifier, scope.roots == CatalogScope(scanRequest).roots, report == nil else { return }
            if let snapshot {
                report = snapshot.report; savedCatalogDate = snapshot.savedAt
                catalogObservations = snapshot.observations; metadataOverrides = snapshot.metadata; usingSavedCatalog = true
                await reloadInstallerRecords(); await reloadUsage()
                guard identifier == scanIdentifier, scope.roots == CatalogScope(scanRequest).roots, !isScanning else { return }
                startUsageCollection()
            }
        } catch {
            guard identifier == scanIdentifier, scope.roots == CatalogScope(scanRequest).roots else { return }
            catalogNotice = error.localizedDescription
        }
    }

    public func scan(scannedKinds: Set<AssetKind> = Set(AssetKind.allCases)) {
        guard !scannedKinds.isEmpty else { return }
        guard !isBusy else { return }
        cancelReceiptCollection()
        tagGeneration = UUID(); tagTask?.cancel(); isFetchingTags = false
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
        let snapshot = request; let database = sineDatabase; let preserveExisting = dirtyCategories.isDisjoint(with: scannedKinds)
        scanTask = Task { [weak self] in
            let (result, additionContext) = await Task.detached(priority: .utility) { [weak self] in
                let context = AdditionScanContext(scope: CatalogScope(snapshot))
                let result = Scanner(sineDatabase: database).scan(snapshot, scannedKinds: scannedKinds, inventory: { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let owner = self, owner.isScanning, owner.acceptingInventory, owner.scanIdentifier == identifier,
                              update.sequence > owner.inventorySequence else { return }
                        owner.inventorySequence = update.sequence
                        owner.basicInventoryComplete = update.discoveryComplete
                        owner.isBackgroundScanning = true
                        if let prior = owner.report {
                            func key(_ asset: Asset) -> String { asset.kind.rawValue + ":" + asset.path + ":" + (asset.libraryMetadata?.identity?.productID ?? "") }
                            var merged = Dictionary(prior.assets.filter { preserveExisting || !scannedKinds.contains($0.kind) }.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
                            for var asset in update.assets {
                                asset.catalogID = merged[key(asset)]?.catalogID
                                merged[key(asset)] = asset
                            }
                            owner.report = ScanReport(inventory: update).merging(previous: priorReport, scannedKinds: scannedKinds).replacingAssets(Array(merged.values))
                        } else { owner.report = ScanReport(inventory: update) }
                        owner.onChange?()
                    }
                }) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self, self.isScanning, self.scanIdentifier == identifier,
                              update.sequence > (self.scanProgress?.sequence ?? 0) else { return }
                        self.scanProgress = update; self.onProgressChange?()
                    }
                }
                return (result, context)
            }.value
            guard let self else { return }
            self.acceptingInventory = false
            let selectedAsset = self.selectedAsset
            self.report = result.merging(previous: priorReport, scannedKinds: scannedKinds); self.usingSavedCatalog = false; self.onChange?()
            if let catalogStore = self.catalogStore {
                do {
                    let saved = try await catalogStore.ingest(result, scope: CatalogScope(snapshot), scannedKinds: scannedKinds, additionContext: additionContext)
                    let fresh = Dictionary((result.assets + (priorReport?.assets.filter { !scannedKinds.contains($0.kind) } ?? [])).map { ($0.kind.rawValue + ":" + $0.selectionKey, $0) }, uniquingKeysWith: { first, _ in first })
                    var assets = saved.report.assets
                    // Only current scan evidence can authorize removal. Cached entries never can.
                    for index in assets.indices where assets[index].catalogStale != true {
                        let key = assets[index].kind.rawValue + ":" + assets[index].path
                        if assets[index].kind == .plugin { assets[index].fileIdentity = fresh[key]?.fileIdentity }
                    }
                    if scannedKinds.contains(.plugin) {
                        let observedPaths = Set(result.assets.filter { $0.kind == .plugin }.map { Data($0.path.utf8) })
                        self.collectReceipts(assets.filter { $0.kind == .plugin && $0.catalogStale != true && observedPaths.contains(Data($0.path.utf8)) })
                    }
                    self.report = saved.report.replacingAssets(assets)
                    self.savedCatalogDate = saved.savedAt; self.catalogObservations = saved.observations; self.metadataOverrides = saved.metadata
                    if let selectedAsset, let current = assets.first(where: { $0.kind == selectedAsset.kind && $0.path == selectedAsset.path && $0.libraryMetadata?.identity?.productID == selectedAsset.libraryMetadata?.identity?.productID }) { self.selectedPath = current.selectionKey }
                } catch { self.catalogNotice = error.localizedDescription }
            }
            self.isScanning = false; self.dirtyCategories.subtract(scannedKinds); self.scanningKinds = []; self.isBackgroundScanning = false; self.basicInventoryComplete = true; self.foregroundTask?.cancel()
            if let selected = self.selectedPath, !(self.report?.assets ?? []).contains(where: { $0.selectionKey == selected && $0.kind == self.category }) {
                self.selectedPath = nil
            }
            self.refreshProductTags(); self.onChange?()
            await self.reloadInstallerRecords(); await self.reloadUsage()
            guard self.scanIdentifier == identifier, CatalogScope(snapshot).roots == CatalogScope(self.scanRequest).roots, !self.isScanning else { return }
            self.startUsageCollection()
        }
    }

    public var visibleAssets: [Asset] {
        if !recentOnly, let cachedVisible { return cachedVisible }
        let source = category == .plugin ? pluginProducts.map(\.representative) : (report?.assets ?? [])
        let dates = sortDates; let reportedDays = usageDays
        let result = source.filter { $0.kind == category && matchesRow($0) }.sorted { left, right in
            CatalogOrdering.precedes(title: left.name, id: left.selectionKey,
                size: category == .sample ? left.logicalBytes : nil,
                date: dates[left.path], format: product(for: left)?.formats ?? left.libraryMetadata?.player ?? left.format.uppercased(),
                otherTitle: right.name, otherID: right.selectionKey,
                otherSize: category == .sample ? right.logicalBytes : nil,
                otherDate: dates[right.path], otherFormat: product(for: right)?.formats ?? right.libraryMetadata?.player ?? right.format.uppercased(),
                sort: sort, reversed: sortReversed, addition: sort == .installed ? additionEvidence(left) : nil, otherAddition: sort == .installed ? additionEvidence(right) : nil, usageDay: reportedDays[left.path], otherUsageDay: reportedDays[right.path])
        }
        cachedVisible = result
        return result
    }

    private var sortAdditions: [String: AdditionDateEvidence] {
        guard sort == .installed else { return [:] }
        return Dictionary((report?.assets ?? []).filter { $0.kind == category }.compactMap { asset in
            additionEvidence(asset).map { (asset.path, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }
    private var sortDates: [String: Date] {
        if sort == .installed {
            return Dictionary((report?.assets ?? []).filter { $0.kind == category }.compactMap { asset in
                additionEvidence(asset).map { (asset.path, $0.upper) }
            }, uniquingKeysWith: { first, _ in first })
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
        asset.catalogID.map { MetadataSubject(nodeID: $0, instrument: instrument) }
    }
    public func suggestedMetadata(asset: Asset, instrument: LibraryInstrument? = nil) -> MusicalMetadata {
        let local = MusicalMetadata.suggested(name: instrument?.name ?? asset.name,
            tags: instrument?.tags ?? asset.libraryMetadata?.tags ?? [], kind: asset.kind)
        guard instrument == nil, let source = productTagSource(asset), tagRecords[source.id] != nil else { return local }
        return local.applying(source.metadata)
    }
    public func effectiveMetadata(asset: Asset, instrument: LibraryInstrument? = nil) -> MusicalMetadata {
        let override = subject(asset: asset, instrument: instrument).flatMap { metadataOverrides[$0.key] }
        return suggestedMetadata(asset: asset, instrument: instrument).applying(override)
    }
    private func matchesFacets(_ metadata: MusicalMetadata) -> Bool {
        musicalFilter.allSatisfy { field, value in
            (metadata.fields[field] ?? []).contains { MusicalSearch.normalized($0) == MusicalSearch.normalized(value) }
        }
    }
    private func matchesNode(_ node: CatalogOutlineNode) -> Bool {
        guard let asset = node.asset else { return false }
        if node.kind == .plugin { return matchesRow(asset) }
        let metadata = effectiveMetadata(asset: asset, instrument: node.instrument)
        if node.instrument != nil, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let localText = node.title + " " + metadata.searchText
            guard MusicalSearch.normalized(query).split(separator: " ").contains(where: { MusicalSearch.matches(String($0), in: localText) }) else { return false }
        }
        // Only literal identity context inherits. Aggregate sibling tags do not.
        let identityText = [node.title, asset.name, asset.libraryMetadata?.maker ?? ""]
        return MusicalSearch.matches(query, in: (identityText + [metadata.searchText]).joined(separator: " "))
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
        cachedOutline = nil; cachedVisible = nil
    }
    public func undoMetadata() async throws {
        guard let catalogStore, !isBusy, let edits = metadataUndo.last else { return }
        isSavingMetadata = true; onChange?()
        defer { isSavingMetadata = false; onChange?() }
        try await catalogStore.saveMetadataBatch(edits)
        metadataUndo.removeLast()
        for (subject, prior) in edits { metadataOverrides[subject.key] = prior }
        cachedOutline = nil; cachedVisible = nil
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
        let targets = node.kind == .plugin ? (product(for: asset)?.installations ?? [asset]) : [asset]
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
        metadataUndo.append(prior); cachedOutline = nil; cachedVisible = nil
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
                return facet.title + ": " + (values.isEmpty ? "None" : values.joined(separator: ", ")) + (override?[facet] != nil ? " (edited)" : node.instrument == nil && productTagSource(target).map { tagRecords[$0.id] != nil && $0.metadata[facet] != nil } == true ? " (vendor suggestion)" : " (suggested from local labels)")
            }
            if !lines.isEmpty { sections.append((targets.count > 1 ? PluginProduct.formatName(target.format) + "\n" : "") + lines.joined(separator: "\n")) }
        }
        if let date = firstFound(asset) {
            let baseline = asset.catalogID.flatMap { catalogObservations[$0]?.baseline } ?? true
            sections.append((baseline ? "First indexed: " : "First found: ") + date.formatted(date: .abbreviated, time: .omitted) + "\nObservation date; not original Date added or an installer record.")
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
        return values.isEmpty ? "No tags yet" : values.prefix(3).joined(separator: " · ") + (values.count > 3 ? " · +\(values.count - 3)" : "")
    }

    public var selectedAsset: Asset? {
        guard let selectedPath, let asset = assetsByKey[category.rawValue + ":" + selectedPath], matchesRow(asset) else { return nil }
        return asset
    }
    private func matchesRow(_ asset: Asset) -> Bool {
        if usageFilter == .unknown && usageRecord(asset) != nil { return false }
        if let product = productsByPath[asset.path], asset.kind == .plugin { return product.installations.contains(where: matchesQuery) }
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
        report = report?.removingPluginPaths(removed)
        if let selected, let replacement = selected.installations.first(where: { !removed.contains($0.path) }) { selectedPath = replacement.path }
        else if let selectedPath, removed.contains(selectedPath) { self.selectedPath = nil }
        isRemoving = false; onChange?()
        return result
    }
    public var locationSummary: String {
        let kind: RootKind = category == .sample ? .samples : category == .library ? .libraries : .plugins
        let count = roots[kind]?.count ?? 0
        if report == nil { return count > 0 ? "\(count) saved location(s). Scan to load this collection in the current session." : "Add one or more folders to get started." }
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
        if usingSavedCatalog, !isScanning, let date = savedCatalogDate { return "Saved collection · \(date.formatted(date: .abbreviated, time: .shortened)) · Scan to refresh availability and references." }
        if isRemoving { return "Moving selected plugin installations to Trash…" }
        if isScanning { return basicInventoryComplete ? "Collection ready. Project references are being checked in the background." : "Discovering your collection in the background. More items may appear." }
        if configurationChanged { return "Folder selection changed. Scan to update results." }
        guard let report else {
            let count = roots.values.reduce(0) { $0 + $1.count }
            return count == 0 ? "Choose folders, then Scan. Standard plugin folders are included by default." : "\(count) folders selected. Scan to build your collection."
        }
        let failed = report.projects.filter { $0.coverage != "partial" }.count
        let stale = report.assets.filter { $0.catalogStale == true }.count
        return "\(report.assets.count) entries · \(stale) not observed in latest scan · \(report.projects.count) projects · \(report.issues.count) scan issues · \(failed) unsupported or failed projects. Reference coverage is partial."
    }

    public var detail: String {
        guard let asset = selectedAsset else { return "Select an item to see its tags and usage." }
        var lines = [asset.name, "", asset.path, "", "Format: \(asset.format.isEmpty ? "Folder" : asset.format.uppercased())",
                     "Type: \(asset.kind == .plugin ? "Plugin installation" : asset.kind == .sample ? "Audio file" : "Library candidate")",
                     "Size: \(asset.logicalBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "Not measured")"]
        if asset.kind == .sample {
            let inclusion = inclusionsByPath[asset.path]
            if isScanning {
                lines += ["", "Project references are still being checked. This item's reference history is not established yet."]
            } else if let inclusion, !inclusion.projectPaths.isEmpty {
                lines += ["", "Referencing projects:"] + inclusion.projectPaths
                lines += ["", "Project recency: \(referenceText(asset)). This uses the latest referencing project's modification date, not when the sample was added or played."]
            } else {
                lines += ["", (report?.projects.isEmpty ?? true) ? "Add project folders to check references." : "No references found in scanned projects. Unsupported formats and unresolved paths may hide references."]
            }
        } else { lines += ["", "Reference matching is not available for plugins or libraries in this preview."] }
        lines += ["", "This is a discovered candidate, not a recommendation to remove it."]
        return lines.joined(separator: "\n")
    }

    public var coverageDetail: String {
        guard let report else { return "No scan yet." }
        var lines = [isScanning ? "Scan is still running; project coverage is pending." : "Scan issues", ""]
        lines += report.issues.map { "\($0.path)\n\($0.reason)\n" }
        lines += ["", "Project coverage", ""]
        lines += report.projects.map { "\($0.path)\n\($0.adapter): \($0.coverage), \($0.references.count) reference candidates\n\($0.limitations.joined(separator: " "))\n" }
        return lines.joined(separator: "\n")
    }

    public var stateSnapshot: [String: Any] {
        ["category": category.rawValue, "query": query, "sort": sort.rawValue, "sort_reversed": sortReversed,
         "standard_plugins": standardPlugins, "online_tags": onlineTags, "appearance": appearance.rawValue, "roots": Dictionary(uniqueKeysWithValues: roots.map { ($0.key.rawValue, $0.value.map(\.path)) }),
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
        ["id": "online_tags", "value_type": "boolean", "default": false, "persisted": true],
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
