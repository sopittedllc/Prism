import AppKit
import SimplifyCore

/// Category colors inspired by Logic's track palette. Text/category labels remain authoritative.
@MainActor extension CatalogTheme {
    static func tagColor(_ facet: MusicalFacet) -> NSColor {
        switch facet {
        case .instrument: .systemBlue
        case .technique: .systemGreen
        case .ensemble: .systemTeal
        case .register: .systemPurple
        case .character: .systemPink
        case .role: .systemOrange
        case .function: .systemIndigo
        case .sampleType: .systemYellow
        case .bpm: NSColor(calibratedRed: 0.55, green: 0.72, blue: 0.16, alpha: 1)
        case .key: .systemCyan
        }
    }
}

@MainActor public final class TagRemoveButton: NSButton {
    public override var acceptsFirstResponder: Bool { true }
    public var showsRemove: Bool { hovered || window?.firstResponder === self }
    var hovered = false { didSet { needsDisplay = true } }
    public override func draw(_ dirtyRect: NSRect) {
        if showsRemove { super.draw(dirtyRect) }
    }
    public override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); needsDisplay = true; return result }
    public override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); needsDisplay = true; return result }
}

@MainActor public final class TagPill: NSView {
    public let facet: MusicalFacet
    public let value: String
    public let removeButton = TagRemoveButton(title: "", target: nil, action: nil)
    private let title: NSTextField
    private let remove: () -> Void
    private var tracking: NSTrackingArea?
    public init(facet: MusicalFacet, value: String, editable: Bool, scope: String, remove: @escaping () -> Void) {
        self.facet = facet; self.value = value; self.remove = remove
        let display = MusicalTagDisplay.title(value)
        title = NSTextField(labelWithString: display)
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 12
        title.font = .systemFont(ofSize: 11, weight: .medium); title.lineBreakMode = .byTruncatingTail
        toolTip = facet.title + ": " + display + (scope.isEmpty ? "" : " · " + scope)
        title.setAccessibilityLabel(facet.title + ": " + display)
        removeButton.isBordered = false; removeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        removeButton.imageScaling = .scaleProportionallyDown; removeButton.isEnabled = editable
        removeButton.target = self; removeButton.action = #selector(removeTag)
        removeButton.setAccessibilityLabel("Remove " + display + ", " + facet.title + (scope.isEmpty ? "" : ", from all installed formats"))
        addSubview(title); addSubview(removeButton)
        updateColor()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    public override var intrinsicContentSize: NSSize { NSSize(width: min(228, ceil((title.stringValue as NSString).size(withAttributes: [.font: title.font!]).width) + 56), height: 25) }
    public override func layout() {
        super.layout()
        title.frame = NSRect(x: 10, y: 5, width: max(0, bounds.width - 34), height: 15)
        removeButton.frame = NSRect(x: bounds.width - 23, y: 3, width: 20, height: 19)
    }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColor() }
    private func updateColor() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = CatalogTheme.tagColor(facet).withAlphaComponent(0.25).cgColor } }
    public override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(next); tracking = next; super.updateTrackingAreas()
    }
    public override func mouseEntered(with event: NSEvent) { removeButton.hovered = true }
    public override func mouseExited(with event: NSEvent) { removeButton.hovered = false }
    @objc private func removeTag() { remove() }
}

