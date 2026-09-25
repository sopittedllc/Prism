import Foundation
import SimplifyCore

public enum RootKind: String, CaseIterable, Sendable {
    case plugins = "Plugins", samples = "Samples", libraries = "Libraries", projects = "Projects"
}
public enum CatalogSort: String, CaseIterable, Sendable { case name = "Name", size = "Size", recency = "Last used" }

/// Browsing is session-only; accepted scan setup can be stored locally.
@MainActor public final class CatalogModel {
    public var category: AssetKind = .plugin { didSet { cachedVisible = nil } }
    public var query = "" { didSet { cachedVisible = nil } }
    public var sort: CatalogSort = .name { didSet { cachedVisible = nil } }
    public var standardPlugins = true
    public private(set) var roots: [RootKind: [URL]] = [:]
    public var selectedPath: String?
    public private(set) var report: ScanReport? { didSet { rebuildIndexes() } }
    public private(set) var isScanning = false
    public private(set) var configurationChanged = false
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
    private var cachedVisible: [Asset]?
    private var assetsByKey: [String: Asset] = [:]
    private var inclusionsByPath: [String: SampleInclusion] = [:]
    public private(set) var pluginProducts: [PluginProduct] = []
    private var productsByPath: [String: PluginProduct] = [:]
    private var candidateProjects: [String: [ProjectReport]] = [:]
    public private(set) var isRemoving = false
    public var isBusy: Bool { isScanning || isRemoving }
    private var categoryCounts: [AssetKind: Int] = [:]

