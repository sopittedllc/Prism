import AppKit
import SimplifyCore

@MainActor public final class CatalogWindow: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate, NSWindowDelegate, NSPopoverDelegate {
    public let model: CatalogModel
    public let categoryButtons = [NSButton(title: "Plugins", target: nil, action: nil), NSButton(title: "Individual Samples", target: nil, action: nil), NSButton(title: "Libraries", target: nil, action: nil)]
    public let scanButton = NSButton(title: "Scan", target: nil, action: nil)
    public let search = NSSearchField()
    public let undoMetadataButton = NSButton(title: "Undo tag edit", target: nil, action: nil)
    public private(set) var metadataEditor: MetadataEditor?
    public let table = NSOutlineView()
    public let tagPills = TagPillList(frame: .zero)
    public private(set) var tagEntry: TagEntryController?
    public let tagPopover = NSPopover()
    private let tagScroll = NSScrollView()
    private var tagHeight: NSLayoutConstraint?
    private let tagError = label("", size: 11, secondary: true)
    private var tagErrorNode: String?

    public private(set) var setup: SetupWindow?
    public private(set) var formatsWindow: PluginFormatsWindow?
    public let formatsButton = NSButton(title: "Manage formats…", target: nil, action: nil)
    private let titleLabel = label("Plugins", size: 26, weight: .bold)
    private let countLabel = label("Your audio tools, together.", secondary: true)
    private let statusLabel = label("", size: 11, secondary: true)
    public let folderButton = NSButton(title: "Settings…", target: nil, action: nil)
    private let issuesButton = NSButton(title: "Scan details", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    public let scanProgressBar = ScanProgressTrack(frame: .zero)
    private let discoveryProgressBar = NSProgressIndicator()
    public let scanProgressLabel = label("", size: 12, weight: .semibold)
    private let scanProgressDetail = label("", size: 11, secondary: true)
    private let scanBanner = NSView()
    private var progressTimer: Timer?
    private let emptyTitle = label("Meet your collection.", size: 22, weight: .semibold)
    private let emptyBody = label("Set up your sound folders, then bring everything into view.", secondary: true)
    private let emptyButton = NSButton(title: "Set up Prism", target: nil, action: nil)
    private let emptyContainer = NSView()
    private let inspectorTitle = label("A closer look", size: 17, weight: .semibold)
    private let inspectorMeta = label("Select an item to explore its details.", size: 12, secondary: true)
    public let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)
    private let lastUsedSummary = label("Unknown", size: 12)
    private let addedSummary = label("Unknown", size: 12)
    private let sizeSummary = label("Unknown", size: 12)
    private let collectionScroll = NSScrollView()
    private var outline = CatalogOutline(roots: [])
    private var presentationContext = ""
    public var selectedNode: CatalogOutlineNode? { table.item(atRow: table.selectedRow) as? CatalogOutlineNode }
    private var coverageWindow: NSWindow?
    private var refreshing = false
    private var appliedAppearance: CatalogAppearance?
    public var inspectorSummaryText: String {
        "Last used   \(lastUsedSummary.stringValue)\nDate added   \(addedSummary.stringValue)\nSize   \(sizeSummary.stringValue)"
    }