/// Wrapping, vertically scrolling tag list. The add pill is always the final item.
@MainActor public final class TagPillList: NSView {
    public private(set) var pills: [TagPill] = []
    public let addButton = NSButton(title: "+", target: nil, action: nil)
    private var onAdd: (() -> Void)?
    public override var isFlipped: Bool { true }
    public override init(frame: NSRect) {
        super.init(frame: frame)
        addButton.bezelStyle = .rounded; addButton.controlSize = .small
        addButton.isBordered = false; addButton.wantsLayer = true; addButton.layer?.cornerRadius = 12
        addButton.font = .systemFont(ofSize: 13, weight: .medium)
        updateAddColor()
        addButton.setAccessibilityLabel("Add tag"); addButton.target = self; addButton.action = #selector(addTag)
        addSubview(addButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    public func update(tags: [(MusicalFacet, String)], editable: Bool, scope: String,
                       onRemove: @escaping (MusicalFacet, String) -> Void, onAdd: @escaping () -> Void) {
        for pill in pills { pill.removeFromSuperview() }
        self.onAdd = onAdd
        pills = tags.map { facet, value in
            let pill = TagPill(facet: facet, value: value, editable: editable, scope: scope) { onRemove(facet, value) }
            addSubview(pill); return pill
        }
        addSubview(addButton, positioned: .above, relativeTo: nil)
        addButton.title = tags.isEmpty ? "+ Add tag" : "+"; addButton.isEnabled = editable
        needsLayout = true
    }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateAddColor() }
    private func updateAddColor() { effectiveAppearance.performAsCurrentDrawingAppearance { addButton.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor } }
    public func contentHeight(width: CGFloat) -> CGFloat { arrange(width: width, apply: false) }
    private func arrange(width: CGFloat, apply: Bool) -> CGFloat {
        var x: CGFloat = 0, y: CGFloat = 0
        for view in (pills.map { $0 as NSView } + [addButton]) {
            let w = min(width, view === addButton ? (pills.isEmpty ? 85 : 30) : view.intrinsicContentSize.width)
            if x > 0 && x + w > width { x = 0; y += 31 }
            if apply { view.frame = NSRect(x: x, y: y, width: w, height: 25) }
            x += w + 6
        }
        return y + 27
    }
    public override func layout() { super.layout(); _ = arrange(width: max(1, bounds.width), apply: true) }
    @objc private func addTag() { onAdd?() }
}

/// A disposable single-tag draft, bound to the selected node when opened.
@MainActor public final class TagEntryController: NSViewController {
    public let categoryMenu = NSPopUpButton()
    public let valueField = NSTextField()
    public let addButton = NSButton(title: "Add", target: nil, action: nil)
    public let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    public let message = label("", size: 11, secondary: true)
    public private(set) var isSaving = false
    private let model: CatalogModel
    private let node: CatalogOutlineNode
    private let facets: [MusicalFacet]
    private let dismiss: () -> Void
    public init(model: CatalogModel, node: CatalogOutlineNode, dismiss: @escaping () -> Void) {
        self.model = model; self.node = node; self.dismiss = dismiss
        facets = MusicalFacet.fields(for: node.asset!.kind)
        super.init(nibName: nil, bundle: nil)
        view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 190))
        categoryMenu.addItems(withTitles: facets.map(\.title)); categoryMenu.setAccessibilityLabel("Tag category")
        valueField.placeholderString = "Tag name"; valueField.setAccessibilityLabel("Tag name")
        addButton.target = self; addButton.action = #selector(save); addButton.keyEquivalent = "\r"; addButton.bezelStyle = .rounded
        cancelButton.target = self; cancelButton.action = #selector(cancel); cancelButton.keyEquivalent = "\u{1b}"; cancelButton.bezelStyle = .rounded
        let scope = node.kind == .plugin ? "Applies to all installed formats." : ""
        let actions = NSStackView(views: [NSView(), cancelButton, addButton]); actions.spacing = 8
        let stack = column([categoryMenu, valueField, label(scope, size: 11, secondary: true), message, actions], spacing: 10)
        pin(stack, in: view, inset: 16)
        for item in stack.arrangedSubviews { item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    public override func viewDidAppear() { super.viewDidAppear(); view.window?.makeFirstResponder(valueField) }
    @objc public func cancel() { guard !isSaving else { return }; dismiss() }
    @objc public func save() {
        guard !isSaving else { return }
        let facet = facets[categoryMenu.indexOfSelectedItem]
        let value = valueField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(","), value.count <= 80 else { message.stringValue = "Enter one tag, up to 80 characters."; return }
        do { _ = try MusicalMetadata(fields: [facet.rawValue: [value]]).validated() }
        catch { message.stringValue = facet == .bpm ? "Enter a BPM between 1 and 999." : "Enter a valid tag, up to 80 characters."; return }
        let targets = node.asset.flatMap(model.product)?.installations ?? [node.asset!]
        if targets.allSatisfy({ (model.effectiveMetadata(asset: $0, instrument: node.instrument)[facet] ?? []).contains { MusicalSearch.normalized($0) == MusicalSearch.normalized(value) } }) {
            message.stringValue = "That tag is already here."; return
        }
        isSaving = true; addButton.isEnabled = false; cancelButton.isEnabled = false; valueField.isEnabled = false; categoryMenu.isEnabled = false
        Task { @MainActor in
            do { try await model.changeTag(value, facet: facet, removing: false, node: node); isSaving = false; dismiss() }
            catch {
                isSaving = false; addButton.isEnabled = true; cancelButton.isEnabled = true; valueField.isEnabled = true; categoryMenu.isEnabled = true
                message.stringValue = "Couldn’t save. Your tag is kept here; try again."
                message.toolTip = error.localizedDescription
            }
        }
    }
}
