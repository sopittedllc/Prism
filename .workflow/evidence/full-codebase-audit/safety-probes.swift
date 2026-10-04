// Synthetic audit probes. Link the existing debug SimplifyCore objects; no shared build.
// The only removal callback is injected and does not touch the filesystem.
import Foundation
@testable import SimplifyCore

@main struct SafetyProbes {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".cache/safety-audit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let plugins = root.appendingPathComponent("Plugins")
        let bundle = plugins.appendingPathComponent("Synthetic.vst3")
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = contents.appendingPathComponent("Info.plist")
        func writeIdentity(_ value: String) throws {
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": value], format: .xml, options: 0).write(to: info)
        }
        try writeIdentity("com.synthetic.before")
        var pluginRequest = ScanRequest(); pluginRequest.plugins = [plugins]
        let asset = Scanner().scan(pluginRequest).assets.first!
        print("before_error=", PluginRemoval.validationError(asset) as Any)
        try writeIdentity("com.synthetic.after")
        print("root_identity_equal_after_descendant_edit=", asset.fileIdentity == PluginFileIdentity.read(bundle.path))
        print("validation_error_after_descendant_edit=", PluginRemoval.validationError(asset) as Any)
        var invoked = false
        let results = PluginRemoval.perform([asset]) { _ in
            invoked = true
            return "/synthetic-only/no-trash-performed"
        }
        print("injected_trash_operation_invoked=", invoked, "result_success=", results.first!.succeeded)

        let sounds = root.appendingPathComponent("Sounds")
        try FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)
        try Data("synthetic".utf8).write(to: sounds.appendingPathComponent("Accordion.wav"))
        let store = CatalogStore(url: root.appendingPathComponent("Catalog/catalog.sqlite"))
        var request = ScanRequest(); request.samples = [sounds]
        let first = try await store.ingest(Scanner().scan(request), scope: CatalogScope(request))
        print("first_scope_assets=", first.report.assets.count)
        try FileManager.default.moveItem(at: sounds, to: root.appendingPathComponent("Offline-Sounds"))
        let same = try await store.ingest(Scanner().scan(request), scope: CatalogScope(request))
        print("same_scope_offline_assets=", same.report.assets.count, "stale=", same.report.assets.first?.catalogStale as Any)
        let projects = root.appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        request.projects = [projects]
        let changed = try await store.ingest(Scanner().scan(request), scope: CatalogScope(request))
        print("add_projects_scope_offline_assets=", changed.report.assets.count)
    }
}
