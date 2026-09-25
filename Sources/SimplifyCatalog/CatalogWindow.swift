import AppKit
import SimplifyCore

@MainActor public final class CatalogWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    public let model: CatalogModel
    public let categoryButtons = [NSButton(title: "Plugins", target: nil, action: nil), NSButton(title: "Samples", target: nil, action: nil), NSButton(title: "Libraries", target: nil, action: nil)]
    public let scanButton = NSButton(title: "Scan", target: nil, action: nil)
    public let search = NSSearchField()
    public let table = NSTableView()
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
    private var rows: [Asset] = []
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
        rows = model.visibleAssets; table.reloadData()
        if let selected = model.selectedPath, let index = rows.firstIndex(where: { $0.selectionKey == selected }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) } else { table.deselectAll(nil) }
        let index = [AssetKind.plugin, .sample, .library].firstIndex(of: model.category) ?? 0
        for (i, button) in categoryButtons.enumerated() {
            button.state = i == index ? .on : .off
            button.layer?.backgroundColor = (i == index ? CatalogTheme.accent.withAlphaComponent(0.14) : NSColor.clear).cgColor
        }
        let title = ["Plugins", "Samples", "Libraries"][index]; titleLabel.stringValue = title; search.placeholderString = "Search \(title.lowercased())"
        countLabel.stringValue = model.report == nil ? ["Your audio tools, together.", "Small sounds. Endless possibilities.", "A home for your instruments."][index] : "\(rows.count.formatted()) \(index == 0 ? (rows.count == 1 ? "plugin" : "plugins") : rows.count == 1 ? "item" : "items")\(model.query.isEmpty ? "" : " matching your search")"
        if !model.isScanning, model.report?.issues.contains(where: { $0.reason.contains("Entry limit") }) == true { countLabel.stringValue += " · partial scan" }
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("reference"))?.isHidden = model.category == .library
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("reference"))?.title = model.category == .plugin ? "Last used" : "Project recency"
        for id in ["format", "size"] { table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id))?.isHidden = model.category == .plugin }
        sortMenu.item(at: 1)?.isEnabled = model.category != .plugin
        sortMenu.item(at: 2)?.isEnabled = model.category == .sample
        sortMenu.selectItem(withTitle: model.sort.rawValue)
        scanButton.isEnabled = !model.isBusy; folderButton.isEnabled = !model.isBusy
        issuesButton.isEnabled = model.report != nil
        if model.isScanning { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        refreshProgress()
        statusLabel.stringValue = model.isRemoving ? "Moving selected installations to Trash…" : model.setupNotice ?? (model.isScanning ? (model.isBackgroundScanning ? "Updating in background · browse as results arrive" : "Finding your collection…") : model.configurationChanged ? "Locations changed. Scan to update." : model.report == nil ? "Ready when you are." : "\(model.report!.projects.count) projects · \(model.report!.issues.count) scan issue\(model.report!.issues.count == 1 ? "" : "s")")
        statusLabel.toolTip = model.status
        emptyContainer.isHidden = !rows.isEmpty; collectionScroll.isHidden = rows.isEmpty
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
        formatsButton.isHidden = model.selectedPlugin == nil
        formatsButton.isEnabled = !model.isBusy
        inspectorTitle.toolTip = model.selectedAsset?.name
        detail.textStorage?.setAttributedString(NSAttributedString(string: "", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
        detail.typingAttributes = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        guard let asset = model.selectedAsset else {
            inspectorTitle.stringValue = "A closer look"; inspectorMeta.stringValue = "Select an item to see its location and project references."; detail.string = "Choose an item to see its formats, locations, and available project evidence."; revealButton.isEnabled = false; return
        }
        inspectorTitle.stringValue = asset.name
        inspectorMeta.stringValue = "\(asset.format.isEmpty ? "Folder" : asset.format.uppercased())  ·  \(asset.logicalBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "Size not measured")"
        if let product = model.selectedPlugin {
            inspectorMeta.stringValue = "\(product.installations.count) installation(s) · \(product.formats)"
            detail.string = "INSTALLED FORMATS\n\n" + product.installations.map { PluginProduct.formatName($0.format) + "\n" + $0.path }.joined(separator: "\n\n") + "\n\nPROJECT REFERENCES\n\n" + model.pluginReferenceDetail(product)
            revealButton.isEnabled = true
            return
        }
        if let metadata = asset.libraryMetadata {
            inspectorMeta.stringValue = metadata.player + " · " + metadata.maker
            let instruments = metadata.instruments.filter { model.query.isEmpty || ($0.name + " " + $0.tags.joined(separator: " ")).localizedCaseInsensitiveContains(model.query) }
            detail.string = [metadata.summary, "TAGS", metadata.tags.joined(separator: ", "), "INSTRUMENTS", instruments.prefix(100).map { $0.name }.joined(separator: "\n"), instruments.count > 100 ? "Showing 100 of \(instruments.count) instruments. Narrow your search." : "", "IDENTIFICATION", metadata.source, "Usage history: unknown. Instrument discovery does not establish project inclusion.", "LOCATION", asset.path].filter { !$0.isEmpty }.joined(separator: "\n\n")
            revealButton.isEnabled = true; return
        }
        let reference = model.detail.components(separatedBy: "\n\n").dropFirst(3).joined(separator: "\n\n")
        detail.string = "LOCATION\n\n\(asset.path)\n\nPROJECT REFERENCES\n\n\(reference)"
        let string = NSMutableAttributedString(string: detail.string, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
        for title in ["LOCATION", "PROJECT REFERENCES"] {
            string.addAttributes([.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.labelColor], range: (string.string as NSString).range(of: title))
        }
        detail.textStorage?.setAttributedString(string); revealButton.isEnabled = true
    }
    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    public func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }; let asset = rows[row]
        let value: String
        switch column?.identifier.rawValue {
        case "format": value = model.product(for: asset)?.formats ?? (asset.format.isEmpty ? "Folder" : asset.format.uppercased())
        case "size": value = asset.logicalBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "—"
        case "reference": value = model.referenceText(asset)
        default: value = model.product(for: asset)?.name ?? asset.name
        }
        return CatalogCell(value: value, primary: column?.identifier.rawValue == "name")
    }
    public func tableViewSelectionDidChange(_ notification: Notification) { guard !refreshing else { return }; model.selectedPath = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].selectionKey : nil; updateInspector() }
    public func controlTextDidChange(_ notification: Notification) { model.query = search.stringValue; refresh() }
    @objc public func scan() { model.scan() }
    @objc public func focusSearch(_ sender: Any?) { window?.makeFirstResponder(search) }
    @objc public func changeCategory(_ sender: NSButton) {
        model.category = [AssetKind.plugin, .sample, .library][sender.tag]; model.selectedPath = nil
        if model.category != .sample && model.sort == .recency { model.sort = .name }; refresh()
    }
    @objc private func changeSort() { model.sort = CatalogSort.allCases[sortMenu.indexOfSelectedItem]; refresh() }
    @objc private func emptyAction() { if !model.query.isEmpty { search.stringValue = ""; model.query = ""; refresh() } else { showSetup() } }
    @objc private func reveal() { guard let asset = model.selectedAsset else { return }; NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: asset.path)]) }
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
