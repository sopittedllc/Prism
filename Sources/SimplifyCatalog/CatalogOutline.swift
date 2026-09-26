import Foundation
import SimplifyCore

/// A presentation identity, never a deletion target. Payloads come only from the catalog.
@MainActor public final class CatalogOutlineNode: NSObject {
    public enum Kind: String { case maker, unidentified, library, instrument, root, folder, sample, plugin }
    public let id: String
    public let locatorKey: String
    public let kind: Kind
    public let title: String
    public let breadcrumb: [String]
    public let location: String?
    public let asset: Asset?
    public let instrument: LibraryInstrument?
    public let children: [CatalogOutlineNode]
    public let searchText: String
    public let metadataOnlyMatch: Bool
    public var stale: Bool { asset?.catalogStale == true || instrument?.catalogStale == true }
    public var initiallyExpanded: Bool { kind == .maker || kind == .unidentified || kind == .root }
    public var isGroup: Bool { kind == .maker || kind == .unidentified || kind == .root || kind == .folder }
    public var displayName: String { title + (stale ? " · Not observed" : "") }
    public var sizeText: String {
        if kind == .instrument { return "Shared with library" }
        if kind == .library { return "Not measured" }
        return asset?.logicalBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "—"
    }
    init(id: String, locatorKey: String? = nil, kind: Kind, title: String, breadcrumb: [String],
         location: String? = nil, asset: Asset? = nil, instrument: LibraryInstrument? = nil,
         children: [CatalogOutlineNode] = [], searchText: String = "", metadataOnlyMatch: Bool = false) {
        self.id = id; self.locatorKey = locatorKey ?? id; self.kind = kind; self.title = title
        self.breadcrumb = breadcrumb; self.location = location; self.asset = asset
        self.instrument = instrument; self.children = children; self.searchText = searchText
        self.metadataOnlyMatch = metadataOnlyMatch
    }
    func replacingChildren(_ children: [CatalogOutlineNode], metadataOnly: Bool = false) -> CatalogOutlineNode {
        CatalogOutlineNode(id: id, locatorKey: locatorKey, kind: kind, title: title, breadcrumb: breadcrumb,
                           location: location, asset: asset, instrument: instrument, children: children,
                           searchText: searchText, metadataOnlyMatch: metadataOnly)
    }
}

