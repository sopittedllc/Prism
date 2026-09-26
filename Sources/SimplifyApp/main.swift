import AppKit
import SimplifyCore
import SimplifyCatalog

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: CatalogWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let isSmoke = CommandLine.arguments.contains("--ui-smoke")
        // Foundation preserves macOS's /var alias even when resolving temp URLs.
        // Use the same nonlinked, disposable fixture location as the store tests.
        let store = isSmoke ? SetupStore(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifySmoke/" + UUID().uuidString + "/setup.json")) : .application
        let catalog = isSmoke ? CatalogStore(url: store.url.deletingLastPathComponent().appendingPathComponent("catalog.sqlite")) : .application
        let model = CatalogModel(store: store, catalogStore: catalog)
        if let iconURL = Bundle.main.url(forResource: "Simplify", withExtension: "icns"), let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
            NSApp.dockTile.display()
        }
        controller = CatalogWindow(model: model)
        let find = NSMenuItem(title: "Find in Collection", action: #selector(CatalogWindow.focusSearch(_:)), keyEquivalent: "f")
        find.target = controller
        NSApp.mainMenu?.items.last?.submenu?.addItem(find)
        controller?.showWindow(nil)
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--project-root" {
            controller?.model.addRoots([URL(fileURLWithPath: CommandLine.arguments[2])], kind: .projects)
        }
        NSApp.activate(ignoringOtherApps: true)
        if !isSmoke { Task { await model.restoreSavedCatalog() } }
        if !isSmoke && !model.onboardingCompleted { controller?.showSetup() }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--ui-smoke" {
            let output = URL(fileURLWithPath: CommandLine.arguments[2])
            Task { @MainActor in
                defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
                do { try await smoke(controller!, output: output, store: store); NSApp.terminate(nil) }
                catch { fputs("UI smoke failed: \(error)\n", stderr); exit(1) }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum SmokeError: Error { case failed(String) }
@MainActor func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw SmokeError.failed(message) }
}

