import Foundation
import AppKit
import ApplicationServices
import CryptoKit

public struct LogicPluginUse: Codable, Sendable, Equatable {
    public static let sourceID = "apple.logic-pro.accessibility-mixer.v1"
    public let name: String
    public let eventID: String
    public let reportedDate: Date
    public let scope: String
    public init(name: String, reportedDate: Date = Date()) {
        self.name = name; self.reportedDate = reportedDate; scope = "currentMixer"
        eventID = SHA256.hash(data: Data([Self.sourceID, name, String(reportedDate.timeIntervalSince1970)].joined(separator: "\u{1F}").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Reads Logic's current mixer accessibility tree. A plugin group is admitted only
/// when it exposes plugin controls (bypass and open); browser/menu entries and AU
/// discovery are excluded. This is prospective current-session evidence.
public enum LogicAccessibilityCollector {
    public static func collect() -> [LogicPluginUse] {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { return [] }
        let root = AXUIElementCreateApplication(app.processIdentifier); var names = Set<String>()
        walk(root, inMixer: false, names: &names, depth: 0)
        return names.sorted().map { LogicPluginUse(name: $0) }
    }
    private static func walk(_ element: AXUIElement, inMixer: Bool, names: inout Set<String>, depth: Int) {
        guard depth < 18 else { return }
        let role = value(element, kAXRoleAttribute) as? String
        let description = value(element, kAXDescriptionAttribute) as? String
        let mixer = inMixer || (role == kAXLayoutAreaRole && description == "Mixer")
        if mixer && role == "AXGroup" && !description.isNilOrEmpty && hasPluginControls(element) {
            names.insert(description!)
        }
        guard let children = value(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for child in children { walk(child, inMixer: mixer, names: &names, depth: depth + 1) }
    }
    private static func hasPluginControls(_ element: AXUIElement) -> Bool {
        var sawBypass = false
        var sawOpen = false
        inspectControls(element, depth: 0, sawBypass: &sawBypass, sawOpen: &sawOpen)
        return sawBypass && sawOpen
    }
    private static func inspectControls(_ element: AXUIElement, depth: Int,
                                        sawBypass: inout Bool, sawOpen: inout Bool) {
        guard depth < 3, let children = value(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for child in children {
            let description = (value(child, kAXDescriptionAttribute) as? String)?.lowercased()
            let title = (value(child, kAXTitleAttribute) as? String)?.lowercased()
            let label = description ?? title ?? ""
            sawBypass = sawBypass || label == "bypass"
            sawOpen = sawOpen || label == "open"
            if sawBypass && sawOpen { return }
            inspectControls(child, depth: depth + 1, sawBypass: &sawBypass, sawOpen: &sawOpen)
            if sawBypass && sawOpen { return }
        }
    }
    private static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var result: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }; return result
    }
}
private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
