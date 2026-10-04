import AppKit

/// A discardable locations draft. Scan is the only action that accepts it.
@MainActor public final class SetupWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    public let draft: CatalogModel
    public let scanButton = NSButton(title: "Scan", target: nil, action: nil)
    public let skipButton = NSButton(title: "Cancel", target: nil, action: nil)
    public let sessionButton = NSButton(title: "Scan without saving", target: nil, action: nil)
    public let onlineTagsButton = NSButton(checkboxWithTitle: "Fetch product tags online", target: nil, action: nil)
    public let retryTagsButton = NSButton(title: "Retry", target: nil, action: nil)
    public let folders = NSTableView()
    public let addButton = NSPopUpButton(frame: .zero, pullsDown: true)
    public let removeButton = NSButton(title: "−", target: nil, action: nil)
    public let appearancePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let settings: Bool
    private let preview: (CatalogAppearance) -> Void
    private let model: CatalogModel
    private let errorLabel = label("", size: 11, secondary: true)
    private var rows: [(RootKind, URL)] = []

    public init(model: CatalogModel, settings: Bool = false, preview: ((CatalogAppearance) -> Void)? = nil) {
        self.model = model; self.settings = settings; self.preview = preview ?? { $0.apply() }; draft = model.setupDraft()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: settings ? 410 : 350), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = settings ? "Settings" : "Collection locations"; panel.isReleasedWhenClosed = false
        super.init(window: panel)
        scanButton.title = settings ? "Save" : "Scan"
        scanButton.target = self; scanButton.action = #selector(scan); scanButton.bezelStyle = .rounded; scanButton.bezelColor = CatalogTheme.accent; scanButton.keyEquivalent = "\r"
        skipButton.target = self; skipButton.action = #selector(skip); skipButton.bezelStyle = .rounded; skipButton.keyEquivalent = "\u{1b}"
        sessionButton.target = self; sessionButton.action = #selector(finishSession); sessionButton.bezelStyle = .rounded; sessionButton.controlSize = .small; sessionButton.isHidden = true; sessionButton.title = settings ? "Use for this session" : "Scan without saving"
        onlineTagsButton.state = model.onlineTags ? .on : .off
        onlineTagsButton.toolTip = "Uses reviewed official product pages. Local paths and projects stay on this Mac. Your edits take priority."
        retryTagsButton.target = self; retryTagsButton.action = #selector(retryTags); retryTagsButton.bezelStyle = .rounded; retryTagsButton.controlSize = .small
        retryTagsButton.isEnabled = model.onlineTags && !model.isFetchingTags
        retryTagsButton.toolTip = model.tagFetchStatus
        let type = NSTableColumn(identifier: .init("type")); type.title = "Type"; type.width = 100; type.minWidth = 100; type.maxWidth = 100
        let folder = NSTableColumn(identifier: .init("folder")); folder.title = "Folder"; folder.width = 390
        folders.addTableColumn(type); folders.addTableColumn(folder)
        folders.dataSource = self; folders.delegate = self; folders.rowHeight = 28
        folders.usesAlternatingRowBackgroundColors = true; folders.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        folders.setAccessibilityLabel("Collection folders")
        let scroll = NSScrollView(); scroll.documentView = folders; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 154).isActive = true
        addButton.addItem(withTitle: "Add folders…")
        for kind in [RootKind.samples, .libraries, .projects, .plugins] {
            let title = kind == .plugins ? "Custom plugins…" : kind == .projects ? "Projects (optional)…" : "\(kind.rawValue)…"
            let item = NSMenuItem(title: title, action: #selector(chooseFolders(_:)), keyEquivalent: "")
            item.target = self; item.tag = RootKind.allCases.firstIndex(of: kind)!
            addButton.menu?.addItem(item)
        }
        addButton.bezelStyle = .rounded; addButton.setAccessibilityLabel("Add collection folders")
        removeButton.bezelStyle = .rounded; removeButton.target = self; removeButton.action = #selector(removeRoot)
        removeButton.setAccessibilityLabel("Remove selected folder from setup")
        let controls = NSStackView(views: [addButton, removeButton, NSView()]); controls.spacing = 4
        let footer = NSStackView(views: [sessionButton, NSView(), skipButton, scanButton]); footer.spacing = 8
        appearancePicker.addItems(withTitles: CatalogAppearance.allCases.map(\.title))
        appearancePicker.selectItem(at: CatalogAppearance.allCases.firstIndex(of: draft.appearance)!)
        appearancePicker.target = self; appearancePicker.action = #selector(changeAppearance)
        appearancePicker.setAccessibilityLabel("Appearance")
        let appearanceRow = NSStackView(views: [label("Appearance", size: 13), NSView(), appearancePicker])
        let separator = NSBox(); separator.boxType = .separator
        let views: [NSView] = (settings ? [label("Settings", size: 15, weight: .semibold), appearanceRow, NSStackView(views: [onlineTagsButton, NSView(), retryTagsButton]), separator] : [])
            + [label("Collection locations", size: settings ? 13 : 15, weight: .semibold), scroll, controls, errorLabel, footer]
        let stack = column(views, spacing: 10)
        if settings {
            appearanceRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        pin(stack, in: panel.contentView!, inset: 20)
        for view in [scroll, controls, errorLabel, footer] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        errorLabel.isHidden = true
        reloadFolders(); window?.makeFirstResponder(scanButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    /// Refresh the transient list after changing the draft.
    public func reloadFolders() {
        rows = RootKind.allCases.flatMap { kind in (draft.roots[kind] ?? []).map { (kind, $0) } }
        folders.reloadData(); removeButton.isEnabled = folders.selectedRow >= 0
    }
    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let (kind, url) = rows[row]
        let text = NSTextField(labelWithString: tableColumn?.identifier.rawValue == "type" ? kind.rawValue : url.path)
        text.font = .systemFont(ofSize: 12); text.lineBreakMode = .byTruncatingMiddle
        text.toolTip = url.path; text.setAccessibilityLabel(tableColumn?.identifier.rawValue == "type" ? kind.rawValue : url.path)
        let cell = NSTableCellView(); cell.addSubview(text); text.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6), text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }
    public func tableViewSelectionDidChange(_ notification: Notification) { removeButton.isEnabled = folders.selectedRow >= 0 }
    @objc private func chooseFolders(_ sender: NSMenuItem) {
        guard let window else { return }; let kind = RootKind.allCases[sender.tag]
        let picker = NSOpenPanel(); picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.allowsMultipleSelection = true
        picker.prompt = "Add"; picker.message = "Choose \(kind.rawValue.lowercased()) folders."
        picker.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK else { return }
            self.draft.addRoots(picker.urls, kind: kind); self.reloadFolders()
            if let url = picker.urls.first, let index = self.rows.firstIndex(where: { $0.0 == kind && $0.1 == url }) {
                self.folders.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false); self.folders.scrollRowToVisible(index)
            }
            self.window?.makeFirstResponder(self.folders)
        }
    }
    @objc private func removeRoot() {
        let index = folders.selectedRow; guard rows.indices.contains(index) else { return }
        let (kind, url) = rows[index]; draft.removeRoot(url, kind: kind); reloadFolders()
        if !rows.isEmpty { folders.selectRowIndexes(IndexSet(integer: min(index, rows.count - 1)), byExtendingSelection: false) }
        window?.makeFirstResponder(rows.isEmpty ? addButton : folders)
    }
    public func refreshTagStatus() {
        retryTagsButton.isEnabled = model.onlineTags && !model.isFetchingTags
        retryTagsButton.toolTip = model.tagFetchStatus
        retryTagsButton.title = model.isFetchingTags ? "Fetching…" : "Retry"
    }
    @objc private func retryTags() { model.refreshProductTags(force: true); refreshTagStatus() }
    @objc public func scan() { finish(remember: true) }
    @objc private func changeAppearance() {
        guard CatalogAppearance.allCases.indices.contains(appearancePicker.indexOfSelectedItem) else { return }
        draft.appearance = CatalogAppearance.allCases[appearancePicker.indexOfSelectedItem]
        preview(draft.appearance)
    }
    @objc public func skip() { preview(model.appearance); closeSheet() }
    @objc private func finishSession() { finish(remember: false) }
    private func finish(remember: Bool) {
        do { try model.acceptSetup(draft, remember: remember, onlineTags: settings ? onlineTagsButton.state == .on : nil); preview(model.appearance); closeSheet(); if !settings { model.scan() } }
        catch { errorLabel.isHidden = false; errorLabel.stringValue = settings ? "Couldn’t save. Try again or use for this session." : "Couldn’t save. Try again or scan without saving."; errorLabel.toolTip = error.localizedDescription; sessionButton.isHidden = false }
    }
    private func closeSheet() { guard let window else { return }; window.sheetParent?.endSheet(window) }
}