    private func rebuildIndexes() {
        cachedVisible = nil; assetsByKey = [:]; inclusionsByPath = [:]; categoryCounts = [:]
        for asset in report?.assets ?? [] {
            assetsByKey[asset.kind.rawValue + ":" + asset.path] = asset
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
    private func matchesQuery(_ asset: Asset) -> Bool {
        query.isEmpty || [asset.name, asset.path, asset.format, PluginProduct.formatName(asset.format), asset.classification, asset.libraryMetadata?.searchText ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
    }

    public private(set) var onboardingCompleted = false
    public private(set) var setupNotice: String?
    private let store: SetupStore?

    public init(store: SetupStore? = nil) {
        self.store = store
        do {
            if let values = try store?.load() {
                standardPlugins = values["standard_plugins"] as? Bool ?? true
                onboardingCompleted = values["onboarding_completed"] as? Bool ?? false
                for (key, paths) in values["roots"] as? [String: [String]] ?? [:] {
                    if let kind = RootKind(rawValue: key) { roots[kind] = paths.map { URL(fileURLWithPath: $0) } }
                }
            }
        } catch { setupNotice = error.localizedDescription }
    }

    public func setupDraft() -> CatalogModel {
        let draft = CatalogModel()
        draft.standardPlugins = standardPlugins; draft.roots = roots
        return draft
    }

    public func acceptSetup(_ draft: CatalogModel, remember: Bool) throws {
        guard !isBusy else { return }
        var values = draft.stateSnapshot; values["onboarding_completed"] = true
        if remember { try store?.save(values) }
        standardPlugins = draft.standardPlugins; roots = draft.roots
        onboardingCompleted = true; configurationChanged = report != nil
        setupNotice = remember ? nil : "Setup is being used for this session only."
        onChange?()
    }

    public func reset() {
        guard !isBusy else { return }
        category = .plugin; query = ""; sort = .name; standardPlugins = true
        roots = [:]; selectedPath = nil; report = nil; configurationChanged = false; onboardingCompleted = false; setupNotice = nil; scanProgress = nil; scanStartedAt = nil; basicInventoryComplete = false; isBackgroundScanning = false
        onChange?()
    }

    public func addRoots(_ urls: [URL], kind: RootKind) {
        guard !isBusy else { return }
        for raw in urls {
            let url = raw.standardizedFileURL
            if !(roots[kind] ?? []).contains(url) { roots[kind, default: []].append(url) }
        }
        configurationChanged = report != nil
        onChange?()
    }

    public func removeRoot(_ url: URL, kind: RootKind) {
        guard !isBusy else { return }
        roots[kind]?.removeAll { $0 == url }
        configurationChanged = report != nil
        onChange?()
    }

    public func setStandardPlugins(_ enabled: Bool) {
        guard !isBusy else { return }
        standardPlugins = enabled; configurationChanged = report != nil; onChange?()
    }

    public func scan() {
        guard !isBusy else { return }
        var request = ScanRequest()
        request.plugins = (standardPlugins ? ScanRequest.standardPluginRoots : []) + (roots[.plugins] ?? [])
        request.samples = roots[.samples] ?? []; request.libraries = roots[.libraries] ?? []
        request.projects = roots[.projects] ?? []
        scanIdentifier = UUID(); let identifier = scanIdentifier
        scanStartedAt = Date(); scanProgress = nil; inventorySequence = 0; basicInventoryComplete = false
        isBackgroundScanning = report != nil
        foregroundTask?.cancel()
        foregroundTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, self.isScanning, self.scanIdentifier == identifier else { return }
            self.isBackgroundScanning = true; self.onChange?()
        }
        isScanning = true; onChange?()
        let snapshot = request
        scanTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { [weak self] in
                Scanner().scan(snapshot, inventory: { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let owner = self, owner.isScanning, owner.scanIdentifier == identifier,
                              update.sequence > owner.inventorySequence else { return }
                        owner.inventorySequence = update.sequence
                        owner.basicInventoryComplete = update.discoveryComplete
                        owner.isBackgroundScanning = true
                        owner.report = ScanReport(inventory: update)
                        owner.onChange?()
                    }
                }) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self, self.isScanning, self.scanIdentifier == identifier,
                              update.sequence > (self.scanProgress?.sequence ?? 0) else { return }
                        self.scanProgress = update; self.onProgressChange?()
                    }
                }
            }.value
            guard let self else { return }
            self.report = result; self.isScanning = false; self.configurationChanged = false; self.isBackgroundScanning = false; self.basicInventoryComplete = true; self.foregroundTask?.cancel()
            if let selected = self.selectedPath, !result.assets.contains(where: { $0.path == selected && $0.kind == self.category }) {
                self.selectedPath = nil
            }
            self.onChange?()
        }
    }

    public var visibleAssets: [Asset] {
        if let cachedVisible { return cachedVisible }
        let source = category == .plugin ? pluginProducts.map(\.representative) : (report?.assets ?? [])
        let result = source.filter { $0.kind == category && matchesRow($0)
        }.sorted { left, right in
            switch sort {
            case .name: break
            case .size:
                if left.logicalBytes != right.logicalBytes { return (left.logicalBytes ?? -1) > (right.logicalBytes ?? -1) }
            case .recency:
                let a = inclusionsByPath[left.path]?.latestReferencingProjectModifiedAt, b = inclusionsByPath[right.path]?.latestReferencingProjectModifiedAt
                if a != b { return (a ?? .distantPast) > (b ?? .distantPast) }
            }
            let comparison = left.name.localizedStandardCompare(right.name)
            return comparison == .orderedSame ? left.path < right.path : comparison == .orderedAscending
        }
        cachedVisible = result
        return result
    }

    public var selectedAsset: Asset? {
        guard let selectedPath, let asset = assetsByKey[category.rawValue + ":" + selectedPath], matchesRow(asset) else { return nil }
        return asset
    }
    private func matchesRow(_ asset: Asset) -> Bool {
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
    /// Explicitly reviewed installation paths only. Caller must present confirmation first.
    public func trashPlugins(_ reviewed: [Asset]) async -> [PluginRemovalResult] {
        let paths = Set(reviewed.map(\.path))
        guard !isBusy, !paths.isEmpty else { return [] }
        let selected = selectedPlugin
        let current = (report?.assets ?? []).filter { $0.kind == .plugin && paths.contains($0.path) }
        guard reviewed.count == paths.count, current.count == paths.count,
              reviewed.allSatisfy({ item in current.contains { $0.path == item.path && $0.fileIdentity == item.fileIdentity && $0.bundleIdentifier == item.bundleIdentifier } }) else { return [] }
        let targets = reviewed
        isRemoving = true; onChange?()
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
        return count == 0 ? "No custom folders selected for this collection. Add folders in Manage locations." : "No matching items were found in \(count) configured location(s). Add sample folders or parent folders containing your libraries, then scan again."
    }
    public var totalCount: Int { categoryCounts[category, default: 0] }

    public func referenceText(_ asset: Asset) -> String {
        if asset.kind == .plugin, let product = productsByPath[asset.path] {
            if isScanning { return "Checking…" }
            _ = product
            return "Unknown"
        }
        guard asset.kind == .sample else { return "Not available" }
        if isScanning { return "Checking…" }
        guard let inclusion = inclusionsByPath[asset.path],
              let date = inclusion.latestReferencingProjectModifiedAt else { return "Not established" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    public var status: String {
        if isRemoving { return "Moving selected plugin installations to Trash…" }
        if isScanning { return basicInventoryComplete ? "Collection ready. Project references are being checked in the background." : "Discovering your collection in the background. More items may appear." }
        if configurationChanged { return "Folder selection changed. Scan to update results." }
        guard let report else {
            let count = roots.values.reduce(0) { $0 + $1.count }
            return count == 0 ? "Choose folders, then Scan. Standard plugin folders are included by default." : "\(count) folders selected. Scan to build your collection."
        }
        let failed = report.projects.filter { $0.coverage != "partial" }.count
        return "\(report.assets.count) entries · \(report.projects.count) projects · \(report.issues.count) scan issues · \(failed) unsupported or failed projects. Reference coverage is partial."
    }

    public var detail: String {
        guard let asset = selectedAsset else { return "Select an item to see its location and reference evidence." }
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
        ["category": category.rawValue, "query": query, "sort": sort.rawValue,
         "standard_plugins": standardPlugins, "roots": Dictionary(uniqueKeysWithValues: roots.map { ($0.key.rawValue, $0.value.map(\.path)) }),
         "selection": selectedPath as Any? ?? NSNull(), "onboarding_completed": onboardingCompleted]
    }
}

@MainActor public enum CatalogStateRegistry {
    public static var persistedIDs: Set<String> { Set(definitions.filter { $0["persisted"] as? Bool == true }.compactMap { $0["id"] as? String }) }
    public static let definitions: [[String: Any]] = [
        ["id": "category", "value_type": "enumeration", "default": "plugin"],
        ["id": "query", "value_type": "string", "default": ""],
        ["id": "sort", "value_type": "enumeration", "default": "Name"],
        ["id": "standard_plugins", "value_type": "boolean", "default": true, "persisted": true],
        ["id": "roots", "value_type": "object", "default": [String: [String]](), "persisted": true],
        ["id": "onboarding_completed", "value_type": "boolean", "default": false, "persisted": true],
        ["id": "selection", "value_type": "string", "default": NSNull()],
    ]
}
