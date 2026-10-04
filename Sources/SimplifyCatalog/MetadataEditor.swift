import AppKit
import SimplifyCore

/// Single-subject draft. The parent sheet prevents scan/setup races while editing.
@MainActor public final class MetadataEditor: NSWindowController, NSTextFieldDelegate {
    public let saveButton = NSButton(title: "Save", target: nil, action: nil)
    public let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    public let installationMenu = NSPopUpButton()
    public private(set) var fields: [MusicalFacet: NSTextField] = [:]
    public private(set) var suggestionButtons: [MusicalFacet: NSButton] = [:]
    public private(set) var isSaving = false
    private let message = label("Uncheck Suggested to edit. Use commas for multiple values; an empty edited field suppresses suggestions.", size: 11, secondary: true)
    private let model: CatalogModel
    private let node: CatalogOutlineNode
    private let targets: [Asset]
    private var target: Asset { targets[max(0, installationMenu.indexOfSelectedItem)] }
    public init(model: CatalogModel, node: CatalogOutlineNode) {
        self.model = model; self.node = node
        targets = [node.asset!]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: node.kind == .sample ? 620 : 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Edit musical metadata"; window.isReleasedWhenClosed = false
        super.init(window: window)
        installationMenu.addItems(withTitles: targets.map { $0.format.uppercased() + " · " + $0.path })
        installationMenu.setAccessibilityLabel("Installation to edit")
        installationMenu.target = self; installationMenu.action = #selector(changeTarget)
        installationMenu.isHidden = targets.count < 2
        let heading = label(node.title, size: 17, weight: .semibold); heading.maximumNumberOfLines = 2
        let stack = column([heading, installationMenu], spacing: 12)
        for facet in MusicalFacet.fields(for: node.asset!.kind) {
            let title = label(facet.title, size: 12); title.widthAnchor.constraint(equalToConstant: 125).isActive = true
            let field = NSTextField(); field.setAccessibilityLabel(facet.title); field.delegate = self
            field.placeholderString = facet == .bpm ? "e.g. 110" : "Comma-separated values"
            let suggested = NSButton(checkboxWithTitle: "Suggested", target: self, action: #selector(toggleSuggestion(_:)))
            suggested.setAccessibilityLabel("Use suggestions for " + facet.title); suggested.tag = MusicalFacet.allCases.firstIndex(of: facet)!
            fields[facet] = field; suggestionButtons[facet] = suggested
            let row = NSStackView(views: [title, field, suggested]); row.spacing = 8
            stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        message.maximumNumberOfLines = 3
        stack.addArrangedSubview(message); message.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        saveButton.target = self; saveButton.action = #selector(save); saveButton.keyEquivalent = "\r"
        cancelButton.target = self; cancelButton.action = #selector(cancel); cancelButton.keyEquivalent = "\u{1b}"
        let actions = NSStackView(views: [NSView(), cancelButton, saveButton]); actions.spacing = 12
        stack.addArrangedSubview(actions); actions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        pin(stack, in: window.contentView!, inset: 24)
        loadTarget()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    private func loadTarget() {
        let subject = model.subject(asset: target, instrument: node.instrument)
        let override = subject.flatMap { model.metadataOverrides[$0.key] }
        let effective = model.effectiveMetadata(asset: target, instrument: node.instrument)
        for (facet, field) in fields {
            field.stringValue = (effective[facet] ?? []).joined(separator: ", ")
            suggestionButtons[facet]?.state = override?[facet] == nil ? .on : .off
            field.isEnabled = override?[facet] != nil
        }
        installationMenu.toolTip = target.path
    }
    @objc private func changeTarget() { loadTarget() }
    @objc private func toggleSuggestion(_ sender: NSButton) {
        let facet = MusicalFacet.allCases[sender.tag]
        fields[facet]?.isEnabled = sender.state == .off
        if sender.state == .on { fields[facet]?.stringValue = (model.suggestedMetadata(asset: target, instrument: node.instrument)[facet] ?? []).joined(separator: ", ") }
        markDirty()
    }
    public func controlTextDidChange(_ notification: Notification) { markDirty() }
    private func markDirty() {
        installationMenu.isEnabled = false
        message.stringValue = targets.count > 1 ? "Save or cancel before changing installation. Empty edited fields suppress suggestions." : "Edits stay in your catalog. Empty edited fields suppress suggestions; Suggested restores local and enabled vendor suggestions."
    }
    @objc public func cancel() {
        guard !isSaving, let window else { return }
        window.sheetParent?.endSheet(window)
    }
    @objc public func save() {
        guard !isSaving, let subject = model.subject(asset: target, instrument: node.instrument) else { return }
        var draft = MusicalMetadata()
        for (facet, field) in fields where suggestionButtons[facet]?.state == .off {
            draft[facet] = field.stringValue.components(separatedBy: ",")
        }
        do { draft = try draft.validated() }
        catch { message.stringValue = "Use up to 24 values per field (80 characters each). BPM must be one number from 0 to 999, excluding zero."; return }
        isSaving = true; saveButton.isEnabled = false; cancelButton.isEnabled = false; installationMenu.isEnabled = false
        for field in fields.values { field.isEnabled = false }
        for button in suggestionButtons.values { button.isEnabled = false }
        Task { @MainActor in
            do {
                try await model.saveMetadata(draft, subject: subject)
                isSaving = false
                if let window { window.sheetParent?.endSheet(window) }
            } catch {
                isSaving = false; saveButton.isEnabled = true; cancelButton.isEnabled = true
                for (facet, field) in fields { field.isEnabled = suggestionButtons[facet]?.state == .off }
                for button in suggestionButtons.values { button.isEnabled = true }
                message.stringValue = "Couldn’t save. Your draft is intact. " + error.localizedDescription
            }
        }
    }
}
