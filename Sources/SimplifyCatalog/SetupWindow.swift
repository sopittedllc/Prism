import AppKit
@preconcurrency import ApplicationServices
import SimplifyCore

/// A discardable locations draft. Scan is the only action that accepts it.
@MainActor public final class SetupWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    public enum Step: Int { case libraries, sounds, projects, review }
    public let draft: CatalogModel
    public let scanButton = NSButton(title: "Scan", target: nil, action: nil)
    public let skipButton = NSButton(title: "Cancel", target: nil, action: nil)
    public let sessionButton = NSButton(title: "Scan without saving", target: nil, action: nil)
    public let accessibilityButton = NSButton(title: "Request Accessibility Access", target: nil, action: nil)
    public let accessibilityStatus = NSTextField(labelWithString: "")
    public let cubaseInstructionsButton = NSButton(title: "Cubase logging instructions…", target: nil, action: nil)
    public let cubaseStatus = NSTextField(labelWithString: "Cubase: enable Usage Logging in Cubase preferences to record new plugin attempts.")
    public let folders = NSTableView()
    public let addButton = NSPopUpButton(frame: .zero, pullsDown: true)
    public let removeButton = NSButton(title: "−", target: nil, action: nil)
    public let backButton = NSButton(title: "Back", target: nil, action: nil)
    public let appearancePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let settings: Bool
    private let preview: (CatalogAppearance) -> Void
    private let model: CatalogModel
    private let errorLabel = label("", size: 11, secondary: true)
    public let stepTitle = label("", size: 16, weight: .semibold)
    public let stepDetail = label("", size: 12, secondary: true)
    public let standardPluginsNote = label("", size: 11, secondary: true)
    public private(set) var step: Step = .libraries
    private var rows: [(RootKind, URL)] = []

    public init(model: CatalogModel, settings: Bool = false, preview: ((CatalogAppearance) -> Void)? = nil) {
        self.model = model; self.settings = settings; self.preview = preview ?? { $0.apply() }; draft = model.setupDraft()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: settings ? 500 : 440), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = settings ? "Settings" : "Set up collection"; panel.isReleasedWhenClosed = false
        super.init(window: panel)
        scanButton.title = settings ? "Save" : "Continue"
        scanButton.target = self; scanButton.action = #selector(scan); scanButton.bezelStyle = .rounded; scanButton.bezelColor = CatalogTheme.accent; scanButton.keyEquivalent = "\r"
        skipButton.target = self; skipButton.action = #selector(skip); skipButton.bezelStyle = .rounded; skipButton.keyEquivalent = "\u{1b}"
        backButton.target = self; backButton.action = #selector(back); backButton.bezelStyle = .rounded
        backButton.setAccessibilityLabel("Back to previous setup step")
        sessionButton.target = self; sessionButton.action = #selector(finishSession); sessionButton.bezelStyle = .rounded; sessionButton.controlSize = .small; sessionButton.isHidden = true; sessionButton.title = settings ? "Use for this session" : "Scan without saving"
        accessibilityButton.target = self; accessibilityButton.action = #selector(requestAccessibility)
        accessibilityButton.bezelStyle = .rounded; accessibilityButton.controlSize = .small
        accessibilityButton.setAccessibilityLabel("Request Accessibility access for Logic mixer observations")
        accessibilityStatus.font = .systemFont(ofSize: 11)
        accessibilityStatus.textColor = .secondaryLabelColor
        accessibilityStatus.maximumNumberOfLines = 3
        accessibilityStatus.lineBreakMode = .byWordWrapping
        accessibilityStatus.setAccessibilityLabel("Logic Accessibility status")
        cubaseInstructionsButton.target = self; cubaseInstructionsButton.action = #selector(openCubaseInstructions)
        cubaseInstructionsButton.bezelStyle = .rounded; cubaseInstructionsButton.controlSize = .small
        cubaseInstructionsButton.toolTip = "Cubase Usage Logging is opt-in inside Cubase. Prism cannot enable it for you."
        cubaseStatus.font = .systemFont(ofSize: 11); cubaseStatus.textColor = .secondaryLabelColor
        cubaseStatus.maximumNumberOfLines = 2; cubaseStatus.lineBreakMode = .byWordWrapping
        let type = NSTableColumn(identifier: .init("type")); type.title = "Type"; type.width = 100; type.minWidth = 100; type.maxWidth = 100
        let folder = NSTableColumn(identifier: .init("folder")); folder.title = "Folder"; folder.width = 390
        folders.addTableColumn(type); folders.addTableColumn(folder)
        folders.dataSource = self; folders.delegate = self; folders.rowHeight = 28
        folders.usesAlternatingRowBackgroundColors = true; folders.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        folders.setAccessibilityLabel("Collection folders")
        let scroll = NSScrollView(); scroll.documentView = folders; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 154).isActive = true
        addButton.addItem(withTitle: "Add folders…")
        for kind in [RootKind.libraries, .samples, .projects] {
            let title = kind == .projects ? "Projects (optional)…" : "\(kind.rawValue)…"
            let item = NSMenuItem(title: title, action: #selector(chooseFolders(_:)), keyEquivalent: "")
            item.target = self; item.tag = RootKind.allCases.firstIndex(of: kind)!
            addButton.menu?.addItem(item)
        }
        addButton.bezelStyle = .rounded; addButton.setAccessibilityLabel("Add collection folders")
        removeButton.bezelStyle = .rounded; removeButton.target = self; removeButton.action = #selector(removeRoot)
        removeButton.setAccessibilityLabel("Remove selected folder from setup")
        let controls = NSStackView(views: [addButton, removeButton, NSView()]); controls.spacing = 4
        let footer = NSStackView(views: [sessionButton, NSView(), backButton, skipButton, scanButton]); footer.spacing = 8
        appearancePicker.addItems(withTitles: CatalogAppearance.allCases.map(\.title))
        appearancePicker.selectItem(at: CatalogAppearance.allCases.firstIndex(of: draft.appearance)!)
        appearancePicker.target = self; appearancePicker.action = #selector(changeAppearance)
        appearancePicker.setAccessibilityLabel("Appearance")
        let appearanceRow = NSStackView(views: [label("Appearance", size: 13), NSView(), appearancePicker])
        let separator = NSBox(); separator.boxType = .separator
        stepDetail.maximumNumberOfLines = 3; stepDetail.lineBreakMode = .byWordWrapping
        standardPluginsNote.maximumNumberOfLines = 2; standardPluginsNote.lineBreakMode = .byWordWrapping
        let views: [NSView] = (settings ? [label("Settings", size: 15, weight: .semibold), appearanceRow, NSStackView(views: [accessibilityButton, NSView()]), accessibilityStatus,
            cubaseStatus, NSStackView(views: [cubaseInstructionsButton, NSView()]), separator] : [])
            + [stepTitle, stepDetail, scroll, controls, standardPluginsNote, errorLabel, footer]
        let stack = column(views, spacing: 10)
        if settings {
            appearanceRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            accessibilityStatus.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            cubaseStatus.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        pin(stack, in: panel.contentView!, inset: 20)
        for view in [stepTitle, stepDetail, scroll, controls, standardPluginsNote, errorLabel, footer] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        errorLabel.isHidden = true
        if settings {
            refreshAccessibilityStatus()
            NotificationCenter.default.addObserver(self, selector: #selector(refreshAccessibilityStatus), name: NSApplication.didBecomeActiveNotification, object: nil)
        }
        refreshStep(); window?.makeFirstResponder(scanButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    @objc public func refreshAccessibilityStatus() {
        let granted = AXIsProcessTrusted()
        accessibilityButton.isEnabled = !granted
        accessibilityStatus.stringValue = granted
            ? "Logic mixer access granted. Prism checks visible plugin names periodically; brief loads may be missed."
            : "Logic mixer access not granted. Prism checks visible plugin names only after access is granted; this does not track Kontakt or SINE instruments."
        accessibilityStatus.setAccessibilityValue(accessibilityStatus.stringValue)
    }
    @objc private func requestAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        refreshAccessibilityStatus()
    }
    @objc private func openCubaseInstructions() {
        guard let url = URL(string: "https://helpcenter.steinberg.de/hc/en-us/articles/32371744743826-Usage-Logging") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Refresh the transient list after changing the draft.
    public func reloadFolders() {
        let kinds: [RootKind] = settings || step == .review ? RootKind.allCases
            : step == .libraries ? [.libraries] : step == .sounds ? [.samples] : [.projects]
        rows = kinds.flatMap { kind in (draft.roots[kind] ?? []).map { (kind, $0) } }
        folders.reloadData(); removeButton.isEnabled = folders.selectedRow >= 0
    }
    private func refreshStep() {
        if settings {
            stepTitle.stringValue = "Collection locations"
            stepDetail.stringValue = "Edit collection folders and appearance. Standard plugins are found automatically; existing plugin locations remain listed for removal."
        } else {
            switch step {
            case .libraries:
                stepTitle.stringValue = "1 of 4 · Sample Libraries"
                stepDetail.stringValue = "Add folders containing installed instruments and sample libraries. Add as many locations as you use."
            case .sounds:
                stepTitle.stringValue = "2 of 4 · Individual Sounds"
                stepDetail.stringValue = "Optional: choose folders of loops, one-shots, and downloaded sample packs."
            case .projects:
                stepTitle.stringValue = "3 of 4 · Projects"
                stepDetail.stringValue = "Optional: choose saved DAW projects to find which plugins, libraries, and sounds they reference. Last Used reflects supported saved references; incomplete projects leave usage unknown."
            case .review:
                stepTitle.stringValue = "4 of 4 · Review & Scan"
                var kinds = [("library", RootKind.libraries), ("sound", .samples), ("project", .projects)]
                if !(draft.roots[.plugins] ?? []).isEmpty { kinds.append(("existing plugin", .plugins)) }
                let counts = kinds
                    .map { name, kind in
                        let count = draft.roots[kind, default: []].count
                        return "\(count) \(name) \(count == 1 ? "folder" : "folders")"
                    }.joined(separator: " · ")
                stepDetail.stringValue = "\(counts). Scan checks all listed locations. It reads files without editing, uploading, or sharing their contents; your catalog stays on this Mac."
            }
        }
        let showControls = settings || step != .review
        addButton.isHidden = !showControls; removeButton.isHidden = !showControls
        let addTitle = settings ? "Add collection folders…" : step == .libraries ? "Add sample library folders…" : step == .sounds ? "Add individual sound folders…" : "Add project folders…"
        addButton.item(at: 0)?.title = addTitle
        addButton.setAccessibilityLabel(addTitle)
        for item in addButton.menu?.items ?? [] where item.tag >= 0 && item.tag < RootKind.allCases.count {
            let kind = RootKind.allCases[item.tag]
            item.isHidden = !settings && (step == .review || (step == .libraries ? kind != .libraries : step == .sounds ? kind != .samples : kind != .projects))
        }
        standardPluginsNote.isHidden = settings
        standardPluginsNote.stringValue = step == .projects
            ? "Scanning reads project files without editing, uploading, or sharing their contents. Your catalog stays on this Mac."
            : draft.standardPlugins
                ? "Standard system plugins are included automatically."
                : "Standard system plugins are turned off for this collection."
        backButton.isHidden = settings || step == .libraries
        scanButton.title = settings ? "Save" : step == .libraries ? "Continue" : step == .sounds && (draft.roots[.samples] ?? []).isEmpty ? "Continue without sounds" : step == .sounds ? "Continue" : step == .projects && (draft.roots[.projects] ?? []).isEmpty ? "Continue without projects" : step == .projects ? "Review" : "Scan collection"
        scanButton.setAccessibilityLabel(scanButton.title)
        reloadFolders()
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
            self.draft.addRoots(picker.urls, kind: kind); self.refreshStep()
            if let url = picker.urls.first, let index = self.rows.firstIndex(where: { $0.0 == kind && $0.1 == url }) {
                self.folders.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false); self.folders.scrollRowToVisible(index)
            }
            self.window?.makeFirstResponder(self.folders)
        }
    }
    @objc private func removeRoot() {
        let index = folders.selectedRow; guard rows.indices.contains(index) else { return }
        let (kind, url) = rows[index]; draft.removeRoot(url, kind: kind); refreshStep()
        if !rows.isEmpty { folders.selectRowIndexes(IndexSet(integer: min(index, rows.count - 1)), byExtendingSelection: false) }
        window?.makeFirstResponder(rows.isEmpty ? addButton : folders)
    }
    @objc public func scan() {
        if !settings && step != .review {
            step = step == .libraries ? .sounds : step == .sounds ? .projects : .review
            refreshStep(); window?.makeFirstResponder(scanButton)
            return
        }
        finish(remember: true)
    }
    @objc public func back() {
        guard !settings, step != .libraries else { return }
        step = step == .review ? .projects : step == .projects ? .sounds : .libraries
        refreshStep(); window?.makeFirstResponder(scanButton)
    }
    @objc private func changeAppearance() {
        guard CatalogAppearance.allCases.indices.contains(appearancePicker.indexOfSelectedItem) else { return }
        draft.appearance = CatalogAppearance.allCases[appearancePicker.indexOfSelectedItem]
        preview(draft.appearance)
    }
    @objc public func skip() { preview(model.appearance); closeSheet() }
    @objc private func finishSession() { guard settings || step == .review else { return }; finish(remember: false) }
    private func finish(remember: Bool) {
        do { try model.acceptSetup(draft, remember: remember, completeOnboarding: !settings); preview(model.appearance); closeSheet(); if !settings { model.scan() } }
        catch { errorLabel.isHidden = false; errorLabel.stringValue = settings ? "Couldn’t save. Try again or use for this session." : "Couldn’t save. Try again or scan without saving."; errorLabel.toolTip = error.localizedDescription; sessionButton.isHidden = false }
    }
    private func closeSheet() { guard let window else { return }; window.sheetParent?.endSheet(window) }
}
