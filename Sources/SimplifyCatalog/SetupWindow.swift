import AppKit

/// A discardable setup draft. Only finishing applies configuration to the browser.
@MainActor public final class SetupWindow: NSWindowController {
    public let draft: CatalogModel
    public private(set) var step = 0
    public let nextButton = NSButton(title: "Let's get started", target: nil, action: nil)
    public let backButton = NSButton(title: "Back", target: nil, action: nil)
    public let skipButton = NSButton(title: "Set up later", target: nil, action: nil)
    public let sessionButton = NSButton(title: "Use for this session & Scan", target: nil, action: nil)
    private let model: CatalogModel
    private let body = NSView()
    private let stepLabel = label("", size: 11, weight: .medium, secondary: true)
    private let errorLabel = label("", size: 11, secondary: true)
    private let standardToggle = NSButton(checkboxWithTitle: "Include standard plugin folders", target: nil, action: nil)
    private var folderActions: [RootKind: NSButton] = [:]
    private var rootButtons: [NSButton: (RootKind, URL)] = [:]

    public init(model: CatalogModel) {
        self.model = model; draft = model.setupDraft()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 602), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Set up Simplify"; panel.isReleasedWhenClosed = false
        panel.contentView?.widthAnchor.constraint(equalToConstant: 740).isActive = true
        super.init(window: panel)
        nextButton.target = self; nextButton.action = #selector(next); nextButton.bezelStyle = .rounded; nextButton.bezelColor = CatalogTheme.accent; nextButton.keyEquivalent = "\r"
        backButton.target = self; backButton.action = #selector(back); backButton.bezelStyle = .rounded
        skipButton.target = self; skipButton.action = #selector(skip); skipButton.bezelStyle = .rounded; skipButton.keyEquivalent = "\u{1b}"
        sessionButton.target = self; sessionButton.action = #selector(finishSession); sessionButton.bezelStyle = .rounded; sessionButton.controlSize = .small
        let header = NSStackView(views: [label("SIMPLIFY / SETUP", size: 10, weight: .semibold, secondary: true), NSView(), stepLabel])
        let footer = NSStackView(views: [skipButton, NSView(), backButton, nextButton]); footer.spacing = 12
        let stack = column([header, body, errorLabel, sessionButton, footer], spacing: 16); pin(stack, in: panel.contentView!, inset: 30)
        for view in [header, body, errorLabel, footer] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        body.heightAnchor.constraint(greaterThanOrEqualToConstant: 365).isActive = true; body.setContentHuggingPriority(.defaultLow, for: .vertical)
        render()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    private func render(focusKind: RootKind? = nil) {
        for view in body.subviews { view.removeFromSuperview() }
        rootButtons = [:]; folderActions = [:]
        let titles = ["Welcome", "Your sounds", "Your projects", "Ready"]
        stepLabel.stringValue = "\(step + 1) of 4  ·  \(titles[step])"
        backButton.isHidden = step == 0; sessionButton.isHidden = step != 3
        nextButton.title = step == 0 ? "Let's get started" : step == 3 ? "Save setup & Scan" : "Continue"
        skipButton.title = model.onboardingCompleted ? "Cancel" : "Set up later"
        errorLabel.stringValue = model.setupNotice ?? ""
        let stack = column([], spacing: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false; body.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: body.leadingAnchor), stack.trailingAnchor.constraint(equalTo: body.trailingAnchor), stack.topAnchor.constraint(equalTo: body.topAnchor), stack.bottomAnchor.constraint(lessThanOrEqualTo: body.bottomAnchor)])
        func text(_ title: String, _ subtitle: String) {
            stack.addArrangedSubview(label(title, size: 28, weight: .bold))
            let sub = label(subtitle, size: 13, secondary: true); stack.addArrangedSubview(sub); sub.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        switch step {
        case 0:
            stack.addArrangedSubview(Brand.mark(size: 72))
            text("Less searching. More creating.", "Bring your plugins, samples, and instrument libraries into one place. A few folder choices will help Simplify see your collection.")
            standardToggle.state = draft.standardPlugins ? .on : .off; standardToggle.target = self; standardToggle.action = #selector(toggleStandard)
            stack.addArrangedSubview(standardToggle)
            stack.addArrangedSubview(label("AU, VST, VST3, CLAP, and AAX installations in standard Mac locations. Your plugins are never opened or run.", size: 12, secondary: true))
            let custom = NSButton(title: "Add a custom plugin folder…", target: self, action: #selector(chooseFolders(_:))); folderActions[.plugins] = custom; custom.tag = 0; custom.bezelStyle = .rounded; stack.addArrangedSubview(custom)
            stack.addArrangedSubview(rootList(.plugins, height: 54))
            stack.addArrangedSubview(label("Scanning is read-only. Plugin removal always requires your review.", size: 11, weight: .medium, secondary: true))
        case 1:
            text("Where do your sounds live?", "Choose the folders you already use, including external drives. Keep individual samples separate from instrument libraries.")
            stack.addArrangedSubview(sourceCard(.samples, title: "Samples", subtitle: "One-shots, loops, and local Splice downloads. Add as many sample folders as you need."))
            stack.addArrangedSubview(sourceCard(.libraries, title: "Instrument libraries", subtitle: "Add separate parent folders for Kontakt, Orchestral Tools / SINE, VSL, Soundpaint, and more."))
            stack.addArrangedSubview(label("You can add more locations later. Vendor names are examples, not automatic identification.", size: 11, secondary: true))
        case 2:
            text("Give your sounds some context.", "Add folders containing saved DAW projects to look for samples included in them. Playback isn't required.")
            stack.addArrangedSubview(sourceCard(.projects, title: "Project folders", subtitle: "Start with current work or a small archive. Large project folders can take longer to scan."))
            stack.addArrangedSubview(label("What this preview can tell you", size: 14, weight: .semibold))
            stack.addArrangedSubview(label("Choose project folders for Logic Pro, Ableton Live, Cubase, Pro Tools, or your other DAWs. Coverage varies: this preview reads limited Ableton, Logic, and REAPER evidence; Cubase and Pro Tools session decoding is not available yet. Scan details lists each project's coverage. Unknown history is never treated as unused.", size: 12, secondary: true))
            stack.addArrangedSubview(label("Optional. You can browse your collection without projects.", size: 12, weight: .medium))
        default:
            stack.addArrangedSubview(Brand.mark(size: 54))
            text("Your collection starts here.", "Review your locations, then start your first scan. You can revisit this setup at any time from Manage locations.")
            let pluginSummary = draft.standardPlugins ? "Standard Mac locations + \(draft.roots[.plugins]?.count ?? 0) custom" : "\(draft.roots[.plugins]?.count ?? 0) custom folder\((draft.roots[.plugins]?.count ?? 0) == 1 ? "" : "s")"
            for (title, value) in [("Plugins", pluginSummary), ("Samples", summary(.samples)), ("Libraries", summary(.libraries)), ("Projects", summary(.projects))] {
                let row = NSStackView(views: [label(title, size: 13, weight: .semibold), NSView(), label(value, size: 12, secondary: true)])
                stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            stack.addArrangedSubview(label("Setup is saved only on this Mac. Scan results are rebuilt each session. Scans start when you ask; scheduled monitoring isn't part of this preview.", size: 12, secondary: true))
        }
        for view in stack.arrangedSubviews where view is NSTextField || view is NSScrollView || view is CatalogPanel { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        if let focusKind, let button = folderActions[focusKind] { window?.makeFirstResponder(button) }
        else { window?.makeFirstResponder(nextButton) }
    }
    private func summary(_ kind: RootKind) -> String { let count = draft.roots[kind]?.count ?? 0; return count == 0 ? "Not added · optional" : "\(count) folder\(count == 1 ? "" : "s") selected" }
    private func sourceCard(_ kind: RootKind, title: String, subtitle: String) -> NSView {
        let add = NSButton(title: "Add folders…", target: self, action: #selector(chooseFolders(_:)))
        folderActions[kind] = add
        add.tag = RootKind.allCases.firstIndex(of: kind)!; add.bezelStyle = .rounded; add.setAccessibilityLabel("Choose \(title.lowercased()) folders")
        let heading = NSStackView(views: [label(title + " (\(draft.roots[kind]?.count ?? 0))", size: 14, weight: .semibold), NSView(), add])
        let contents = column([heading, label(subtitle, size: 12, secondary: true), rootList(kind, height: 48)], spacing: 8)
        let wrapper = NSView(); pin(contents, in: wrapper, inset: 12)
        let panel = CatalogPanel(content: wrapper)
        for view in contents.arrangedSubviews { view.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true }
        return panel
    }
    private func rootList(_ kind: RootKind, height: CGFloat) -> NSView {
        let rows = column([], spacing: 4)
        for url in draft.roots[kind] ?? [] {
            let path = NSTextField(labelWithString: url.path); path.lineBreakMode = .byTruncatingMiddle; path.toolTip = url.path; path.font = .systemFont(ofSize: 11); path.textColor = .secondaryLabelColor
            path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            path.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let remove = NSButton(title: "Remove", target: self, action: #selector(removeRoot(_:))); remove.bezelStyle = .rounded; remove.controlSize = .mini; remove.setAccessibilityLabel("Remove \(url.lastPathComponent) from setup")
            remove.setContentCompressionResistancePriority(.required, for: .horizontal)
            rootButtons[remove] = (kind, url)
            let row = NSStackView(views: [path, remove]); rows.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        if (draft.roots[kind] ?? []).isEmpty { rows.addArrangedSubview(label("No folders added · add one or several at a time", size: 11, secondary: true)) }
        let document = TopAlignedDocument()
        let scroll = NSScrollView(); scroll.documentView = document; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        document.translatesAutoresizingMaskIntoConstraints = false
        rows.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(rows)
        NSLayoutConstraint.activate([document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            rows.leadingAnchor.constraint(equalTo: document.leadingAnchor), rows.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            rows.topAnchor.constraint(equalTo: document.topAnchor), rows.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: height)])
        return scroll
    }
    @objc private func chooseFolders(_ sender: NSButton) {
        guard let window else { return }; let kind = RootKind.allCases[sender.tag]
        let picker = NSOpenPanel(); picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.allowsMultipleSelection = true
        picker.prompt = "Add folders"; picker.message = "Choose \(kind.rawValue.lowercased()) folders. Files stay in their current locations."
        picker.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK else { return }; self.draft.addRoots(picker.urls, kind: kind); self.render(focusKind: kind)
        }
    }
    @objc private func removeRoot(_ sender: NSButton) { guard let (kind, url) = rootButtons[sender] else { return }; draft.removeRoot(url, kind: kind); render(focusKind: kind) }
    @objc private func toggleStandard() { draft.setStandardPlugins(standardToggle.state == .on) }
    @objc public func next() { if step < 3 { step += 1; render() } else { finish(remember: true) } }
    @objc public func back() { if step > 0 { step -= 1; render() } }
    @objc public func skip() { closeSheet() }
    @objc private func finishSession() { finish(remember: false) }
    private func finish(remember: Bool) {
        do { try model.acceptSetup(draft, remember: remember); closeSheet(); model.scan() }
        catch { errorLabel.stringValue = error.localizedDescription }
    }
    private func closeSheet() { guard let window else { return }; window.sheetParent?.endSheet(window) }
}
