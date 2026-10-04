import AppKit

/// Adapted from Projector's semantic typography, spacing, panel, and accent roles.
@MainActor enum CatalogTheme {
    static let accent = NSColor(srgbRed: 1, green: 0.2, blue: 0.55, alpha: 1)
    static let title = NSFont.systemFont(ofSize: 16, weight: .semibold)
    static let heading = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let body = NSFont.systemFont(ofSize: 12)
    static let caption = NSFont.systemFont(ofSize: 11)
    static let inset: CGFloat = 12
    static let gap: CGFloat = 8
    static let panelRadius: CGFloat = 8
}

@MainActor final class CatalogBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

@MainActor final class CatalogPanel: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false; addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
        wantsLayer = true; layer?.cornerRadius = CatalogTheme.panelRadius; layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: CatalogTheme.panelRadius, yRadius: CatalogTheme.panelRadius).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: CatalogTheme.panelRadius, yRadius: CatalogTheme.panelRadius).stroke()
    }
}

@MainActor enum Brand {
    static func icon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppMark", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        // A locally packaged preview can be launched by its executable path;
        // in that case Foundation may treat the executable as an unbundled tool.
        guard let executable = Bundle.main.executableURL else { return nil }
        let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
        guard contents.lastPathComponent == "Contents", contents.deletingLastPathComponent().pathExtension == "app" else { return nil }
        return NSImage(contentsOf: contents.appendingPathComponent("Resources/AppMark.png"))
    }
    static func mark(size: CGFloat) -> NSView {
        let tile = NSView(); tile.wantsLayer = true
        tile.layer?.backgroundColor = NSColor.white.cgColor; tile.layer?.cornerRadius = size * 0.22
        let image = NSImageView(); image.image = icon(); image.imageScaling = .scaleProportionallyUpOrDown
        image.setAccessibilityLabel("Prism app icon")
        image.translatesAutoresizingMaskIntoConstraints = false; tile.addSubview(image)
        NSLayoutConstraint.activate([tile.widthAnchor.constraint(equalToConstant: size), tile.heightAnchor.constraint(equalToConstant: size),
            image.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: size * 0.13), image.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -size * 0.13),
            image.topAnchor.constraint(equalTo: tile.topAnchor, constant: size * 0.13), image.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -size * 0.13)])
        return tile
    }
}

@MainActor func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
    let view = NSTextField(wrappingLabelWithString: text)
    view.font = .systemFont(ofSize: size, weight: weight); view.textColor = secondary ? .secondaryLabelColor : .labelColor
    return view
}

@MainActor func pin(_ child: NSView, in parent: NSView, inset: CGFloat = 0) {
    child.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(child)
    NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset), child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset), child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset), child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)])
}

@MainActor func column(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
    let stack = NSStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
    return stack
}

/// Shared table geometry: comfortable horizontal inset and baseline-independent centering.
@MainActor final class CatalogCell: NSTableCellView {
    init(value: String, primary: Bool, subtitle: String? = nil, query: String = "", context: String? = nil, wrap: Bool = false) {
        super.init(frame: .zero)
        let text = NSTextField(labelWithString: value)
        text.font = .systemFont(ofSize: 12, weight: primary ? .medium : .regular)
        text.textColor = primary ? .labelColor : .secondaryLabelColor
        text.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingMiddle
        text.maximumNumberOfLines = wrap ? 2 : 1
        text.toolTip = [value, subtitle, context].compactMap { $0 }.joined(separator: "\n")
        text.setAccessibilityLabel([value, context].compactMap { $0 }.joined(separator: " · ")); textField = text
        if !query.isEmpty {
            let attributed = NSMutableAttributedString(string: value, attributes: [.font: text.font!, .foregroundColor: text.textColor!])
            let match = (value as NSString).range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
            if match.location != NSNotFound { attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 12, weight: .bold), range: match) }
            text.attributedStringValue = attributed
        }
        text.translatesAutoresizingMaskIntoConstraints = false; addSubview(text)
        NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            text.centerYAnchor.constraint(equalTo: centerYAnchor, constant: subtitle == nil ? 0 : -7)])
        if let subtitle {
            let secondary = NSTextField(labelWithString: subtitle)
            secondary.font = .systemFont(ofSize: 10); secondary.textColor = .secondaryLabelColor
            secondary.lineBreakMode = .byTruncatingMiddle; secondary.toolTip = subtitle
            secondary.translatesAutoresizingMaskIntoConstraints = false; addSubview(secondary)
            NSLayoutConstraint.activate([secondary.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                secondary.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                secondary.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 1)])
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}

@MainActor final class InsetButtonCell: NSButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.draw(withFrame: cellFrame.insetBy(dx: 10, dy: 0), in: controlView)
    }
}

@MainActor final class TopAlignedDocument: NSView {
    nonisolated override var isFlipped: Bool { true }
}

/// No animation lag: the fill and accessible numeric value always represent the same snapshot.
@MainActor public final class ScanProgressTrack: NSView {
    public var doubleValue: Double = 0 { didSet { needsDisplay = true; setAccessibilityValue(doubleValue) } }
    public override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.progressIndicator)
        setAccessibilityMinValue(0); setAccessibilityMaxValue(100)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    public override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        var fill = bounds; fill.size.width *= CGFloat(min(100, max(0, doubleValue)) / 100)
        CatalogTheme.accent.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
    }
}

/// App-wide override; nil leaves AppKit following changes to the system preference.
@MainActor extension CatalogAppearance {
    func apply() {
        switch self {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }
}
