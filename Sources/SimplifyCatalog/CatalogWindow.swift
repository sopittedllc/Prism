import AppKit
import SimplifyCore

@MainActor public final class CatalogWindow: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    public let model: CatalogModel
    public let categoryButtons = [NSButton(title: "Plugins", target: nil, action: nil), NSButton(title: "Individual Samples", target: nil, action: nil), NSButton(title: "Libraries", target: nil, action: nil)]
    public let scanButton = NSButton(title: "Scan", target: nil, action: nil)
    public let search = NSSearchField()
    public let table = NSOutlineView()
    public let detail = NSTextView()
    public private(set) var setup: SetupWindow?
    public private(set) var formatsWindow: PluginFormatsWindow?
    public let formatsButton = NSButton(title: "Manage formats…", target: nil, action: nil)
    private let titleLabel = label("Plugins", size: 26, weight: .bold)
    private let countLabel = label("Your audio tools, together.", secondary: true)
    private let statusLabel = label("", size: 11, secondary: true)
    private let folderButton = NSButton(title: "Manage locations…", target: nil, action: nil)
    private let issuesButton = NSButton(title: "Scan details", target: nil, action: nil)
    private let sortMenu = NSPopUpButton()
    private let progress = NSProgressIndicator()
    public let scanProgressBar = ScanProgressTrack(frame: .zero)
    private let discoveryProgressBar = NSProgressIndicator()
    public let scanProgressLabel = label("", size: 12, weight: .semibold)
    private let scanProgressDetail = label("", size: 11, secondary: true)
    private let scanBanner = NSView()
    private var progressTimer: Timer?
    private let emptyTitle = label("Meet your collection.", size: 22, weight: .semibold)
    private let emptyBody = label("Set up your sound folders, then bring everything into view.", secondary: true)
    private let emptyButton = NSButton(title: "Set up Simplify", target: nil, action: nil)
    private let emptyContainer = NSView()
    private let inspectorTitle = label("A closer look", size: 17, weight: .semibold)
    private let inspectorMeta = label("Select an item to explore its details.", size: 12, secondary: true)
    private let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)
    private let collectionScroll = NSScrollView()
    private var outline = CatalogOutline(roots: [])
    private var presentationContext = ""
    public var selectedNode: CatalogOutlineNode? { table.item(atRow: table.selectedRow) as? CatalogOutlineNode }
    private var coverageWindow: NSWindow?
    private var refreshing = false

    public init(model: CatalogModel = CatalogModel()) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1220, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Simplify"; window.minSize = NSSize(width: 1040, height: 680)
        window.contentView = CatalogBackground(frame: .zero); window.isReleasedWhenClosed = false
        super.init(window: window)
        build(); model.onChange = { [weak self] in self?.refresh() }; model.onProgressChange = { [weak self] in self?.refreshProgress() }; refresh(); window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    private func build() {
        guard let content = window?.contentView else { return }
        let sidebar = NSVisualEffectView(); sidebar.material = .sidebar; sidebar.blendingMode = .behindWindow
        let main = NSView(); let inspector = NSView()
        let split = NSStackView(views: [sidebar, main, inspector]); split.spacing = 0; split.alignment = .top; split.distribution = .fill
        pin(split, in: content)
        for view in [sidebar, main, inspector] { view.heightAnchor.constraint(equalTo: split.heightAnchor).isActive = true }
        sidebar.widthAnchor.constraint(equalToConstant: 192).isActive = true
        inspector.widthAnchor.constraint(equalToConstant: 272).isActive = true
        main.widthAnchor.constraint(greaterThanOrEqualToConstant: 550).isActive = true
        let brand = NSStackView(views: [Brand.mark(size: 38), label("Simplify", size: 20, weight: .bold)]); brand.spacing = 10
        let sidebarStack = column([brand, label("YOUR COLLECTION", size: 10, weight: .semibold, secondary: true)], spacing: 22)
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(sidebarStack)
        NSLayoutConstraint.activate([sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16), sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16), sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 26)])
        let nav = column([], spacing: 5)
        for (index, button) in categoryButtons.enumerated() {
            let title = button.title; button.cell = InsetButtonCell(textCell: title); button.isEnabled = true; button.contentTintColor = .labelColor
            button.tag = index; button.target = self; button.action = #selector(changeCategory(_:))
            button.image = NSImage(systemSymbolName: ["slider.horizontal.3", "waveform", "square.stack.3d.up"][index], accessibilityDescription: nil)
            button.imagePosition = .imageLeading; button.alignment = .left; button.isBordered = false
            button.font = .systemFont(ofSize: 13, weight: .medium); button.setAccessibilityLabel(button.title)
            button.wantsLayer = true; button.layer?.cornerRadius = 8
            nav.addArrangedSubview(button); button.widthAnchor.constraint(equalTo: nav.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        }
        sidebarStack.addArrangedSubview(nav); nav.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
        folderButton.target = self; folderButton.action = #selector(showSetup); folderButton.bezelStyle = .rounded
        folderButton.font = .systemFont(ofSize: 11)
        let sidebarBottom = column([folderButton, label("Made for your music.\nFree. Local. Yours.", size: 11, secondary: true)], spacing: 16)
        sidebarBottom.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(sidebarBottom)
        NSLayoutConstraint.activate([sidebarBottom.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16), sidebarBottom.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12), sidebarBottom.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -24)])
        scanButton.target = self; scanButton.action = #selector(scan); scanButton.bezelStyle = .rounded
        scanButton.bezelColor = CatalogTheme.accent; scanButton.keyEquivalent = "r"; scanButton.keyEquivalentModifierMask = .command
        scanButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil); scanButton.imagePosition = .imageLeading
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        let heading = NSStackView(views: [column([titleLabel, countLabel], spacing: 4), NSView(), progress, scanButton]); heading.spacing = 12
        search.placeholderString = "Search plugins"; search.delegate = self; search.sendsSearchStringImmediately = true; search.setAccessibilityLabel("Search collection")
        sortMenu.addItems(withTitles: CatalogSort.allCases.map(\.rawValue)); sortMenu.target = self; sortMenu.action = #selector(changeSort)
        sortMenu.setAccessibilityLabel("Sort collection"); sortMenu.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let filters = NSStackView(views: [search, sortMenu]); filters.spacing = 10
        for (id, title, width) in [("name", "Name", 290.0), ("format", "Format", 75.0), ("size", "Size", 90.0), ("reference", "Project recency", 140.0)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); col.title = title; col.width = width; col.minWidth = id == "name" ? 155 : 65; table.addTableColumn(col)
        }
        table.dataSource = self; table.delegate = self; table.rowHeight = 38; table.style = .inset
        table.outlineTableColumn = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("name"))
        table.indentationPerLevel = 16; table.autoresizesOutlineColumn = false
        table.usesAlternatingRowBackgroundColors = false; table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.setAccessibilityLabel("Audio collection")
        collectionScroll.documentView = table; collectionScroll.hasVerticalScroller = true; collectionScroll.hasHorizontalScroller = true
        let collection = NSView(); pin(collectionScroll, in: collection); pin(emptyContainer, in: collection)
        let empty = column([Brand.mark(size: 62), emptyTitle, emptyBody, emptyButton], spacing: 16)
        emptyBody.preferredMaxLayoutWidth = 340
        empty.translatesAutoresizingMaskIntoConstraints = false; emptyContainer.addSubview(empty)
        NSLayoutConstraint.activate([empty.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor), empty.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor), empty.widthAnchor.constraint(equalToConstant: 350)])
        emptyButton.target = self; emptyButton.action = #selector(emptyAction); emptyButton.bezelStyle = .rounded
        issuesButton.target = self; issuesButton.action = #selector(showIssues); issuesButton.bezelStyle = .rounded; issuesButton.controlSize = .small
        let footer = NSStackView(views: [statusLabel, NSView(), issuesButton]); footer.spacing = 8
        discoveryProgressBar.style = .bar; discoveryProgressBar.isIndeterminate = true
        discoveryProgressBar.setAccessibilityLabel("Finding files; total not yet known")
        let progressTrack = NSView(); pin(scanProgressBar, in: progressTrack); pin(discoveryProgressBar, in: progressTrack)
        progressTrack.heightAnchor.constraint(equalToConstant: 6).isActive = true
        scanProgressBar.setAccessibilityLabel("Current scan phase progress")
        scanProgressLabel.setAccessibilityLabel("Scan status")
        scanProgressDetail.lineBreakMode = .byTruncatingMiddle; scanProgressDetail.maximumNumberOfLines = 1
        let bannerStack = column([scanProgressLabel, progressTrack, scanProgressDetail], spacing: 6)
        pin(bannerStack, in: scanBanner)
        for view in bannerStack.arrangedSubviews { view.widthAnchor.constraint(equalTo: bannerStack.widthAnchor).isActive = true }
        let mainStack = column([heading, filters, scanBanner, collection, footer], spacing: 18); pin(mainStack, in: main, inset: 24)
        for view in [heading, filters, scanBanner, collection, footer] { view.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true }
        collection.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        collection.setContentHuggingPriority(.defaultLow, for: .vertical)
        inspectorTitle.maximumNumberOfLines = 3; inspectorTitle.lineBreakMode = .byTruncatingMiddle
        inspector.wantsLayer = true
        let line = NSBox(); line.boxType = .separator; line.translatesAutoresizingMaskIntoConstraints = false; inspector.addSubview(line)
        NSLayoutConstraint.activate([line.leadingAnchor.constraint(equalTo: inspector.leadingAnchor), line.topAnchor.constraint(equalTo: inspector.topAnchor), line.bottomAnchor.constraint(equalTo: inspector.bottomAnchor), line.widthAnchor.constraint(equalToConstant: 1)])
        detail.setAccessibilityLabel("Selected item details")
        let scroll = Self.textScroll(detail); detail.backgroundColor = .windowBackgroundColor; detail.textContainerInset = .zero
        revealButton.target = self; revealButton.action = #selector(reveal); revealButton.bezelStyle = .rounded
        formatsButton.target = self; formatsButton.action = #selector(showFormats); formatsButton.bezelStyle = .rounded
        let inspectorStack = column([label("DETAILS", size: 10, weight: .semibold, secondary: true), inspectorTitle, inspectorMeta, scroll, formatsButton, revealButton, label("Reference coverage is partial.", size: 11, secondary: true)], spacing: 16)
        pin(inspectorStack, in: inspector, inset: 22)
        for view in [inspectorTitle, inspectorMeta, scroll] { view.widthAnchor.constraint(equalTo: inspectorStack.widthAnchor).isActive = true }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true; scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    public static func textScroll(_ text: NSTextView) -> NSScrollView {
        text.isEditable = false; text.isSelectable = true; text.isRichText = false
        text.font = .systemFont(ofSize: 12); text.textColor = .labelColor; text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 8, height: 8); text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView(); scroll.documentView = text; scroll.hasVerticalScroller = true; return scroll
    }

    public func refresh() {
        refreshing = true; defer { refreshing = false }
        outline = model.outline; table.reloadData(); table.collapseItem(nil, collapseChildren: true)
        func expand(_ nodes: [CatalogOutlineNode]) {
            for node in nodes where !node.children.isEmpty && model.outlineState.isExpanded(node, category: model.category, query: model.query) {
                table.expandItem(node); expand(node.children)
            }
        }
        expand(outline.roots)
        let selectedID = model.outlineState.selectedID(category: model.category, query: model.query)
        let selected = selectedID.flatMap { outline.byID[$0] }
        let row = selected.map { table.row(forItem: $0) } ?? -1
        if row >= 0 { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
        model.selectedPath = selectedNode?.asset?.selectionKey
        let context = model.category.rawValue + ":" + model.query
        if context != presentationContext, row >= 0 { table.scrollRowToVisible(row) }
        presentationContext = context
        let index = [AssetKind.plugin, .sample, .library].firstIndex(of: model.category) ?? 0
        for (i, button) in categoryButtons.enumerated() {
            button.state = i == index ? .on : .off
            button.layer?.backgroundColor = (i == index ? CatalogTheme.accent.withAlphaComponent(0.14) : NSColor.clear).cgColor
        }
        let title = ["Plugins", "Individual Samples", "Libraries"][index]; titleLabel.stringValue = title
        search.placeholderString = model.category == .library ? "Search libraries and instruments" : "Search \(model.category == .sample ? "samples" : "plugins")"
        search.stringValue = model.query
        let count = outline.nodes.filter { $0.kind == .plugin || $0.kind == .library || $0.kind == .sample }.count
        let instruments = outline.nodes.filter { $0.kind == .instrument }.count
        let noun = model.category == .plugin ? (count == 1 ? "plugin" : "plugins") : model.category == .sample ? (count == 1 ? "sample" : "samples") : (count == 1 ? "library" : "libraries")
        countLabel.stringValue = model.report == nil ? ["Your audio tools, together.", "Small sounds. Endless possibilities.", "A home for your instruments."][index] : "\(count.formatted()) \(noun)" + (model.category == .library ? " · \(instruments.formatted()) \(instruments == 1 ? "instrument" : "instruments")" : "") + (model.query.isEmpty ? "" : " matching your search")
        if !model.isScanning, model.report?.issues.contains(where: { $0.reason.contains("Entry limit") }) == true { countLabel.stringValue += " · partial scan" }
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("reference"))?.isHidden = false
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("reference"))?.title = model.category == .sample ? "Project recency" : "Last used"
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("size"))?.title = model.category == .library ? "Installed size" : "Size"
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("size"))?.width = model.category == .library ? 135 : 90
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("format"))?.title = model.category == .library ? "Player / format" : "Format"
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("format"))?.width = model.category == .library ? 105 : 75
        for id in ["format", "size"] { table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id))?.isHidden = model.category == .plugin }
        sortMenu.item(at: 1)?.isEnabled = model.category == .sample
        sortMenu.item(at: 2)?.isEnabled = model.category == .sample
        sortMenu.selectItem(withTitle: model.sort.rawValue)
        scanButton.isEnabled = !model.isBusy; folderButton.isEnabled = !model.isBusy
        issuesButton.isEnabled = model.report != nil
        if model.isScanning { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        refreshProgress()
        statusLabel.stringValue = model.isRemoving ? "Moving selected installations to Trash…" : model.catalogNotice ?? model.setupNotice ?? (model.usingSavedCatalog && !model.isScanning ? "Saved collection · Scan to refresh" : model.isScanning ? (model.isBackgroundScanning ? "Updating in background · browse as results arrive" : "Finding your collection…") : model.configurationChanged ? "Locations changed. Scan to update." : model.report == nil ? "Ready when you are." : "\(model.report!.projects.count) projects · \(model.report!.issues.count) scan issue\(model.report!.issues.count == 1 ? "" : "s")")
        statusLabel.toolTip = model.status
        emptyContainer.isHidden = !outline.roots.isEmpty; collectionScroll.isHidden = outline.roots.isEmpty
        emptyTitle.stringValue = model.isScanning ? (model.isBackgroundScanning ? "Your collection is open." : "Finding your sounds…") : model.report == nil ? "Meet your collection." : model.query.isEmpty ? "No items found." : "No matches."
        emptyBody.stringValue = model.isScanning ? "Items appear as they are found. You can switch collections and search while project references are checked in the background." : model.report == nil ? model.locationSummary : model.query.isEmpty ? model.locationSummary : "Try another name or clear your search to see the collection."
        emptyButton.title = model.query.isEmpty ? "Set up locations…" : "Clear search"; emptyButton.isEnabled = !model.isScanning || !model.query.isEmpty
        updateInspector()
    }
    @objc private func progressTick() { refreshProgress() }
    public func refreshProgress() {
        scanBanner.isHidden = !model.isScanning
        guard model.isScanning else { progressTimer?.invalidate(); progressTimer = nil; discoveryProgressBar.stopAnimation(nil); return }
        if progressTimer == nil { progressTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(progressTick), userInfo: nil, repeats: true) }
        let update = model.scanProgress
        let phase = update?.phase ?? .discovering
        let title: String
        switch phase {
        case .discovering: title = "1 of 3 · Finding files"
        case .inspecting: title = "2 of 3 · Reading files"
        case .matching: title = "3 of 3 · Matching references"
        case .complete: title = "Finishing scan"
        }
        if let fraction = update?.fraction {
            discoveryProgressBar.stopAnimation(nil); discoveryProgressBar.isHidden = true
            scanProgressBar.isHidden = false; scanProgressBar.doubleValue = fraction * 100
            scanProgressLabel.stringValue = "\(title) · \(Int(fraction * 100))%"
        } else {
            scanProgressBar.isHidden = true; discoveryProgressBar.isHidden = false; discoveryProgressBar.startAnimation(nil)
            scanProgressLabel.stringValue = title
        }
        let seconds = max(0, Int(Date().timeIntervalSince(model.scanStartedAt ?? Date())))
        let elapsed = seconds < 60 ? "\(seconds)s elapsed" : "\(seconds / 60)m \(seconds % 60)s elapsed"
        let count = update?.completed ?? 0
        let counts = update?.total.map { "\(count.formatted()) of \($0.formatted())" } ?? "\(count.formatted()) entries checked"
        let current = update?.currentPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Preparing…"
        scanProgressDetail.stringValue = "\(counts) · \(elapsed) · \(current)"
        scanProgressDetail.toolTip = update?.currentPath
    }
    private func updateInspector() {
        let node = selectedNode
        formatsButton.isHidden = node?.kind != .plugin || model.selectedPlugin == nil
        formatsButton.isEnabled = !model.isBusy
        inspectorTitle.toolTip = node?.breadcrumb.joined(separator: " › ")
        detail.textStorage?.setAttributedString(NSAttributedString(string: "", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
        detail.typingAttributes = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        guard let node else {
            inspectorTitle.stringValue = "A closer look"; inspectorMeta.stringValue = "Select an item to see its location and project references."; detail.string = "Choose an item to see its formats, locations, and available project evidence."; revealButton.isEnabled = false; return
        }
        inspectorTitle.stringValue = node.displayName
        revealButton.isEnabled = node.location != nil
        if node.isGroup {
            inspectorMeta.stringValue = node.kind == .maker ? "Maker" : node.kind == .unidentified ? "Unverified library identities" : "Sample folder"
            detail.string = node.breadcrumb.joined(separator: " › ") + "\n\n\(node.children.count.formatted()) entries in this group."
            if node.kind == .unidentified { detail.string += "\n\nThese library boundaries are proposed or unresolved. They are not vendor-confirmed products." }
            if let path = node.location {
                let parts = URL(fileURLWithPath: path).pathComponents
                let volume = parts.count > 2 && parts[1] == "Volumes" ? parts[2] : "Startup volume"
                detail.string += "\n\nVOLUME\n\(volume)\n\nLOCATION\n\(path)\n\nFolders reflect discovered samples. No files are moved by this view."
            }
            return
        }
        guard let asset = node.asset else { return }
        if node.kind == .library || node.kind == .instrument {
            let metadata = asset.libraryMetadata
            inspectorMeta.stringValue = node.kind == .instrument ? "Instrument · \(metadata?.player ?? asset.format)" : "Library · \(metadata?.player ?? asset.format)"
            let tags = node.instrument.map { metadata?.tags(for: $0, productName: asset.name) ?? $0.tags } ?? metadata?.tags ?? []
            var sections = [node.breadcrumb.joined(separator: " › ")]
            if node.metadataOnlyMatch { sections.append("Library metadata match. No individual installed instrument matched this search.") }
            if let summary = metadata?.summary, !summary.isEmpty { sections.append(summary) }
            if node.kind == .instrument {
                sections.append("PARENT LIBRARY\n\(asset.name)\nInstalled size: Not measured\nInstrument storage: Shared with library")
            } else {
                let count = metadata?.instruments.count ?? 0
                let guidance = count == 0 ? "No indexed instruments." : node.metadataOnlyMatch ? "Clear search to browse." : "Expand this library to browse."
                sections.append("INSTALLED SIZE\nNot measured\n\nINSTRUMENTS\n\(count) indexed · \(guidance)")
            }
            if !tags.isEmpty { sections.append("TAGS\n" + tags.joined(separator: ", ")) }
            sections.append("USAGE\nUnknown. Instrument discovery does not establish project inclusion.")
            if node.stale { sections.append("AVAILABILITY\nNot observed in the latest scan. This retained entry may be offline or moved.") }
            sections.append("IDENTIFICATION\n\(metadata?.source ?? asset.classification)")
            if let location = node.location { sections.append("LOCATION\n" + location) }
            detail.string = sections.joined(separator: "\n\n")
            highlightSearch()
            return
        }
        inspectorMeta.stringValue = "\(asset.format.isEmpty ? "Folder" : asset.format.uppercased())  ·  \(asset.logicalBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "Size not measured")"
        if let product = model.selectedPlugin {
            inspectorMeta.stringValue = "\(product.installations.count) installation(s) · \(product.formats)"
            detail.string = "INSTALLED FORMATS\n\n" + product.installations.map { PluginProduct.formatName($0.format) + "\n" + $0.path }.joined(separator: "\n\n") + "\n\nPROJECT REFERENCES\n\n" + model.pluginReferenceDetail(product)
            revealButton.isEnabled = true
            return
        }
        let reference = model.detail.components(separatedBy: "\n\n").dropFirst(3).joined(separator: "\n\n")
        detail.string = node.breadcrumb.joined(separator: " › ") + "\n\nAudio file\n\nLOCATION\n\n\(asset.path)\n\nPROJECT REFERENCES\n\n\(reference)"
        let string = NSMutableAttributedString(string: detail.string, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
        for title in ["LOCATION", "PROJECT REFERENCES"] {
            string.addAttributes([.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.labelColor], range: (string.string as NSString).range(of: title))
        }
        detail.textStorage?.setAttributedString(string); revealButton.isEnabled = true
        highlightSearch()
    }
    private func highlightSearch() {
        guard !model.query.isEmpty, let storage = detail.textStorage else { return }
        let text = storage.string as NSString
        var remaining = NSRange(location: 0, length: text.length)
        while remaining.length > 0 {
            let match = text.range(of: model.query, options: [.caseInsensitive, .diacriticInsensitive], range: remaining)
            guard match.location != NSNotFound else { break }
            storage.addAttributes([.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor], range: match)
            remaining = NSRange(location: NSMaxRange(match), length: text.length - NSMaxRange(match))
        }
    }
    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? CatalogOutlineNode)?.children.count ?? outline.roots.count
    }
    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? CatalogOutlineNode)?.children ?? outline.roots)[index]
    }
    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !(item as! CatalogOutlineNode).children.isEmpty
    }
    public func outlineView(_ outlineView: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? CatalogOutlineNode else { return nil }
        let value: String
        switch column?.identifier.rawValue {
        case "format":
            value = node.instrument.map { URL(fileURLWithPath: $0.path).pathExtension.uppercased() }
                .flatMap { $0.isEmpty ? nil : $0 } ?? node.asset.map { $0.libraryMetadata?.player ?? $0.format.uppercased() } ?? ""
        case "size": value = node.isGroup ? "" : node.sizeText
        case "reference":
            value = node.isGroup ? "" : node.kind == .library || node.kind == .instrument ? "Unknown" : node.asset.map(model.referenceText) ?? ""
        default:
            let product = node.asset.flatMap(model.product)
            let stale = product.map { $0.installations.allSatisfy { $0.catalogStale == true } } ?? node.stale
            value = (product?.name ?? node.title) + (stale ? " · Not observed" : "")
        }
        let subtitle: String?
        if column?.identifier.rawValue == "name", node.metadataOnlyMatch {
            subtitle = "Library metadata match"
        } else if column?.identifier.rawValue == "name", !model.query.isEmpty, node.kind == .sample {
            subtitle = node.breadcrumb.dropLast().joined(separator: " › ")
        } else { subtitle = nil }
        return CatalogCell(value: value, primary: column?.identifier.rawValue == "name", subtitle: subtitle,
                           query: model.query, context: [node.kind == .sample ? "Audio file" : nil, node.breadcrumb.joined(separator: " › "), node.location].compactMap { $0 }.joined(separator: " · "))
    }
    public func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !refreshing else { return }
        model.outlineState.select(selectedNode?.id, category: model.category, query: model.query)
        model.selectedPath = selectedNode?.asset?.selectionKey; updateInspector()
    }
    public func outlineViewItemDidExpand(_ notification: Notification) { recordExpansion(notification, expanded: true) }
    public func outlineViewItemDidCollapse(_ notification: Notification) { recordExpansion(notification, expanded: false) }
    private func recordExpansion(_ notification: Notification, expanded: Bool) {
        guard !refreshing, let node = notification.userInfo?["NSObject"] as? CatalogOutlineNode else { return }
        model.outlineState.setExpanded(expanded, node: node, category: model.category, query: model.query)
    }
    public func controlTextDidChange(_ notification: Notification) { model.query = search.stringValue; refresh() }
    @objc public func scan() { model.scan() }
    @objc public func focusSearch(_ sender: Any?) { window?.makeFirstResponder(search) }
    @objc public func changeCategory(_ sender: NSButton) {
        model.category = [AssetKind.plugin, .sample, .library][sender.tag]; model.selectedPath = nil
        if model.category != .sample { model.sort = .name }; refresh()
    }
    @objc private func changeSort() { model.sort = CatalogSort.allCases[sortMenu.indexOfSelectedItem]; refresh() }
    @objc private func emptyAction() { if !model.query.isEmpty { search.stringValue = ""; model.query = ""; refresh() } else { showSetup() } }
    @objc private func reveal() { guard let path = selectedNode?.location else { return }; NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    @objc public func showSetup() {
        guard !model.isBusy, window?.attachedSheet == nil else { return }
        setup = SetupWindow(model: model)
        guard let window, let panel = setup?.window else { return }; window.beginSheet(panel)
    }
    @objc public func showFormats() {
        guard !model.isBusy, let product = model.selectedPlugin, let window, window.attachedSheet == nil else { return }
        formatsWindow = PluginFormatsWindow(product: product, model: model)
        window.beginSheet(formatsWindow!.window!)
    }
    @objc private func showIssues() {
        let text = NSTextView(); text.string = model.coverageDetail
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Scan details & project coverage"; panel.isReleasedWhenClosed = false
        panel.contentView = Self.textScroll(text); panel.center(); panel.makeKeyAndOrderFront(nil); coverageWindow = panel
    }
}
