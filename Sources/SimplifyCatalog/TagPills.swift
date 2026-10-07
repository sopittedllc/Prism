import AppKit
import SimplifyCore

/// A read-only pill with text centered inside explicit, equal vertical insets.
@MainActor final class ReadOnlyTagPill: NSView {
    let facet: MusicalFacet
    let title: NSTextField
    static let pillHeight: CGFloat = 20

    init(facet: MusicalFacet, value: String) {
        self.facet = facet
        title = NSTextField(labelWithString: MusicalTagDisplay.title(value))
        super.init(frame: .zero)
        title.font = .systemFont(ofSize: 10, weight: .medium)
        title.textColor = .labelColor
        title.lineBreakMode = .byClipping
        title.setAccessibilityLabel(facet.title + ": " + title.stringValue)
        toolTip = facet.title + ": " + title.stringValue
        wantsLayer = true; layer?.cornerRadius = 9
        addSubview(title)
        updateColor()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(title.fittingSize.width) + 16,
               height: Self.pillHeight)
    }
    override func layout() {
        super.layout()
        let textHeight = ceil(title.fittingSize.height)
        title.frame = NSRect(x: 8, y: (bounds.height - textHeight) / 2,
                             width: max(0, bounds.width - 16), height: textHeight)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColor() }
    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = CatalogTheme.tagColor(facet).withAlphaComponent(0.22).cgColor
        }
    }
}

/// Compact read-only tag presentation for a visible collection outline cell.
/// Layout is recalculated only when this cell's width changes; the outline never
/// computes pill geometry for offscreen instruments.
@MainActor final class CollectionTagCell: NSTableCellView {
    private let heading = NSTextField(labelWithString: "")
    private let subtitleLabel: NSTextField?
    private let tagViews: [(MusicalFacet, String, ReadOnlyTagPill)]
    private let more = NSButton(title: "", target: nil, action: nil)
    private let allTags: [(MusicalFacet, String)]
    private let showAll: (NSButton, [(MusicalFacet, String)]) -> Void
    private var laidOutWidth: CGFloat = -1

    init(title: String, subtitle: String? = nil, tags: [(MusicalFacet, String)], context: String, query: String = "", showAll: @escaping (NSButton, [(MusicalFacet, String)]) -> Void) {
        self.subtitleLabel = subtitle.map { value in
            let text = NSTextField(labelWithString: value)
            text.font = .systemFont(ofSize: 10)
            text.textColor = .secondaryLabelColor
            text.lineBreakMode = .byTruncatingMiddle
            text.maximumNumberOfLines = 1
            text.toolTip = value
            return text
        }
        self.allTags = tags; self.showAll = showAll
        self.tagViews = tags.map { facet, value in
            (facet, value, ReadOnlyTagPill(facet: facet, value: value))
        }
        super.init(frame: .zero)
        heading.stringValue = title; heading.font = .systemFont(ofSize: 12, weight: .medium)
        heading.lineBreakMode = .byTruncatingMiddle
        heading.maximumNumberOfLines = 1
        if !query.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingMiddle
            let attributed = NSMutableAttributedString(string: title, attributes: [
                .font: heading.font!, .foregroundColor: heading.textColor!, .paragraphStyle: paragraph
            ])
            let match = (title as NSString).range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
            if match.location != NSNotFound {
                attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 12, weight: .bold), range: match)
            }
            heading.attributedStringValue = attributed
        }
        heading.toolTip = [title, subtitle, context].compactMap { $0 }.joined(separator: "\n")
        heading.setAccessibilityElement(true)
        let fullTags = tags.map { $0.0.title + ": " + MusicalTagDisplay.title($0.1) }.joined(separator: ", ")
        heading.setAccessibilityLabel(title + (subtitle.map { " · " + $0 } ?? "") + (context.isEmpty ? "" : " · " + context) + (fullTags.isEmpty ? "" : " · Tags: " + fullTags))
        heading.setAccessibilityHelp(fullTags)
        textField = heading; addSubview(heading)
        if let subtitleLabel { addSubview(subtitleLabel) }
        for (_, _, text) in tagViews { addSubview(text) }
        more.isBordered = false; more.font = .systemFont(ofSize: 10, weight: .semibold)
        more.contentTintColor = CatalogTheme.accent
        more.target = self; more.action = #selector(showMore)
        more.setAccessibilityRole(.button)
        addSubview(more)
        setAccessibilityHelp(tags.map { $0.0.title + ": " + MusicalTagDisplay.title($0.1) }.joined(separator: ", "))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func layout() {
        super.layout()
        let width = max(0, bounds.width - 16)
        heading.frame = NSRect(x: 8, y: bounds.height - 21, width: width, height: 16)
        subtitleLabel?.frame = NSRect(x: 8, y: bounds.height - 38, width: width, height: 13)
        guard abs(width - laidOutWidth) > 0.5 else { return }
        laidOutWidth = width
        let lineHeight: CGFloat = 21, gap: CGFloat = 4
        var placements: [(Int, CGFloat, CGFloat, CGFloat)] = []
        var line = 0, x: CGFloat = 8
        for (index, entry) in tagViews.enumerated() {
            let pillWidth = entry.2.intrinsicContentSize.width
            if pillWidth > width { continue }
            if x + pillWidth > width + 8 { line += 1; x = 8 }
            if line >= 2 { break }
            placements.append((index, x, CGFloat(line), pillWidth)); x += pillWidth + gap
        }
        var hiddenCount = tagViews.count - placements.count
        if hiddenCount > 0 {
            repeat {
                hiddenCount = tagViews.count - placements.count
                let moreWidth = ceil(("+\(hiddenCount) more" as NSString).size(withAttributes: [.font: more.font!]).width) + 10
                let last = placements.last
                let lastLine = last.map { Int($0.2) } ?? 0
                let end = last.map { $0.1 + $0.3 + gap } ?? 8
                if moreWidth <= width && (end + moreWidth <= width + 8 || (lastLine == 0 && moreWidth <= width)) { break }
                if placements.isEmpty { break }
                placements.removeLast()
            } while true
        }
        for (_, _, text) in tagViews { text.isHidden = true }
        for (index, px, row, pillWidth) in placements {
            let text = tagViews[index].2
            let offset: CGFloat = subtitleLabel == nil ? 42 : 59
            text.frame = NSRect(x: px, y: bounds.height - offset - row * lineHeight,
                                width: pillWidth, height: ReadOnlyTagPill.pillHeight)
            text.isHidden = false
        }
        more.isHidden = hiddenCount == 0
        if hiddenCount > 0 {
            more.title = "+\(hiddenCount) more"
            more.setAccessibilityLabel("Show all \(allTags.count) tags for \(heading.stringValue)")
            let last = placements.last
            let sameLineEnd = last.map { $0.1 + $0.3 + gap } ?? 8
            let sameLine = last.map { Int($0.2) } ?? 0
            let moreWidth = min(width, ceil((more.title as NSString).size(withAttributes: [.font: more.font!]).width) + 10)
            let row = sameLineEnd + moreWidth <= width + 8 ? sameLine : min(1, sameLine + 1)
            let px = row == sameLine ? sameLineEnd : 8
            let offset: CGFloat = subtitleLabel == nil ? 42 : 59
            more.frame = NSRect(x: px, y: bounds.height - offset - CGFloat(row) * lineHeight,
                                width: moreWidth, height: ReadOnlyTagPill.pillHeight)
        }
    }
    @objc private func showMore() { showAll(more, allTags) }
}

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
