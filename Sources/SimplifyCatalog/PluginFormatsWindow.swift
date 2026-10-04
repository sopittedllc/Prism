import AppKit
import SimplifyCore

/// Installation choices are a discardable review draft; unchecked files stay in place.
@MainActor public final class PluginFormatsWindow: NSWindowController {
    public let product: PluginProduct
    public private(set) var choices: [NSButton] = []
    public let selectedButton = NSButton(title: "Review selected…", target: nil, action: nil)
    public let allButton = NSButton(title: "Remove all formats…", target: nil, action: nil)
    public let closeButton = NSButton(title: "Done", target: nil, action: nil)
    public private(set) var confirmation: NSAlert?
    public private(set) var results: [PluginRemovalResult] = []
    public private(set) var isWorking = false
    public private(set) var installerLabels: [NSTextField] = []
    public private(set) var finderButtons: [NSButton] = []
    private let model: CatalogModel
    private let message = label("", size: 12, secondary: true)
    private let summary = label("", size: 12, secondary: true)

    public init(product: PluginProduct, model: CatalogModel) {
        self.product = product; self.model = model
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 580), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Plugin formats"; panel.isReleasedWhenClosed = false
        panel.contentView?.widthAnchor.constraint(equalToConstant: 740).isActive = true
        super.init(window: panel)
        let name = label(product.name, size: 22, weight: .semibold); name.maximumNumberOfLines = 2; name.lineBreakMode = .byTruncatingMiddle; name.toolTip = product.name
        let subtitle = label("Choose installations to remove. Unchecked formats will be kept.", secondary: true)
        let document = TopAlignedDocument(); let rows = column([], spacing: 14)
        document.addSubview(rows); rows.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView(); scroll.documentView = document; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        document.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            rows.topAnchor.constraint(equalTo: document.topAnchor, constant: 8), rows.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 8),
            rows.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12), rows.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -8)])
        for (index, installation) in product.installations.enumerated() {
            let toggle = NSButton(checkboxWithTitle: PluginProduct.formatName(installation.format) + " · " + URL(fileURLWithPath: installation.path).lastPathComponent, target: self, action: #selector(updateChoices))
            toggle.tag = index; toggle.state = .off; toggle.isEnabled = model.canReviewRemoval(installation); toggle.lineBreakMode = .byTruncatingMiddle
            toggle.setAccessibilityLabel("Remove " + PluginProduct.formatName(installation.format) + " at " + installation.path)
            choices.append(toggle)
            let path = label(installation.path, size: 11, secondary: true); path.maximumNumberOfLines = 2; path.lineBreakMode = .byTruncatingMiddle; path.toolTip = installation.path; path.isSelectable = true
            let finder = NSButton(title: "Show in Finder", target: self, action: #selector(revealInstallation(_:)))
            finder.tag = index; finder.bezelStyle = .rounded; finder.controlSize = .small
            finder.toolTip = installation.path
            finder.setAccessibilityLabel("Show " + PluginProduct.formatName(installation.format) + " in Finder")
            finderButtons.append(finder)
            let receipt = label("", size: 11, secondary: true)
            receipt.isSelectable = true; installerLabels.append(receipt)
            let location = NSStackView(views: [path, finder]); location.spacing = 8
            let row = column([toggle, receipt, location], spacing: 4); rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            for view in [toggle, receipt, location] { view.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true; view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
        }
        selectedButton.target = self; selectedButton.action = #selector(reviewSelected); selectedButton.bezelStyle = .rounded
        allButton.target = self; allButton.action = #selector(reviewAll); allButton.bezelStyle = .rounded
        closeButton.target = self; closeButton.action = #selector(closeSheet); closeButton.bezelStyle = .rounded; closeButton.keyEquivalent = "\u{1b}"
        message.stringValue = model.usingSavedCatalog || product.installations.contains(where: { $0.catalogStale == true }) ? "Scan again to verify these installations before removing them." : "Only the listed plugin bundles are moved to Trash. Presets, licenses, shared files, and sample libraries stay in place. Quit your DAWs first."
        let footer = NSStackView(views: [allButton, NSView(), closeButton, selectedButton]); footer.spacing = 10
        let stack = column([name, subtitle, scroll, summary, message, footer], spacing: 16); pin(stack, in: panel.contentView!, inset: 24)
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        updateChoices(); refreshInstallerRecords()
    }
    /// Keep an open review sheet consistent with async evidence refresh/invalidation.
    public func refreshInstallerRecords() {
        for (index, installation) in product.installations.enumerated() {
            installerLabels[index].stringValue = "Size: " + model.pluginSize(installation, grouped: false).value
                + (installation.catalogStale == true ? " · Not observed in latest scan" : "")
            installerLabels[index].setAccessibilityLabel(PluginProduct.formatName(installation.format) + ". " + installerLabels[index].stringValue)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    @objc private func updateChoices() {
        let count = choices.filter { $0.state == .on && $0.isEnabled }.count
        let currentPaths = Set(model.pluginProducts.flatMap(\.installations).map(\.path))
        let needsScan = choices.filter { !$0.isEnabled && currentPaths.contains(product.installations[$0.tag].path) }.count
        let removed = product.installations.filter { !currentPaths.contains($0.path) }.count
        let kept = choices.filter(\.isEnabled).count - count
        var parts = ["\(count) selected"]
        if kept > 0 { parts.append("\(kept) kept") }
        if needsScan > 0 { parts.append("\(needsScan) need scan") }
        if removed > 0 { parts.append("\(removed) removed") }
        summary.stringValue = isWorking ? "Moving selected installations…" : parts.joined(separator: " · ")
        selectedButton.isEnabled = count > 0 && !model.isBusy && !isWorking
        allButton.isEnabled = choices.contains(where: \.isEnabled) && !model.isBusy && !isWorking
    }
    @objc public func reviewSelected() { review(choices.filter { $0.state == .on && $0.isEnabled }.map(\.tag)) }
    @objc public func reviewAll() { review(choices.filter(\.isEnabled).map(\.tag)) }
    private func review(_ indexes: [Int]) {
        guard let window, !indexes.isEmpty, !model.isBusy, !isWorking, window.attachedSheet == nil else { return }
        let installations = indexes.map { product.installations[$0] }
        let alert = NSAlert(); alert.messageText = "Move \(installations.count) installation(s) to Trash?"
        alert.informativeText = "Projects using these formats may stop loading correctly. Reference coverage is incomplete. Review every path below. You can restore files from Trash in Finder."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Move to Trash").hasDestructiveAction = true
        alert.buttons[0].keyEquivalent = "\r"; alert.buttons[1].keyEquivalent = ""
        let text = NSTextView(); text.string = installations.map { PluginProduct.formatName($0.format) + "\n" + $0.path }.joined(separator: "\n\n")
        let scroll = CatalogWindow.textScroll(text); scroll.frame = NSRect(x: 0, y: 0, width: 540, height: 170); alert.accessoryView = scroll
        confirmation = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }; self.confirmation = nil
            guard response == .alertSecondButtonReturn else { return }
            self.isWorking = true; self.closeButton.isEnabled = false; self.choices.forEach { $0.isEnabled = false }; self.updateChoices()
            self.message.stringValue = "Moving selected installations to Trash…"
            Task { @MainActor in
                self.results = await self.model.trashPlugins(installations)
                self.isWorking = false; self.closeButton.isEnabled = true
                let removed = Set(self.results.filter(\.succeeded).map(\.path))
                for (index, toggle) in self.choices.enumerated() {
                    toggle.isEnabled = self.model.pluginProducts.contains { $0.installations.contains { $0.path == self.product.installations[index].path && self.model.canReviewRemoval($0) } }
                    toggle.state = .off
                }
                self.message.stringValue = self.results.isEmpty ? "Nothing was moved. Close this panel and scan again." : "\(removed.count) moved to Trash. \(self.results.count - removed.count) could not be moved. Restore from Trash in Finder; rescan after restoring."
                if self.results.contains(where: { !$0.succeeded }) {
                    let errors = NSAlert(); errors.messageText = "Some installations were kept"
                    errors.informativeText = "Review the errors below. Nothing is permanently deleted."
                    let detail = NSTextView(); detail.string = self.results.filter { !$0.succeeded }.map { $0.path + "\n" + ($0.error ?? "") }.joined(separator: "\n\n")
                    let scroll = CatalogWindow.textScroll(detail); scroll.frame = NSRect(x: 0, y: 0, width: 540, height: 180); errors.accessoryView = scroll
                    errors.beginSheetModal(for: window, completionHandler: nil)
                }
                self.updateChoices()
            }
        }
    }
    @objc public func closeSheet() { guard !isWorking, let window else { return }; window.sheetParent?.endSheet(window) }
    @objc private func revealInstallation(_ sender: NSButton) {
        guard product.installations.indices.contains(sender.tag) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: product.installations[sender.tag].path)])
    }
}