/// Immutable, in-memory projection. Building and filtering never read the filesystem.
@MainActor public final class CatalogOutline {
    public let roots: [CatalogOutlineNode]
    public let nodes: [CatalogOutlineNode]
    public let byID: [String: CatalogOutlineNode]
    public init(roots: [CatalogOutlineNode]) {
        self.roots = roots
        var nodes: [CatalogOutlineNode] = []
        func visit(_ items: [CatalogOutlineNode]) { for item in items { nodes.append(item); visit(item.children) } }
        visit(roots); self.nodes = nodes
        byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    /// Structured components avoid collisions between names, vendor IDs and paths.
    static func key(_ parts: [String]) -> String {
        String(decoding: try! JSONEncoder().encode(parts), as: UTF8.self)
    }
    public static func build(assets: [Asset], category: AssetKind, sampleRoots: [URL] = [],
                             sort: CatalogSort = .name, recency: [String: Date] = [:],
                             pluginProductIDs: [String: String] = [:]) -> CatalogOutline {
        func ordered(_ values: [CatalogOutlineNode]) -> [CatalogOutlineNode] {
            values.sorted {
                if $0.isGroup != $1.isGroup { return $0.isGroup }
                if category == .sample, !$0.isGroup, !$1.isGroup {
                    if sort == .size, $0.asset?.logicalBytes != $1.asset?.logicalBytes {
                        return ($0.asset?.logicalBytes ?? -1) > ($1.asset?.logicalBytes ?? -1)
                    }
                    if sort == .recency, recency[$0.location ?? ""] != recency[$1.location ?? ""] {
                        return (recency[$0.location ?? ""] ?? .distantPast) > (recency[$1.location ?? ""] ?? .distantPast)
                    }
                }
                let order = $0.title.localizedStandardCompare($1.title)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
        }
        let assets = assets.filter { $0.kind == category }
        if category == .plugin {
            return CatalogOutline(roots: ordered(assets.map {
                CatalogOutlineNode(id: key(["plugin", pluginProductIDs[$0.path] ?? $0.selectionKey]), kind: .plugin, title: $0.name,
                                   breadcrumb: [$0.name], location: $0.path, asset: $0)
            }))
        }
        if category == .library {
            var groups: [String: [CatalogOutlineNode]] = [:]
            var groupNames: [String: String] = [:]
            for asset in assets {
                let metadata = asset.libraryMetadata
                let verified = metadata?.identity?.evidence == .manifest || metadata?.identity?.evidence == .vendorCatalog
                let maker = metadata?.maker.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let groupName = verified ? (maker.isEmpty ? "Unknown maker" : maker) : "Needs identification"
                let groupID = key([verified ? "maker" : "unidentified", groupName])
                let locator = key(["library", asset.path, metadata?.identity?.productID ?? ""])
                let libraryID = asset.catalogID.map { key(["library", $0]) } ?? locator
                let context = [groupName, asset.name]
                let instruments = (metadata?.instruments ?? []).map { instrument in
                    let identity = instrument.vendorID.map { ["vendor", $0] } ?? ["path", instrument.path]
                    return CatalogOutlineNode(id: key([libraryID] + identity), locatorKey: key([locator] + identity),
                        kind: .instrument, title: instrument.name, breadcrumb: context + [instrument.name],
                        location: instrument.path, asset: asset, instrument: instrument,
                        searchText: ([instrument.name] + instrument.tags).joined(separator: " "))
                }
                let productText = ([asset.name, metadata?.maker ?? "", metadata?.player ?? "", metadata?.summary ?? ""]
                                   + (metadata?.tags ?? [])).joined(separator: " ")
                let library = CatalogOutlineNode(id: libraryID, locatorKey: locator, kind: .library, title: asset.name,
                    breadcrumb: context, location: asset.path, asset: asset, children: ordered(instruments),
                    searchText: productText)
                groups[groupID, default: []].append(library); groupNames[groupID] = groupName
            }
            return CatalogOutline(roots: ordered(groups.map { id, items in
                let title = groupNames[id]!
                return CatalogOutlineNode(id: id, kind: items.first?.asset?.libraryMetadata?.identity.map {
                    $0.evidence == .manifest || $0.evidence == .vendorCatalog ? .maker : .unidentified
                } ?? .unidentified, title: title, breadcrumb: [title], children: ordered(items))
            }))
        }
        final class Folder {
            let path: String
            var folders: [String: Folder] = [:]
            var files: [Asset] = []
            init(_ path: String) { self.path = path }
        }
        let configured = Array(Set(sampleRoots.map { $0.standardizedFileURL.path })).sorted { $0.count > $1.count }
        var folders: [String: Folder] = [:]
        for asset in assets {
            let path = URL(fileURLWithPath: asset.path).standardizedFileURL.path
            let root = configured.first { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") }
                ?? URL(fileURLWithPath: path).deletingLastPathComponent().path
            let folder = folders[root] ?? Folder(root); folders[root] = folder
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            let suffix = parent == root ? "" : String(parent.dropFirst(root == "/" ? 1 : root.count + 1))
            var current = folder
            for part in suffix.split(separator: "/") {
                let childPath = URL(fileURLWithPath: current.path).appendingPathComponent(String(part)).path
                let child = current.folders[childPath] ?? Folder(childPath)
                current.folders[childPath] = child; current = child
            }
            current.files.append(asset)
        }
        // Distinguish equal root names using the shortest unambiguous parent suffix.
        // These are display labels only; paths and file names stay unchanged.
        var rootTitles: [String: String] = [:]
        let rootGroups = Dictionary(grouping: Array(folders.keys), by: { URL(fileURLWithPath: $0).lastPathComponent })
        for (name, paths) in rootGroups {
            if paths.count == 1 { rootTitles[paths[0]] = name; continue }
            let parents = paths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().pathComponents }
            var depth = 1
            while depth < (parents.map(\.count).max() ?? 1),
                  Set(parents.map { $0.suffix(depth).joined(separator: "/") }).count < paths.count { depth += 1 }
            for (index, path) in paths.enumerated() {
                rootTitles[path] = name + " · " + parents[index].suffix(depth).joined(separator: "/")
            }
        }
        func node(_ folder: Folder, root: String, context: [String], isRoot: Bool) -> CatalogOutlineNode {
            let title = isRoot ? rootTitles[root]! : URL(fileURLWithPath: folder.path).lastPathComponent
            let breadcrumb = context + [title]
            let subfolders = folder.folders.values.map { node($0, root: root, context: breadcrumb, isRoot: false) }
            let files = folder.files.map { asset in
                CatalogOutlineNode(id: key(["sample", asset.selectionKey]), locatorKey: key(["sample", asset.path]),
                    kind: .sample, title: asset.name, breadcrumb: breadcrumb + [asset.name], location: asset.path,
                    asset: asset, searchText: [asset.name, asset.path, asset.format].joined(separator: " "))
            }
            return CatalogOutlineNode(id: key(["folder", root, folder.path]), kind: isRoot ? .root : .folder,
                title: title, breadcrumb: breadcrumb, location: folder.path, children: ordered(subfolders + files),
                searchText: root)
        }
        return CatalogOutline(roots: ordered(folders.map { node($0.value, root: $0.key, context: [], isRoot: true) }))
    }
    public func filtered(query: String, sort: CatalogSort = .name, recency: [String: Date] = [:],
                         pluginMatches: (Asset) -> Bool = { _ in true }) -> CatalogOutline {
        guard !query.isEmpty else { return self }
        if nodes.contains(where: { $0.kind == .sample }) {
            // Flat results retain their original breadcrumbs and physical locators.
            let results = nodes.filter { $0.kind == .sample && $0.searchText.localizedCaseInsensitiveContains(query) }
            return CatalogOutline(roots: results.sorted {
                if sort == .size, $0.asset?.logicalBytes != $1.asset?.logicalBytes {
                    return ($0.asset?.logicalBytes ?? -1) > ($1.asset?.logicalBytes ?? -1)
                }
                if sort == .recency, recency[$0.location ?? ""] != recency[$1.location ?? ""] {
                    return (recency[$0.location ?? ""] ?? .distantPast) > (recency[$1.location ?? ""] ?? .distantPast)
                }
                let order = $0.title.localizedStandardCompare($1.title)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            })
        }
        func filter(_ node: CatalogOutlineNode) -> CatalogOutlineNode? {
            if node.kind == .plugin { return node.asset.map(pluginMatches) == true ? node : nil }
            let children = node.children.compactMap(filter)
            let matches = !node.isGroup && node.searchText.localizedCaseInsensitiveContains(query)
            guard matches || !children.isEmpty else { return nil }
            return node.replacingChildren(children, metadataOnly: node.kind == .library && children.isEmpty)
        }
        return CatalogOutline(roots: roots.compactMap(filter))
    }
}

/// Registry-backed session navigation. Search has a separate temporary context so it
/// cannot erase browsing expansion/selection; no state is written to setup or catalog.
@MainActor public final class CatalogOutlineState {
    private struct ViewState {
        var expanded = Set<String>()
        var collapsed = Set<String>()
        var selection: String?
        var snapshot: [String: Any] {
            ["expanded": expanded.sorted(), "collapsed": collapsed.sorted(), "selection": selection as Any? ?? NSNull()]
        }
        mutating func remap(_ ids: [String: String]) {
            expanded = Set(expanded.map { ids[$0] ?? $0 }); collapsed = Set(collapsed.map { ids[$0] ?? $0 })
            selection = selection.map { ids[$0] ?? $0 }
        }
    }
    private var browsing: [AssetKind: ViewState] = [:]
    private var searching: [AssetKind: (String, ViewState)] = [:]
    public init() {}
    public func reset() { browsing = [:]; searching = [:] }
    private func state(_ category: AssetKind, _ query: String) -> ViewState {
        if query.isEmpty { return browsing[category] ?? ViewState() }
        return searching[category]?.0 == query ? searching[category]!.1 : ViewState()
    }
    private func update(_ category: AssetKind, _ query: String, _ mutate: (inout ViewState) -> Void) {
        var value = state(category, query); mutate(&value)
        if query.isEmpty { browsing[category] = value } else { searching[category] = (query, value) }
    }
    public func selectedID(category: AssetKind, query: String) -> String? { state(category, query).selection }
    public func select(_ id: String?, category: AssetKind, query: String) {
        update(category, query) { $0.selection = id }
    }
    public func isExpanded(_ node: CatalogOutlineNode, category: AssetKind, query: String) -> Bool {
        let value = state(category, query)
        return !value.collapsed.contains(node.id) && (value.expanded.contains(node.id) || node.initiallyExpanded || !query.isEmpty)
    }
    public func setExpanded(_ expanded: Bool, node: CatalogOutlineNode, category: AssetKind, query: String) {
        update(category, query) {
            if expanded { $0.expanded.insert(node.id); $0.collapsed.remove(node.id) }
            else { $0.expanded.remove(node.id); $0.collapsed.insert(node.id) }
        }
    }
    func reconcile(previous: CatalogOutline?, current: CatalogOutline, category: AssetKind) {
        guard let previous else { return }
        let locators = Dictionary(current.nodes.map { ($0.locatorKey, $0.id) }, uniquingKeysWith: { first, _ in first })
        var mapping: [String: String] = [:]
        for node in previous.nodes where current.byID[node.id] == nil {
            if let replacement = locators[node.locatorKey] { mapping[node.id] = replacement }
        }
        browsing[category]?.remap(mapping)
        if var search = searching[category] { search.1.remap(mapping); searching[category] = search }
    }
    public var snapshot: [String: Any] {
        var result = browsing.mapValues(\.snapshot).reduce(into: [String: Any]()) { $0[$1.key.rawValue] = $1.value }
        for (category, value) in searching { result[category.rawValue + ".search"] = ["query": value.0, "state": value.1.snapshot] }
        return result
    }
}