@MainActor func smoke(_ controller: CatalogWindow, output: URL, store: SetupStore) async throws {
    func activate(_ button: NSButton) {
        // Dispatch the native control action without a nested synthetic mouse-tracking loop.
        if let action = button.action { NSApp.sendAction(action, to: button.target, from: button) }
    }
    let files = FileManager.default
    try files.createDirectory(at: output, withIntermediateDirectories: true)
    let fixture = output.appendingPathComponent("fixture-" + UUID().uuidString)
    try files.createDirectory(at: fixture, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: fixture) }
    func file(_ path: String, _ value: String = "fixture") throws {
        let url = fixture.appendingPathComponent(path)
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }
    for index in 0..<3000 { try file("Samples/Percussion \(index).wav") }
    try file("Plugins/Studio Compressor – " + String(repeating: "Extended Edition ", count: 9) + ".vst3/Contents/Info.plist", "<plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>com.fixture.studiocompressor.vst3</string></dict></plist>")
    try file("Plugins/Studio Compressor – " + String(repeating: "Extended Edition ", count: 9) + ".component/Contents/Info.plist", "<plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>com.fixture.studiocompressor.au</string></dict></plist>")
    try file("Libraries/Chamber Strings/Samples/C3.wav")
    try file("Libraries/Chamber Strings/Accordion.nki")
    try file("Projects/Fixture.rpp", "<REAPER_PROJECT\n<TRACK\n<ITEM\n<SOURCE WAVE\nFILE \"../Samples/Percussion 0.wav\"\n>\n>\n>\n>")
    try file("Projects/Unsupported.ptx")
    let longProject = "<REAPER_PROJECT\n" + String(repeating: "# synthetic metadata\n", count: 100_000) + ">\n"
    for index in 0..<12 { try file("Projects/Archive \(index).rpp", longProject) }
    let window = controller.window!
    var screenshots: [String] = []
    func capture(_ name: String, target: NSWindow? = nil) async throws {
        let window = target ?? window
        window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        // Window-server capture includes native composited controls, unlike view caching.
        let number = window.windowNumber
        let path = output.appendingPathComponent(name + ".png").path
        let status = try await Task.detached {
            let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(number), path]
            try capture.run(); capture.waitUntilExit()
            return capture.terminationStatus
        }.value
        guard status == 0 else { throw SmokeError.failed("Window screenshot unavailable") }
        screenshots.append(name)
    }
    window.appearance = NSAppearance(named: .aqua)
    try await Task.sleep(for: .milliseconds(150))
    try await capture("empty-light")
    let model = controller.model
    controller.showSetup()
    var setup = controller.setup!
    try require(window.attachedSheet === setup.window, "Setup sheet visible")
    try await capture("setup-welcome", target: setup.window)
    setup.draft.addRoots([fixture], kind: .samples)
    activate(setup.skipButton)
    try await Task.sleep(for: .milliseconds(250))
    try require(model.roots.isEmpty && !model.isScanning, "Cancel discards draft without scan")
    controller.showSetup(); setup = controller.setup!
    setup.draft.setStandardPlugins(false)
    for kind in RootKind.allCases { setup.draft.addRoots([fixture.appendingPathComponent(kind.rawValue)], kind: kind) }
    activate(setup.nextButton)
    try require(setup.step == 1, "Welcome continues")
    try await capture("setup-sounds", target: setup.window)
    activate(setup.nextButton)
    try await capture("setup-projects", target: setup.window)
    activate(setup.backButton)
    try require(setup.step == 1 && setup.draft.roots[.samples]?.count == 1, "Back retains draft")
    activate(setup.nextButton); activate(setup.nextButton)
    try require(setup.step == 3 && !model.isScanning, "Review precedes scan")
    try await capture("setup-ready", target: setup.window)
    var capturedProgress = false
    var scheduledProgressCapture = false
    var progressCaptureError: String?
    let existingProgressHandler = model.onProgressChange
    model.onProgressChange = {
        existingProgressHandler?()
        if model.scanProgress?.phase == .inspecting && (model.scanProgress?.completed ?? 0) > 0 && (model.scanProgress?.fraction ?? 1) < 1 && !scheduledProgressCapture {
            scheduledProgressCapture = true
            Task { @MainActor in
                do {
                    // Allow the window server to present the new determinate control.
                    try await Task.sleep(for: .milliseconds(150))
                    try require(model.isScanning && !controller.scanProgressBar.isHidden, "Reading uses a measured progress bar")
                    activate(controller.categoryButtons[1])
                    try require(model.basicInventoryComplete && controller.table.numberOfRows == 3000, "Basic inventory is browseable before project analysis finishes")
                    controller.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                    try require(controller.detail.string.contains("being checked"), "References remain pending during analysis")
                    try await capture("reading-progress"); capturedProgress = true
                } catch { progressCaptureError = String(describing: error) }
            }
        }
    }
    activate(setup.nextButton)
    try require(!controller.scanProgressLabel.stringValue.isEmpty, "Initial discovery status visible")
    try require(model.isScanning, "Scan button must start background work")
    try require(!controller.scanButton.isEnabled, "Duplicate scan disabled")
    try await capture("loading-light")
    let deadline = Date().addingTimeInterval(60)
    while (model.isScanning || (scheduledProgressCapture && !capturedProgress && progressCaptureError == nil)) && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    try require(!model.isScanning, "Scan timeout")
    try require(model.catalogNotice == nil && model.savedCatalogDate != nil, "Fixture catalog persisted: \(model.catalogNotice ?? "no save timestamp")")
    try require(capturedProgress && progressCaptureError == nil, "Determinate reading progress shown and captured: \(progressCaptureError ?? "capture incomplete")")
    let setupOnly = CatalogModel(store: store)
    try require(setupOnly.onboardingCompleted && setupOnly.roots == model.roots && setupOnly.report == nil, "Reopen restores setup only")
    activate(controller.categoryButtons[1])
    try require(model.category == .sample, "Sample category action")
    let reopenStart = Date()
    let reopened = CatalogModel(store: store, catalogStore: CatalogStore(url: store.url.deletingLastPathComponent().appendingPathComponent("catalog.sqlite")))
    await reopened.restoreSavedCatalog()
    let restoreSeconds = Date().timeIntervalSince(reopenStart)
    try require(reopened.usingSavedCatalog && reopened.report?.assets.count == model.report?.assets.count, "Durable inventory reopens without a scan")
    try require(restoreSeconds < 2, "Cached 3000-sample fixture opens within 2 seconds")
    let cachedWindow = CatalogWindow(model: reopened); cachedWindow.showWindow(nil)
    cachedWindow.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    cachedWindow.showFormats()
    try require(cachedWindow.formatsWindow?.choices.allSatisfy { !$0.isEnabled } == true, "Cached plugin removal disabled")
    try require(cachedWindow.formatsWindow?.allButton.isEnabled == false, "Cached all-format removal disabled")
    try await capture("cached-plugin-formats", target: cachedWindow.formatsWindow?.window)
    cachedWindow.formatsWindow?.closeSheet()
    reopened.category = .sample; cachedWindow.refresh()
    try await capture("cached-collection", target: cachedWindow.window)
    cachedWindow.window?.appearance = NSAppearance(named: .aqua)
    cachedWindow.window?.setContentSize(NSSize(width: 1040, height: 658))
    try await capture("cached-collection-light-compact", target: cachedWindow.window)
    cachedWindow.close(); window.makeKeyAndOrderFront(nil)
    try require(controller.table.numberOfRows == 3000, "All samples visible")
    window.contentView?.layoutSubtreeIfNeeded()
    if let cell = controller.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView, let text = cell.textField {
        try require(abs(text.frame.midY - cell.bounds.midY) < 1, "Table text is vertically centered")
        let textRect = text.alignmentRect(forFrame: text.frame)
        try require(textRect.minX >= 7.5 && cell.bounds.maxX - textRect.maxX >= 7.5, "Table text has horizontal padding")
    } else { try require(false, "Table uses padded cells") }
    try await capture("samples-populated")
    controller.search.stringValue = "Percussion 0"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    try require(controller.table.numberOfRows == 1, "Search updates table")
    controller.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    try require(controller.detail.string.contains("Referencing projects:"), "Selected details show references")
    let selected = model.selectedPath
    controller.refresh()
    try require(model.selectedPath == selected, "Selection survives refresh")
    try await Task.sleep(for: .milliseconds(100))
    try await capture("sample-reference-light")
    window.setContentSize(NSSize(width: 1040, height: 658))
    window.appearance = NSAppearance(named: .darkAqua)
    try await Task.sleep(for: .milliseconds(100))
    try await capture("sample-reference-dark-compact")
    controller.search.stringValue = "no-match"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    try require(controller.table.numberOfRows == 0, "No-match state")
    try await capture("no-match-dark")
    controller.search.stringValue = ""
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    for segment in [0, 2] {
        activate(controller.categoryButtons[segment])
        try require(controller.table.numberOfRows == 1, "Other category")
        controller.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        try require(controller.detail.string.contains(segment == 0 ? "unknown" : "Usage"), "No false plugin/library reference")
        try await capture(segment == 0 ? "plugins-dark" : "libraries-dark")
    }
    controller.search.stringValue = "Accordion"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    try require(controller.table.numberOfRows == 1, "Library search matches instrument name")
    try await capture("library-instrument-search")
    controller.search.stringValue = ""
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    // Only generated plugin fixtures are ever passed to the real Trash service.
    activate(controller.categoryButtons[0])
    controller.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    try require(model.selectedPlugin?.installations.count == 2 && controller.table.numberOfRows == 1, "Formats share one plugin row")
    try require(controller.table.tableColumns.filter { !$0.isHidden }.map { $0.identifier.rawValue } == ["name", "reference"], "Plugin list only name and last used")
    controller.showFormats()
    let formats = controller.formatsWindow!
    let originals = formats.product.installations.map(\.path)
    try require(originals.allSatisfy { $0.hasPrefix(fixture.standardizedFileURL.path + "/") }, "Trash test is restricted to generated fixtures")
    try require(formats.choices.allSatisfy { $0.state == .off } && !formats.selectedButton.isEnabled, "Removal defaults to keep")
    try await capture("plugin-formats-dark", target: formats.window)
    formats.reviewAll()
    try require(formats.confirmation != nil, "All formats requires a review")
    try await capture("plugin-removal-review", target: formats.confirmation?.window)
    formats.window!.endSheet(formats.confirmation!.window, returnCode: .alertFirstButtonReturn)
    try await Task.sleep(for: .milliseconds(250))
    try require(originals.allSatisfy { files.fileExists(atPath: $0) }, "Cancel preserves all installations")
    formats.choices[0].state = .on
    formats.reviewSelected()
    formats.window!.endSheet(formats.confirmation!.window, returnCode: .alertSecondButtonReturn)
    let removalDeadline = Date().addingTimeInterval(15)
    while (formats.confirmation != nil || formats.isWorking || formats.results.isEmpty) && Date() < removalDeadline { try await Task.sleep(for: .milliseconds(50)) }
    try require(formats.results.count == 1 && formats.results[0].succeeded, "Selected synthetic installation reaches Trash")
    try require(!files.fileExists(atPath: originals[0]) && files.fileExists(atPath: originals[1]), "Unselected format is preserved")
    try require(model.pluginProducts.count == 1 && model.pluginProducts[0].installations.count == 1, "Surviving format keeps its grouped row")
    try await capture("plugin-removal-result", target: formats.window)
    formats.reviewAll()
    formats.window!.endSheet(formats.confirmation!.window, returnCode: .alertSecondButtonReturn)
    try await Task.sleep(for: .milliseconds(250))
    while (formats.confirmation != nil || formats.isWorking) && Date() < removalDeadline { try await Task.sleep(for: .milliseconds(50)) }
    try require(model.pluginProducts.isEmpty && !files.fileExists(atPath: originals[1]), "All remaining formats removed from fixture and catalog")
    formats.closeSheet()
    try await Task.sleep(for: .milliseconds(250))
    try require(model.coverageDetail.contains("unsupported"), "Unsupported project visible")
    try require(controller.scanButton.accessibilityLabel() == "Scan" || controller.scanButton.title == "Scan", "Named Scan")
    try require(controller.search.accessibilityLabel() == "Search collection", "Named search")
    try require(controller.categoryButtons.allSatisfy { $0.isEnabled }, "Sidebar navigation remains enabled")
    try require(controller.table.accessibilityLabel() == "Audio collection", "Named table")
    try require(controller.detail.accessibilityLabel() == "Selected item details", "Named details")
    window.makeFirstResponder(controller.table)
    let findEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                    characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3)!
    try require(NSApp.mainMenu?.performKeyEquivalent(with: findEvent) == true, "Command-F menu shortcut")
    try require(window.firstResponder === controller.search.currentEditor(), "Command-F focuses search")
    controller.showSetup()
    try require(controller.setup?.draft.roots == model.roots, "Revisited setup has accepted locations")
    try await capture("setup-dark", target: controller.setup?.window)
    if let button = controller.setup?.skipButton { activate(button) }
    try await Task.sleep(for: .milliseconds(250))
    // Long folder rows, overflow, and contextual focus after an edit.
    controller.showSetup()
    let longSetup = controller.setup!
    for index in 0..<10 {
        longSetup.draft.addRoots([fixture.appendingPathComponent("Long folder \(index) " + String(repeating: "orchestral samples ", count: 7))], kind: .samples)
    }
    activate(longSetup.nextButton)
    longSetup.window?.contentView?.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let setupViews = descendants(longSetup.window!.contentView!)
    if let remove = setupViews.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Remove" }) {
        activate(remove)
        try require((longSetup.window?.firstResponder as? NSButton)?.title == "Add folders…", "Removing a folder retains category focus")
    } else { try require(false, "Folder removal control exists") }
    try require(longSetup.window!.contentView!.bounds.width <= 741, "Long paths cannot expand setup width")
    try await capture("setup-long-folders", target: longSetup.window)
    activate(longSetup.skipButton)
    try await Task.sleep(for: .milliseconds(250))
    try file("blocked-store", "not a directory")
    let failedModel = CatalogModel(store: SetupStore(url: fixture.appendingPathComponent("blocked-store/setup.json")))
    let failedSetup = SetupWindow(model: failedModel)
    window.beginSheet(failedSetup.window!, completionHandler: nil)
    for _ in 0..<3 { activate(failedSetup.nextButton) }
    activate(failedSetup.nextButton)
    try require(!failedModel.isScanning && window.attachedSheet === failedSetup.window, "Setup save failure keeps recovery controls available")
    try await capture("setup-save-error", target: failedSetup.window)
    activate(failedSetup.skipButton)
    try await Task.sleep(for: .milliseconds(250))
    // Capture the actual Dock region on the primary display, not an icon preview.
    if let screen = NSScreen.screens.first {
        let frame = screen.frame
        let dockCapture = Process(); dockCapture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        dockCapture.arguments = ["-x", "-R0,\(Int(frame.height) - 140),\(Int(frame.width)),140", output.appendingPathComponent("dock.png").path]
        try dockCapture.run(); dockCapture.waitUntilExit()
        try require(dockCapture.terminationStatus == 0, "Dock screenshot available")
    }
    let afterRemoval = CatalogModel(store: store, catalogStore: CatalogStore(url: store.url.deletingLastPathComponent().appendingPathComponent("catalog.sqlite")))
    await afterRemoval.restoreSavedCatalog()
    try require(afterRemoval.usingSavedCatalog && afterRemoval.pluginProducts.isEmpty, "Removed formats stay absent after reopen")

    // Exercise every persistence state in native controls using a small separate scope.
    try file("PersistenceStates/Samples/Accordion.wav")
    try file("PersistenceStates/Libraries/Folk/Instruments/Accordion.nki")
    try file("PersistenceStates/Libraries/Folk/Samples/C3.wav")
    try file("PersistenceStates/Plugins/Folk.vst3/Contents/marker")
    let stateRoot = fixture.appendingPathComponent("PersistenceStates")
    let stateModel = CatalogModel(catalogStore: CatalogStore(url: stateRoot.appendingPathComponent("catalog.sqlite")))
    stateModel.setStandardPlugins(false)
    for kind in [RootKind.samples, .libraries, .plugins] { stateModel.addRoots([stateRoot.appendingPathComponent(kind.rawValue)], kind: kind) }
    func finishStateScan(_ model: CatalogModel) async throws {
        model.scan()
        let deadline = Date().addingTimeInterval(15)
        while model.isScanning && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try require(!model.isScanning, "Persistence state fixture scan completes")
    }
    try await finishStateScan(stateModel)
    try require(stateModel.report?.assets.count == 3 && stateModel.catalogNotice == nil, "Persistence state fixture saved")
    for kind in [RootKind.samples, .libraries, .plugins] {
        try files.moveItem(at: stateRoot.appendingPathComponent(kind.rawValue), to: stateRoot.appendingPathComponent("Offline" + kind.rawValue))
    }
    try await finishStateScan(stateModel)
    try require(stateModel.report?.assets.count == 3 && stateModel.report?.assets.allSatisfy { $0.catalogStale == true } == true, "Unavailable sources retain stale inventory")
    let stateWindow = CatalogWindow(model: stateModel); stateWindow.showWindow(nil)
    stateWindow.window?.appearance = NSAppearance(named: .darkAqua)
    stateModel.category = .library; stateWindow.refresh()
    stateWindow.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    try require(stateWindow.detail.string.contains("Not observed"), "Unobserved library instrument is labeled")
    try await capture("stale-library", target: stateWindow.window)
    stateModel.category = .plugin; stateWindow.refresh()
    stateWindow.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    stateWindow.showFormats()
    try require(stateWindow.formatsWindow?.choices.allSatisfy { !$0.isEnabled } == true && stateWindow.formatsWindow?.allButton.isEnabled == false, "Stale installation removal disabled")
    try await capture("stale-plugin-formats", target: stateWindow.formatsWindow?.window)
    stateWindow.formatsWindow?.closeSheet(); stateWindow.close()

    try file("PersistenceStates/broken.sqlite", "preserve this corrupt fixture")
    let errorModel = CatalogModel(catalogStore: CatalogStore(url: stateRoot.appendingPathComponent("broken.sqlite")))
    errorModel.setStandardPlugins(false); errorModel.addRoots([stateRoot.appendingPathComponent("OfflineSamples")], kind: .samples)
    try await finishStateScan(errorModel)
    let errorWindow = CatalogWindow(model: errorModel); errorWindow.showWindow(nil)
    errorWindow.window?.appearance = NSAppearance(named: .aqua)
    errorWindow.window?.setContentSize(NSSize(width: 1040, height: 658))
    errorModel.category = .sample; errorWindow.refresh()
    try require(errorModel.catalogNotice != nil && errorWindow.table.numberOfRows == 1 && errorWindow.scanButton.isEnabled, "Catalog save failure retains browsable live results and retry")
    let corruptContents = try String(contentsOf: stateRoot.appendingPathComponent("broken.sqlite"), encoding: .utf8)
    try require(corruptContents == "preserve this corrupt fixture", "Corrupt catalog remains unchanged")
    try await capture("catalog-save-error", target: errorWindow.window)
    errorWindow.close()
    let result: [String: Any] = ["status": "passed", "fixture_samples": 3000, "cached_restore_seconds": restoreSeconds, "screenshots": screenshots,
                                "checks": ["setup next/back/skip/finish controls", "draft cancellation", "setup reopen restores accepted roots", "explicit first scan", "actual scan/category controls", "async completion", "discovery counts and determinate reading progress", "search", "selection retention", "sample provenance", "unavailable matching", "coverage issues", "accessibility labels", "keyboard search focus", "centered padded cells", "inventory browsing before analysis completes", "long folder removal focus", "save error recovery", "grouped plugin formats", "cancel removal keeps all", "real Trash of synthetic fixtures only", "selective and whole-product removal", "durable catalog reopening", "cached removal disabled", "removed plugins stay absent after reopen", "offline library and instrument labels", "stale removal disabled", "catalog save failure retains live browsing", "corrupt catalog preserved"],
                                "limits": ["VoiceOver user testing not performed", "native open panel interaction not automated", "current Mac only", "first visual baseline, no previous image diff"]]
    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("runtime.json"))
    print("UI smoke: PASS")
}