    public init(model: CatalogModel = CatalogModel()) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1220, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Prism"; window.minSize = NSSize(width: 1040, height: 680)
        window.contentView = CatalogBackground(frame: .zero); window.isReleasedWhenClosed = false
        super.init(window: window)
        model.appearance.apply(); appliedAppearance = model.appearance
        window.delegate = self
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
        inspector.widthAnchor.constraint(equalToConstant: 240).isActive = true
        main.widthAnchor.constraint(greaterThanOrEqualToConstant: 550).isActive = true
        let brand = NSStackView(views: [Brand.mark(size: 38), label("Prism", size: 20, weight: .bold)]); brand.spacing = 10
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
        folderButton.target = self; folderButton.action = #selector(showSettings); folderButton.bezelStyle = .rounded
        folderButton.font = .systemFont(ofSize: 11)
        let sidebarBottom = column([folderButton], spacing: 16)
        sidebarBottom.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(sidebarBottom)
        NSLayoutConstraint.activate([sidebarBottom.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16), sidebarBottom.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12), sidebarBottom.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -24)])
        scanButton.target = self; scanButton.action = #selector(scan); scanButton.bezelStyle = .rounded
        scanButton.bezelColor = CatalogTheme.accent; scanButton.keyEquivalent = "r"; scanButton.keyEquivalentModifierMask = .command
        scanButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil); scanButton.imagePosition = .imageLeading
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        let heading = NSStackView(views: [column([titleLabel, countLabel], spacing: 4), NSView(), progress, scanButton]); heading.spacing = 12
        search.placeholderString = "Search plugins"; search.delegate = self; search.sendsSearchStringImmediately = true; search.setAccessibilityLabel("Search collection")
        search.placeholderString = "Search names and tags"
        search.searchMenuTemplate = nil
        let filters = column([search], spacing: 0)
        search.widthAnchor.constraint(equalTo: filters.widthAnchor).isActive = true
        for (id, title, width) in [("name", "Name", 165.0), ("tags", "Tags", 105.0), ("size", "Size", 65.0), ("installed", "Date added", 90.0), ("reference", "Last used", 85.0)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); col.title = title; col.width = width; col.minWidth = id == "name" ? 155 : 60; col.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: id == "name" || id == "format" || id == "tags"); table.addTableColumn(col)
        }
        let context = NSMenu()
        let editTags = NSMenuItem(title: "Edit tags…", action: #selector(editClickedTags), keyEquivalent: "")
        editTags.target = self; context.addItem(editTags); table.menu = context
        table.dataSource = self; table.delegate = self; table.rowHeight = 38; table.style = .inset
        table.outlineTableColumn = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("name"))
        table.indentationPerLevel = 16; table.autoresizesOutlineColumn = false
        table.usesAlternatingRowBackgroundColors = false; table.columnAutoresizingStyle = .noColumnAutoresizing
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
        revealButton.target = self; revealButton.action = #selector(reveal); revealButton.bezelStyle = .rounded
        formatsButton.target = self; formatsButton.action = #selector(showFormats); formatsButton.bezelStyle = .rounded
        undoMetadataButton.target = self; undoMetadataButton.action = #selector(undoMetadata); undoMetadataButton.bezelStyle = .rounded
        func summaryRow(_ name: String, _ value: NSTextField) -> NSStackView {
            let title = label(name, size: 12, secondary: true)
            title.widthAnchor.constraint(equalToConstant: 76).isActive = true
            value.maximumNumberOfLines = 2; value.lineBreakMode = .byWordWrapping
            let row = NSStackView(views: [title, value]); row.spacing = 8; row.alignment = .top
            return row
        }
        let summary = column([summaryRow("Last used", lastUsedSummary), summaryRow("Date added", addedSummary), summaryRow("Size", sizeSummary)], spacing: 5)
        tagScroll.documentView = tagPills; tagScroll.hasVerticalScroller = true; tagScroll.autohidesScrollers = true; tagScroll.drawsBackground = false
        tagPills.autoresizingMask = [.width]
        tagHeight = tagScroll.heightAnchor.constraint(equalToConstant: 27); tagHeight?.priority = .defaultHigh; tagHeight?.isActive = true
        tagScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 27).isActive = true
        tagError.isHidden = true
        let inspectorStack = column([label("YOUR SOUND", size: 10, weight: .semibold, secondary: true), inspectorTitle, inspectorMeta, tagScroll, tagError, summary, formatsButton, revealButton, undoMetadataButton, NSView()], spacing: 12)
        pin(inspectorStack, in: inspector, inset: 22)
        for view in [inspectorTitle, inspectorMeta, tagScroll, tagError, summary, revealButton] { view.widthAnchor.constraint(equalTo: inspectorStack.widthAnchor).isActive = true }
    }

    public static func textScroll(_ text: NSTextView) -> NSScrollView {
        text.isEditable = false; text.isSelectable = true; text.isRichText = false
        text.font = .systemFont(ofSize: 12); text.textColor = .labelColor; text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 8, height: 8); text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView(); scroll.documentView = text; scroll.hasVerticalScroller = true; return scroll
    }

    public func refresh() {
        setup?.refreshTagStatus()
        if appliedAppearance != model.appearance {
            model.appearance.apply(); appliedAppearance = model.appearance
        }
        refreshing = true; defer { refreshing = false }
        outline = model.outline; table.reloadData(); table.collapseItem(nil, collapseChildren: true)
        func expand(_ nodes: [CatalogOutlineNode]) {
            for node in nodes where !node.children.isEmpty && model.outlineState.isExpanded(node, category: model.category, query: model.navigationQuery) {
                table.expandItem(node); expand(node.children)
            }
        }
        expand(outline.roots)
        let selectedID = model.outlineState.selectedID(category: model.category, query: model.navigationQuery)
        let selected = selectedID.flatMap { outline.byID[$0] }
        let row = selected.map { table.row(forItem: $0) } ?? -1
        if row >= 0 { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
        model.selectedPath = selectedNode?.asset?.selectionKey
        model.selectedProductID = selectedNode?.asset?.pluginProductID
        let context = model.category.rawValue + ":" + model.navigationQuery
        if context != presentationContext, row >= 0 { table.scrollRowToVisible(row) }
        presentationContext = context
        let index = [AssetKind.plugin, .sample, .library].firstIndex(of: model.category) ?? 0
        for (i, button) in categoryButtons.enumerated() {
            button.state = i == index ? .on : .off
            button.layer?.backgroundColor = (i == index ? CatalogTheme.accent.withAlphaComponent(0.14) : NSColor.clear).cgColor
        }
        let title = ["Plugins", "Individual Samples", "Libraries"][index]; titleLabel.stringValue = title
        search.placeholderString = "Search names and tags"
        search.stringValue = model.query
        let count = outline.nodes.filter { $0.kind == .plugin || $0.kind == .library || $0.kind == .sample }.count
        let instruments = outline.nodes.filter { $0.kind == .instrument }.count
        let flatLibrary = model.category == .library && (model.sort == .tags || model.sort == .installed)
        let shown = flatLibrary ? count + instruments : count
        let noun = model.category == .plugin ? (shown == 1 ? "plugin" : "plugins") : model.category == .sample ? (shown == 1 ? "sample" : "samples") : flatLibrary ? (shown == 1 ? "sound" : "sounds") : (shown == 1 ? "library" : "libraries")
        countLabel.stringValue = model.report == nil ? ["Your audio tools, together.", "Small sounds. Endless possibilities.", "A home for your instruments."][index] : "\(shown.formatted()) \(noun)" + (model.category == .library && !flatLibrary ? " · \(instruments.formatted()) \(instruments == 1 ? "instrument" : "instruments")" : "") + (model.query.isEmpty ? "" : " matching your search")
        if !model.isScanning, model.report?.issues.contains(where: { $0.reason.contains("Entry limit") }) == true { countLabel.stringValue += " · partial scan" }
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("reference"))?.isHidden = false
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("installed"))?.title = model.dateColumnTitle
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("reference"))?.title = model.category == .sample ? "Project recency" : "Last used"
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("size"))?.title = "Size"
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("size"))?.width = model.category == .library ? 135 : 90
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("format"))?.title = model.category == .library ? "Player / format" : "Format"
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("format"))?.width = model.category == .library ? 105 : 75
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("format"))?.isHidden = true
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("size"))?.isHidden = false
        let sortKey: String
        switch model.sort { case .name: sortKey = "name"; case .tags: sortKey = "tags"; case .format: sortKey = "format"; case .size: sortKey = "size"; case .installed: sortKey = "installed"; case .recency, .firstFound: sortKey = "reference" }
        let ascending = (model.sort == .name || model.sort == .format || model.sort == .tags) != model.sortReversed
        let descriptor = NSSortDescriptor(key: sortKey, ascending: ascending)
        if table.sortDescriptors != [descriptor] { table.sortDescriptors = [descriptor] }
        table.setAccessibilityHelp("Sorted by \(model.sort == .installed ? model.dateColumnTitle : model.sort == .recency && model.category != .sample ? "Last used" : model.sort.rawValue), \(ascending ? "ascending" : "descending"). Click a column heading to reverse its order. Unknown dates do not mean unused. Plugin Date added uses the earliest available Finder file-location date, or confirmed original addition when Finder metadata is unavailable; scan and installer dates remain separate. Unknown sizes and dates sort last. Last used for plugins sorts calendar days: Live and Pro Tools use reported DAW local days; Cubase and Logic use this Mac's local display day. Comparable times within one host family break same-day ties.")
        undoMetadataButton.isEnabled = model.canUndoMetadata
        undoMetadataButton.isHidden = !model.canUndoMetadata
        scanButton.toolTip = "Scan " + categoryButtons[index].title.lowercased()
        scanButton.setAccessibilityLabel(scanButton.toolTip)
        scanButton.isEnabled = !model.isBusy; folderButton.isEnabled = !model.isBusy
        issuesButton.isEnabled = model.report != nil
        if model.isScanning { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        refreshProgress()
        statusLabel.stringValue = model.isRemoving ? "Moving selected installations to Trash…" : model.catalogNotice ?? model.setupNotice ?? (model.usingSavedCatalog && !model.isScanning ? "Saved collection · Scan to refresh" : model.isScanning ? (model.isBackgroundScanning ? "Updating in background · browse as results arrive" : "Finding your collection…") : model.configurationChanged ? "Locations changed. Scan to update." : model.report == nil ? "Ready when you are." : "\(model.report!.projects.count) projects · \(model.report!.issues.count) scan issue\(model.report!.issues.count == 1 ? "" : "s")")
        statusLabel.toolTip = model.status
        emptyContainer.isHidden = !outline.roots.isEmpty; collectionScroll.isHidden = outline.roots.isEmpty
        emptyTitle.stringValue = model.isScanning ? (model.isBackgroundScanning ? "Your collection is open." : "Finding your sounds…") : model.report == nil ? "Meet your collection." : model.query.isEmpty ? "No items found." : "No matches."
        emptyBody.stringValue = model.isScanning ? "Items appear as they are found. You can switch collections and search while project references are checked in the background." : model.report == nil ? model.locationSummary : model.query.isEmpty ? model.locationSummary : "Try another name or clear your search to see the collection."
        if model.hasFilters, model.report != nil {
            emptyTitle.stringValue = "No matches."
            emptyBody.stringValue = "Try another name or tag, or clear your search."
        }
        emptyButton.title = model.hasFilters ? "Clear search" : "Set up locations…"; emptyButton.isEnabled = !model.isScanning || model.hasFilters
        updateInspector(); formatsWindow?.refreshInstallerRecords()
        window?.contentView?.layoutSubtreeIfNeeded(); fitCollectionColumns()
    }
    public func windowDidResize(_ notification: Notification) {
        // AppKit finishes the content/clip-view resize after the window notification.
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.window?.contentView?.layoutSubtreeIfNeeded(); self?.fitCollectionColumns()
        }
    }
    private func fitCollectionColumns() {
        guard let name = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("name")) else { return }
        let available = collectionScroll.contentSize.width
        guard available > 0 else { return }
        let size = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("size"))
        let reference = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("reference"))
        let compact = available < 600
        name.minWidth = compact ? 140 : model.category == .plugin ? 140 : 155
        // Format remains in the selected-item subtitle and Manage formats sheet.
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("tags"))?.width = compact ? 70 : 105
        size?.width = compact ? (model.category == .library ? 90 : 80) : 105
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("installed"))?.width = compact ? 90 : model.category == .plugin ? 120 : 90
        reference?.width = compact ? (model.category == .sample ? 115 : 80) : model.category == .sample ? 130 : model.category == .plugin ? 90 : 105
        let others = table.tableColumns.filter { $0 !== name && !$0.isHidden }.reduce(CGFloat(0)) { $0 + $1.width }
        name.width = max(name.minWidth, available - others - 24)
        // Inset table style adds spacing outside NSTableColumn.width. Fit the rendered extent.
        if let last = table.tableColumns.lastIndex(where: { !$0.isHidden }) {
            let overflow = table.rect(ofColumn: last).maxX - available
            if overflow > 0 { name.width = max(name.minWidth, name.width - overflow - 1) }
        }
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
        let scope = model.scanningKinds.count == 1 ? (model.scanningKinds.first == .plugin ? "Plugins" : model.scanningKinds.first == .sample ? "Samples" : "Libraries") : "Collection"
        if let fraction = update?.fraction {
            discoveryProgressBar.stopAnimation(nil); discoveryProgressBar.isHidden = true
            scanProgressBar.isHidden = false; scanProgressBar.doubleValue = fraction * 100
            scanProgressLabel.stringValue = "\(scope) · \(title) · \(Int(fraction * 100))%"
        } else {
            scanProgressBar.isHidden = true; discoveryProgressBar.isHidden = false; discoveryProgressBar.startAnimation(nil)
            scanProgressLabel.stringValue = scope + " · " + title
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
        tagScroll.isHidden = node?.asset == nil || node?.isGroup == true
        tagError.isHidden = tagErrorNode != node?.id || tagError.stringValue.isEmpty
        if let node {
            tagPills.update(tags: model.tags(for: node), editable: model.canEditMetadata(node), scope: node.kind == .plugin ? "One tag set for this plugin" : "", onRemove: { [weak self] facet, value in
                self?.removeTag(value, facet: facet, node: node)
            }, onAdd: { [weak self] in self?.showAddTag(node) })
            let height = tagPills.contentHeight(width: 196)
            tagPills.frame = NSRect(x: 0, y: 0, width: 196, height: height)
            tagHeight?.constant = min(96, height)
        }
        tagPills.toolTip = node?.asset.map { model.productTagProvenance($0) }
        formatsButton.isHidden = node?.kind != .plugin || model.selectedPlugin == nil
        formatsButton.isEnabled = !model.isBusy
        revealButton.isHidden = node == nil || node?.kind == .plugin || node?.isGroup == true || node?.location == nil
        revealButton.isEnabled = !model.isBusy
        revealButton.toolTip = node?.location
        inspectorTitle.toolTip = node?.breadcrumb.joined(separator: " › ")
        guard let node else {
            inspectorTitle.stringValue = "A closer look"; inspectorMeta.stringValue = "Select a sound"
            lastUsedSummary.stringValue = "—"; addedSummary.stringValue = "—"; sizeSummary.stringValue = "—"
            return
        }
        inspectorTitle.stringValue = node.displayName
        if node.isGroup {
            inspectorMeta.stringValue = "\(node.children.count.formatted()) items"
            lastUsedSummary.stringValue = "—"; addedSummary.stringValue = "—"; sizeSummary.stringValue = "—"
            return
        }
        guard let asset = node.asset else { return }
        inspectorMeta.stringValue = model.product(for: asset)?.formats
            ?? node.instrument.map { URL(fileURLWithPath: $0.path).pathExtension.uppercased() }
            ?? asset.libraryMetadata?.player ?? asset.format.uppercased()
        let size = node.kind == .instrument ? "Shared with library" : asset.kind == .plugin ? model.pluginSize(asset).value : node.sizeText
        let addition = node.instrument.map(model.instrumentAdditionDate) ?? model.additionDate(asset)
        let usage = model.lastUsed(asset)
        lastUsedSummary.stringValue = usage.value.replacingOccurrences(of: "\n", with: " ")
        addedSummary.stringValue = addition.value.replacingOccurrences(of: "\n", with: " ")
        sizeSummary.stringValue = size
        lastUsedSummary.setAccessibilityLabel(usage.accessibility)
        addedSummary.setAccessibilityLabel(addition.accessibility)
        sizeSummary.setAccessibilityLabel(asset.kind == .plugin ? model.pluginSize(asset).accessibility : "Size, " + size)
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
        case "tags": value = node.isGroup ? "" : model.tagSummary(node)
        case "format":
            value = node.asset.flatMap(model.product)?.formats ?? node.instrument.map { URL(fileURLWithPath: $0.path).pathExtension.uppercased() }
                .flatMap { $0.isEmpty ? nil : $0 } ?? node.asset.map { $0.libraryMetadata?.player ?? $0.format.uppercased() } ?? ""
        case "size": value = node.isGroup ? "" : node.sizeText
        case "installed": value = node.isGroup ? "" : node.instrument.map { model.instrumentAdditionDate($0).value } ?? node.asset.map { model.additionDate($0).value } ?? "Unknown"
        case "reference":
            value = node.isGroup ? "" : node.kind == .instrument ? "Unknown" : node.asset.map { $0.kind == .plugin ? model.lastUsed($0).value : model.referenceText($0) } ?? ""
        default:
            let product = node.asset.flatMap(model.product)
            let stale = product.map { $0.installations.allSatisfy { $0.catalogStale == true } } ?? node.stale
            value = (product?.name ?? node.title) + (stale ? " · Not observed" : "")
        }
        let subtitle: String?
        if column?.identifier.rawValue == "name", node.kind == .plugin {
            subtitle = node.asset.flatMap(model.product)?.formats
        } else if column?.identifier.rawValue == "name", node.metadataOnlyMatch {
            subtitle = "Library metadata match"
        } else if column?.identifier.rawValue == "name", model.hasFilters, node.kind == .sample {
            subtitle = node.breadcrumb.dropLast().joined(separator: " › ")
        } else if column?.identifier.rawValue == "name", !node.isGroup, node.kind != .sample {
            subtitle = model.tagSummary(node)
        } else { subtitle = nil }
        let cell = CatalogCell(value: value, primary: column?.identifier.rawValue == "name", subtitle: subtitle,
                           query: model.query, context: node.breadcrumb.joined(separator: " › "), wrap: ["installed", "reference"].contains(column?.identifier.rawValue ?? ""))
        if column?.identifier.rawValue == "reference", node.kind == .plugin, let asset = node.asset {
            cell.textField?.setAccessibilityLabel(model.lastUsed(asset).accessibility); cell.textField?.setAccessibilityHelp(model.lastUsed(asset).detail)
        }
        if column?.identifier.rawValue == "installed", !node.isGroup {
            let help = node.instrument.map { model.instrumentAdditionDate($0).accessibility } ?? node.asset.map { model.additionDate($0).accessibility } ?? "Date added unknown"
            cell.textField?.setAccessibilityLabel(help); cell.textField?.setAccessibilityHelp(help)
            cell.textField?.toolTip = help
        }
        return cell
    }
    public func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !refreshing else { return }
        model.outlineState.select(selectedNode?.id, category: model.category, query: model.navigationQuery)
        model.selectedPath = selectedNode?.asset?.selectionKey; model.selectedProductID = selectedNode?.asset?.pluginProductID; updateInspector()
    }
    public func outlineViewItemDidExpand(_ notification: Notification) { recordExpansion(notification, expanded: true) }
    public func outlineViewItemDidCollapse(_ notification: Notification) { recordExpansion(notification, expanded: false) }
    private func recordExpansion(_ notification: Notification, expanded: Bool) {
        guard !refreshing, let node = notification.userInfo?["NSObject"] as? CatalogOutlineNode else { return }
        model.outlineState.setExpanded(expanded, node: node, category: model.category, query: model.navigationQuery)
    }
    public func controlTextDidChange(_ notification: Notification) { model.query = search.stringValue; refresh() }
    @objc public func scan() { model.scan(scannedKinds: [model.category]) }
    @objc public func focusSearch(_ sender: Any?) { window?.makeFirstResponder(search) }
    @objc public func changeCategory(_ sender: NSButton) {
        model.category = [AssetKind.plugin, .sample, .library][sender.tag]; model.selectedPath = nil; model.selectedProductID = nil
        if model.sort == .firstFound { model.sort = .name; model.sortReversed = false }
        model.musicalFilter = [:]; model.usageFilter = .all; refresh()
    }
    public func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !refreshing, let descriptor = outlineView.sortDescriptors.first else { return }
        let sort: CatalogSort
        switch descriptor.key { case "tags": sort = .tags; case "format": sort = .format; case "size": sort = .size; case "installed": sort = .installed; case "reference": sort = .recency; default: sort = .name }
        model.sort = sort; model.sortReversed = descriptor.ascending != (sort == .name || sort == .format || sort == .tags)
        refresh()
    }
    @objc private func emptyAction() { if model.hasFilters { clearFilters() } else { showSetup() } }
    public func clearFilters() {
        model.query = ""; search.stringValue = ""; model.musicalFilter = [:]; model.recentOnly = false; model.usageFilter = .all
        refresh(); window?.makeFirstResponder(search)
    }
    public func popoverShouldClose(_ popover: NSPopover) -> Bool { popover !== tagPopover || tagEntry?.isSaving != true }
    public func showAddTag(_ node: CatalogOutlineNode) {
        guard model.canEditMetadata(node) else { return }
        tagEntry = TagEntryController(model: model, node: node) { [weak self] in
            self?.tagPopover.close(); self?.refresh(); self?.window?.makeFirstResponder(self?.tagPills.addButton)
        }
        tagPopover.contentViewController = tagEntry; tagPopover.delegate = self; tagPopover.behavior = .transient
        tagPopover.show(relativeTo: tagPills.addButton.bounds, of: tagPills.addButton, preferredEdge: .minX)
    }
    private func removeTag(_ value: String, facet: MusicalFacet, node: CatalogOutlineNode) {
        guard model.canEditMetadata(node) else { return }
        tagError.stringValue = ""; tagErrorNode = node.id
        Task { @MainActor in
            do {
                try await model.changeTag(value, facet: facet, removing: true, node: node)
                window?.makeFirstResponder(selectedNode == nil ? table : tagPills.addButton)
            } catch {
                tagError.stringValue = "Couldn’t remove tag. Try again."; tagError.toolTip = error.localizedDescription
                tagError.isHidden = selectedNode?.id != node.id
            }
        }
    }
    @objc private func editClickedTags() {
        if table.clickedRow >= 0 { table.selectRowIndexes(IndexSet(integer: table.clickedRow), byExtendingSelection: false) }
        showMetadataEditor()
    }
    @objc public func showMetadataEditor() {
        tagPopover.close()
        guard let node = selectedNode, model.canEditMetadata(node), let window, window.attachedSheet == nil else { return }
        metadataEditor = MetadataEditor(model: model, node: node)
        window.beginSheet(metadataEditor!.window!) { [weak self] _ in
            self?.refresh(); self?.window?.makeFirstResponder(self?.table)
        }
    }
    @objc public func undoMetadata() {
        Task { @MainActor in
            do { try await model.undoMetadata(); refresh() }
            catch { let alert = NSAlert(); alert.messageText = "Couldn’t undo metadata edit"; alert.informativeText = error.localizedDescription; if let window { await alert.beginSheetModal(for: window) } }
        }
    }
    @objc private func reveal() { guard let path = selectedNode?.location else { return }; NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    @objc public func showSettings() { openLocations(settings: true) }
    @objc public func showSetup() { openLocations(settings: false) }
    private func openLocations(settings: Bool) {
        if let panel = setup?.window, window?.attachedSheet === panel { panel.makeKeyAndOrderFront(nil); return }
        guard !model.isBusy, window?.attachedSheet == nil else { return }
        setup = SetupWindow(model: model, settings: settings) { [weak self] appearance in
            self?.window?.appearance = nil
            appearance.apply()
        }
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