if CommandLine.arguments == [CommandLine.arguments[0], "--state-contract"] {
    let model = CatalogModel()
    var contract: [String: Any] = ["definitions": CatalogStateRegistry.definitions, "defaults": model.stateSnapshot,
                                 "runtime_ids": Array(model.stateSnapshot.keys).sorted(), "preset_ids": [String](),
                                 "persistence": "local-setup-v1", "persistence_ids": Array(CatalogStateRegistry.persistedIDs).sorted(), "migration": "version 1; reject unsupported versions", "preset_serialization": "absent"]
    contract["catalog_definitions"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CatalogPersistenceRegistry.definitions))
    contract["catalog_schema_version"] = CatalogPersistenceRegistry.schemaVersion
    print(String(data: try JSONSerialization.data(withJSONObject: contract, options: [.sortedKeys]), encoding: .utf8)!)
} else {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    let menu = NSMenu()
    let appItem = NSMenuItem(); menu.addItem(appItem)
    let appMenu = NSMenu(); appItem.submenu = appMenu
    appMenu.addItem(withTitle: "Quit Simplify", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let editItem = NSMenuItem(); menu.addItem(editItem)
    let edit = NSMenu(title: "Edit"); editItem.submenu = edit
    for (title, selector, key) in [("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
        edit.addItem(withTitle: title, action: selector, keyEquivalent: key)
    }
    application.mainMenu = menu
    let delegate = AppDelegate(); application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
