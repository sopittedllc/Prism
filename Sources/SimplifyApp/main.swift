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
        let receiptCollector: CatalogModel.ReceiptCollector?
        if isSmoke { receiptCollector = nil }
        else { receiptCollector = { assets, store in await PackageReceiptCollector.collect(assets: assets, store: store) } }
        let usageCollector: CatalogModel.UsageCollector?
        if isSmoke { usageCollector = nil }
        else {
            usageCollector = { assets, store in
                let live = await LiveUsageCollector.collect(assets: assets, store: store)
                let cubase = await Task.detached(priority: .utility) { CubaseUsageCollector.collect() }.value
                var recorded = live.recorded, failures = live.failures + cubase.failures
                for bound in cubase.uses {
                    guard let asset = assets.first(where: { $0.path == bound.pluginPath }) else { failures += 1; continue }
                    guard asset.kind == .plugin, asset.format == "vst3", let id = asset.catalogID else { failures += 1; continue }
                    do { _ = try await store.recordCubaseUsage(bound, for: id, at: Date()); recorded += 1 }
                    catch { failures += 1 }
                }
                let proTools = await Task.detached(priority: .utility) { ProToolsUsageCollector.collect(assets: assets) }.value
                failures += proTools.failures
                for bound in proTools.uses {
                    guard let asset = assets.first(where: { $0.path == bound.pluginPath }), asset.kind == .plugin,
                          let id = asset.catalogID else { failures += 1; continue }
                    do { _ = try await store.recordProToolsUsage(bound, for: id, at: Date()); recorded += 1 }
                    catch { failures += 1 }
                }
                let logic = await Task.detached(priority: .utility) { LogicAccessibilityCollector.collect() }.value
                for use in logic {
                    let matches = assets.filter { $0.kind == .plugin && $0.format == "component" && $0.name == use.name && $0.catalogID != nil }
                    guard matches.count == 1, let id = matches[0].catalogID else { failures += 1; continue }
                    do { _ = try await store.recordLogicUsage(use, for: id, at: Date()); recorded += 1 }
                    catch { failures += 1 }
                }
                return LiveUsageCollection(recorded: recorded, failures: failures, rejectedDocuments: live.rejectedDocuments)
            }
        }
        let model = CatalogModel(store: store, catalogStore: catalog, receiptCollector: receiptCollector, usageCollector: usageCollector, tagStore: ProductTagStore(url: store.url.deletingLastPathComponent().appendingPathComponent("product-tags.json")))
        if !isSmoke { model.setStandardPlugins(true) } // Standard roots are automatic; synthetic profiles remain isolated.
        if let iconURL = Bundle.main.url(forResource: "Prism", withExtension: "icns"), let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
            NSApp.dockTile.display()
        }
        controller = CatalogWindow(model: model)
        let settings = NSMenuItem(title: "Settings…", action: #selector(CatalogWindow.showSettings), keyEquivalent: ",")
        settings.target = controller
        NSApp.mainMenu?.items.first?.submenu?.insertItem(settings, at: 0)
        NSApp.mainMenu?.items.first?.submenu?.insertItem(.separator(), at: 1)
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
    func requireColumn(_ table: NSOutlineView, id: String) throws -> Int {
        guard let index = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == id }) else { throw SmokeError.failed("Missing column " + id) }
        return index
    }
    func visible(_ controller: CatalogWindow, kind: CatalogOutlineNode.Kind) -> [CatalogOutlineNode] {
        (0..<controller.table.numberOfRows).compactMap { controller.table.item(atRow: $0) as? CatalogOutlineNode }.filter { $0.kind == kind }
    }
    @discardableResult func select(_ controller: CatalogWindow, kind: CatalogOutlineNode.Kind, title: String? = nil) throws -> CatalogOutlineNode {
        guard let node = visible(controller, kind: kind).first(where: { title == nil || $0.title == title }) else {
            throw SmokeError.failed("Missing visible \(kind.rawValue) \(title ?? "")")
        }
        controller.table.selectRowIndexes(IndexSet(integer: controller.table.row(forItem: node)), byExtendingSelection: false)
        return node
    }
    func arrow(_ controller: CatalogWindow, right: Bool) throws {
        controller.window?.makeFirstResponder(controller.table)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad],
            timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil,
            characters: right ? "\u{F703}" : "\u{F702}", charactersIgnoringModifiers: right ? "\u{F703}" : "\u{F702}",
            isARepeat: false, keyCode: right ? 124 : 123)!
        controller.table.keyDown(with: event)
    }
    func clickHeader(_ controller: CatalogWindow, key: String) throws {
        let index = try requireColumn(controller.table, id: key)
        controller.table.scrollColumnToVisible(index)
        let header = controller.table.headerView!
        let rect = header.headerRect(ofColumn: index)
        let location = header.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: controller.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        NSApp.postEvent(event(.leftMouseUp), atStart: true)
        header.mouseDown(with: event(.leftMouseDown))
    }
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
    try file("Libraries/Chamber Strings/Legato Strings.nki")
    try file("Libraries/Chamber Strings/Strings.nicnt", "<ProductHints><Product><Name>Chamber Strings</Name><Company>Example Audio</Company></Product></ProductHints>")
    try file("Libraries/Folk Colors/Folk.nicnt", "<ProductHints><Product><Name>Folk Colors</Name><Company>Example Audio</Company></Product></ProductHints>")
    try file("Libraries/Folk Colors/Instruments/Accordion.nki")
    try file("Libraries/Folk Colors/Instruments/Piano.nki")
    try file("Libraries/Folk Colors/Samples/C3.wav")
    try file("Libraries/Mystery Box/Instruments/Unknown.nki")
    try file("Libraries/Mystery Box/Samples/C3.wav")
    try file("Projects/Fixture.rpp", "<REAPER_PROJECT\n<TRACK\n<ITEM\n<SOURCE WAVE\nFILE \"../Samples/Percussion 0.wav\"\n>\n>\n>\n>")
    try file("Projects/Unsupported.ptx")
    let longProject = "<REAPER_PROJECT\n" + String(repeating: "# synthetic metadata\n", count: 100_000) + ">\n"
    for index in 0..<12 { try file("Projects/Archive \(index).rpp", longProject) }
    let window = controller.window!
    var screenshots: [String] = []
    func capture(_ name: String, target: NSWindow? = nil) async throws {
        let window = target ?? window
        // Native outline disclosure animates. Capture the settled composition.
        try await Task.sleep(for: .milliseconds(350))
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
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    window.appearance = NSAppearance(named: .aqua)
    try await Task.sleep(for: .milliseconds(150))
    try await capture("empty-light")
    let model = controller.model
    controller.showSetup()
    var setup = controller.setup!
    try require(window.attachedSheet === setup.window, "Setup sheet visible")
    try require(setup.draft.standardPlugins, "Standard plugin folders automatic")
    try await capture("setup-welcome", target: setup.window)
    try require(setup.window!.contentView!.bounds.width <= 540 && setup.window!.contentView!.bounds.height <= 420, "Setup occupies half the previous area")
    setup.draft.addRoots([fixture], kind: .samples)
    activate(setup.skipButton)
    try await Task.sleep(for: .milliseconds(250))
    try require(model.roots.isEmpty && !model.isScanning, "Cancel discards draft without scan")
    controller.showSetup(); setup = controller.setup!
    setup.draft.setStandardPlugins(false)
    for kind in RootKind.allCases { setup.draft.addRoots([fixture.appendingPathComponent(kind.rawValue)], kind: kind) }
    setup.reloadFolders()
    try require(setup.folders.numberOfRows == 4 && !model.isScanning, "All folder kinds visible before Scan")
    try await capture("setup-mixed", target: setup.window)
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
                    // Inventory and progress are separately queued MainActor deliveries.
                    // Wait for the complete inventory snapshot, not a fixed scheduling gap.
                    let inventoryDeadline = Date().addingTimeInterval(2)
                    while !model.basicInventoryComplete && model.isScanning && Date() < inventoryDeadline {
                        try await Task.sleep(for: .milliseconds(10))
                    }
                    activate(controller.categoryButtons[1])
                    try require(model.basicInventoryComplete && visible(controller, kind: .sample).count == 3000,
                        "Basic inventory is browseable before project analysis finishes: complete=\(model.basicInventoryComplete), rows=\(visible(controller, kind: .sample).count), assets=\(model.report?.assets.filter { $0.kind == .sample }.count ?? -1)")
                    try select(controller, kind: .sample)
                    try require(controller.detail.string.contains("Checking…"), "References remain pending during analysis")
                    try await capture("reading-progress"); capturedProgress = true
                } catch { progressCaptureError = String(describing: error) }
            }
        }
    }
    activate(setup.scanButton)
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
    try require(visible(controller, kind: .sample).count == 3000, "All samples visible: table=\(visible(controller, kind: .sample).count), outline=\(model.outline.nodes.filter { $0.kind == .sample }.count), category=\(model.category), query=\(model.navigationQuery)")
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
    try require(controller.detail.string.contains("Project recency"), "Selected details show references")
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
        try require(visible(controller, kind: segment == 0 ? .plugin : .library).count == (segment == 0 ? 1 : 3), "Other category")
        try select(controller, kind: segment == 0 ? .plugin : .library)
        try require(controller.detail.string.localizedCaseInsensitiveContains("unknown"), "No false plugin/library reference")
        try await capture(segment == 0 ? "plugins-dark" : "libraries-dark")
    }
    let folk = try select(controller, kind: .library, title: "Folk Colors")
    try require(!controller.table.isItemExpanded(folk), "Libraries start collapsed")
    try arrow(controller, right: true)
    try require(controller.table.isItemExpanded(folk), "Native right arrow expands library")
    let piano = try select(controller, kind: .instrument, title: "Piano")
    try require(controller.detail.string.contains("Folk Colors") && controller.detail.string.contains("Shared with library"), "Instrument retains parent and shared storage context")
    try await capture("library-expanded-dark")
    controller.refresh()
    try require(controller.selectedNode?.id == piano.id && controller.table.isItemExpanded(folk), "Refresh preserves patch and expansion")
    controller.search.stringValue = "Accordion"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    try require(visible(controller, kind: .instrument).map(\.title) == ["Accordion"], "Library search prunes unrelated instruments")
    try select(controller, kind: .instrument, title: "Accordion")
    try require(controller.detail.string.contains("Example Audio › Folk Colors › Accordion"), "Search retains matching instrument breadcrumb")
    try await capture("library-instrument-search")
    activate(controller.categoryButtons[1]); activate(controller.categoryButtons[2])
    try require(controller.selectedNode?.title == "Accordion", "Category roundtrip retains search selection")
    controller.search.stringValue = "no such instrument"; controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    try require(controller.table.numberOfRows == 0, "Unmatched library search is empty")
    controller.search.stringValue = ""
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    try require(controller.selectedNode?.id == piano.id && controller.table.isItemExpanded(folk), "Clear search restores prior browse selection and expansion")
    controller.search.stringValue = "Folk Colors"; controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    try require(visible(controller, kind: .instrument).isEmpty, "Library-only query does not invent matching patches")
    try select(controller, kind: .library, title: "Folk Colors")
    try require(controller.detail.string.contains("Library tags match") && controller.detail.string.contains("Clear search to browse.") && !controller.detail.string.contains("Expand this library"), "Metadata-only match explains how to return to installed instruments")
    try await capture("library-metadata-search")
    controller.search.stringValue = ""; controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    try select(controller, kind: .library, title: "Folk Colors")
    try arrow(controller, right: false)
    try require(!controller.table.isItemExpanded(folk), "Native left arrow collapses library")
    controller.refresh()
    try require(!controller.table.isItemExpanded(folk), "Explicit collapsed state survives refresh")
    window.appearance = NSAppearance(named: .aqua)
    try await capture("library-hierarchy-light-compact")
    window.appearance = NSAppearance(named: .darkAqua)
    // Only generated plugin fixtures are ever passed to the real Trash service.
    activate(controller.categoryButtons[0])
    controller.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    try require(model.selectedPlugin?.installations.count == 2 && controller.table.numberOfRows == 1, "Formats share one plugin row")
    let pluginPaths = Set(model.selectedPlugin!.installations.map(\.path))
    let pathTexts = descendants(window.contentView!).compactMap { $0 as? NSTextView }.filter { $0.isSelectable }.map(\.string)
    let finderPaths = descendants(window.contentView!).compactMap { $0 as? NSButton }.filter { $0.title == "Show in Finder" }.compactMap(\.toolTip)
    try require(pluginPaths.isSubset(of: Set(pathTexts)) && Set(finderPaths) == pluginPaths, "Every plugin format has selectable full path and matching Finder target")

    try require(controller.table.tableColumns.filter { !$0.isHidden }.map { $0.identifier.rawValue } == ["name", "size", "installed", "reference"], "Plugin formats remain visible beside name and last used")
    try require(controller.detail.string.contains("Last used   Unknown") && controller.detail.string.contains("Date added   By ") && controller.detail.string.contains("Size   Not measured"), "Plugin lifecycle and size explicitly unknown")
    try require(!controller.detail.string.contains(fixture.path), "Plugin inspector hides installation paths")
    try await capture("asset-plugin-priority-compact")
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
    longSetup.reloadFolders()
    longSetup.window?.contentView?.layoutSubtreeIfNeeded()
    longSetup.folders.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    let previousCount = longSetup.folders.numberOfRows
    activate(longSetup.removeButton)
    try require(longSetup.folders.numberOfRows == previousCount - 1 && longSetup.window?.firstResponder === longSetup.folders, "Removing a folder retains list focus")
    try require(longSetup.window!.contentView!.bounds.width <= 540, "Long paths cannot expand setup width")
    try await capture("setup-long-folders", target: longSetup.window)
    activate(longSetup.skipButton)
    try await Task.sleep(for: .milliseconds(250))
    try file("blocked-store", "not a directory")
    let failedModel = CatalogModel(store: SetupStore(url: fixture.appendingPathComponent("blocked-store/setup.json")))
    let failedSetup = SetupWindow(model: failedModel)
    window.beginSheet(failedSetup.window!, completionHandler: nil)
    activate(failedSetup.scanButton)
    try require(!failedModel.isScanning && window.attachedSheet === failedSetup.window, "Setup save failure keeps recovery controls available")
    try await capture("setup-save-error", target: failedSetup.window)
    activate(failedSetup.sessionButton)
    try require(failedModel.onboardingCompleted, "Session recovery accepts setup without saving")
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
    let staleLibrary = try select(stateWindow, kind: .library)
    stateWindow.table.expandItem(staleLibrary)
    try select(stateWindow, kind: .instrument)
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
    try require(errorModel.catalogNotice != nil && visible(errorWindow, kind: .sample).count == 1 && errorWindow.scanButton.isEnabled, "Catalog save failure retains browsable live results and retry")
    let corruptContents = try String(contentsOf: stateRoot.appendingPathComponent("broken.sqlite"), encoding: .utf8)
    try require(corruptContents == "preserve this corrupt fixture", "Corrupt catalog remains unchanged")
    try await capture("catalog-save-error", target: errorWindow.window)
    errorWindow.close()

    try file("Hierarchy/One/Samples/Percussion/Kick.wav")
    try file("Hierarchy/Two/Samples/Percussion/Kick.wav", "a larger synthetic sample")
    try file("Hierarchy/One/Samples/Orchestral/Accordion.wav")
    let sampleModel = CatalogModel(); sampleModel.setStandardPlugins(false)
    let sampleRoots = ["One/Samples", "Two/Samples", "One/Samples/Orchestral"].map { fixture.appendingPathComponent("Hierarchy/" + $0) }
    sampleModel.addRoots(sampleRoots, kind: .samples)
    try await finishStateScan(sampleModel)
    sampleModel.category = .sample
    let sampleWindow = CatalogWindow(model: sampleModel); sampleWindow.showWindow(nil)
    sampleWindow.window?.appearance = NSAppearance(named: .aqua)
    try require(sampleWindow.table.accessibilityRole() == .outline, "Native accessibility outline role")
    try require(visible(sampleWindow, kind: .root).count == 3 && sampleModel.totalCount == 3, "Overlapping roots stay distinct without duplicating samples")
    let folder = try select(sampleWindow, kind: .folder, title: "Percussion")
    try arrow(sampleWindow, right: true)
    try require(sampleWindow.table.isItemExpanded(folder), "Native right arrow expands sample folder")
    let kick = try select(sampleWindow, kind: .sample, title: "Kick")
    try require(descendants(sampleWindow.window!.contentView!).compactMap { $0 as? NSTextView }.contains { $0.isSelectable && $0.string.contains("One/Samples/Percussion") }, "Sample details preserve distinguishable root and folder context")
    try await capture("sample-folder-tree", target: sampleWindow.window)
    sampleWindow.search.stringValue = "Kick"; sampleWindow.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    sampleModel.sort = .size; sampleWindow.refresh()
    try require(sampleWindow.table.numberOfRows == 2 && visible(sampleWindow, kind: .sample).count == 2, "Sample search is flat and preserves both roots")
    try select(sampleWindow, kind: .sample, title: "Kick")
    try require(sampleWindow.selectedNode?.location?.contains("/Two/") == true, "Flat sample search sorts across root boundaries")
    sampleWindow.window?.setContentSize(NSSize(width: 1040, height: 658))
    sampleWindow.window?.appearance = NSAppearance(named: .darkAqua)
    try await capture("sample-search-breadcrumbs", target: sampleWindow.window)
    sampleWindow.search.stringValue = ""; sampleWindow.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    try require(sampleWindow.selectedNode?.id == kick.id, "Clearing sample search restores browse selection")
    sampleModel.category = .plugin; sampleWindow.refresh()
    sampleModel.category = .sample; sampleWindow.refresh()
    try require(sampleWindow.selectedNode?.id == kick.id, "Switching categories preserves sample browsing")
    try await finishStateScan(sampleModel)
    try require(sampleWindow.selectedNode?.id == kick.id, "Rescan preserves sample selection and ancestors")
    sampleWindow.close()
    // Composer discovery uses isolated synthetic content and a separate local catalog.
    try file("Composer/Libraries/Folk/Folk.nicnt", "<ProductHints><Product><Name>Folk</Name><Company>Example Audio</Company></Product></ProductHints>")
    try file("Composer/Libraries/Folk/Solo Accordion Legato.nki")
    try file("Composer/Libraries/Folk/Piano.nki")
    try file("Composer/Libraries/Berlin/Product.nicnt", "<ProductHints><Product><Name>Berlin Strings</Name><Company>Orchestral Tools</Company></Product></ProductHints>")
    try file("Composer/Samples/Loop.wav")
    let composerRoot = fixture.appendingPathComponent("Composer")
    let composerStore = CatalogStore(url: composerRoot.appendingPathComponent("catalog.sqlite"))
    let composerModel = CatalogModel(catalogStore: composerStore, tagFetcher: { source in
        // Synthetic transport only; live official sources are checked by the separate network probe.
        try await Task.sleep(for: .milliseconds(100))
        return ProductTagRecord(sourceID: source.id, descriptionDigest: source.descriptionDigest, fetchedAt: Date())
    })
    composerModel.standardPlugins = false
    composerModel.addRoots([composerRoot.appendingPathComponent("Libraries")], kind: .libraries)
    composerModel.addRoots([composerRoot.appendingPathComponent("Samples")], kind: .samples)
    composerModel.category = .library
    try await finishStateScan(composerModel)
    let composerWindow = CatalogWindow(model: composerModel); composerWindow.showWindow(nil)
    composerWindow.window?.appearance = NSAppearance(named: .aqua)
    composerWindow.showSettings()
    let tagPreferences = composerWindow.setup!
    tagPreferences.onlineTagsButton.state = .on
    activate(tagPreferences.scanButton)
    try await Task.sleep(for: .milliseconds(250))
    let tagsDeadline = Date().addingTimeInterval(5)
    while composerModel.isFetchingTags && Date() < tagsDeadline { try await Task.sleep(for: .milliseconds(20)) }
    try require(!composerModel.isFetchingTags && composerModel.tagFetchStatus.contains("1 of 1 verified"), "Native online tags fetch completes")
    composerWindow.showSettings()
    let retryPreferences = composerWindow.setup!
    activate(retryPreferences.retryTagsButton)
    let retryDeadline = Date().addingTimeInterval(5)
    while composerModel.isFetchingTags && Date() < retryDeadline { try await Task.sleep(for: .milliseconds(20)) }
    try require(retryPreferences.retryTagsButton.isEnabled && retryPreferences.retryTagsButton.toolTip == composerModel.tagFetchStatus, "Settings Retry recovers after completion")
    activate(retryPreferences.skipButton)
    try await Task.sleep(for: .milliseconds(250))

    try select(composerWindow, kind: .library, title: "Berlin Strings")
    try require(composerWindow.tagPills.pills.contains { $0.value == "legato" }, "Vendor tags prominent with provenance")
    try await capture("product-tags-light", target: composerWindow.window)
    composerWindow.window?.setContentSize(NSSize(width: 1040, height: 680))
    composerWindow.window?.appearance = NSAppearance(named: .darkAqua)
    try require(composerWindow.detail.string.contains("No indexed instruments.") && !composerWindow.detail.string.contains("Expand this library"), "Empty instrument index offers no impossible expansion")
    try await capture("product-tags-dark-compact", target: composerWindow.window)
    let usageColumn = try requireColumn(composerWindow.table, id: "reference")
    try require(composerWindow.table.rect(ofColumn: usageColumn).maxX <= composerWindow.table.visibleRect.maxX, "Compact library usage remains visible")
    composerWindow.showSettings()
    composerWindow.setup!.onlineTagsButton.state = .off
    activate(composerWindow.setup!.scanButton)
    try await Task.sleep(for: .milliseconds(250))
    try require(!composerWindow.detail.string.contains("vendor suggestion"), "Disable excludes vendor suggestions")
    composerWindow.window?.appearance = NSAppearance(named: .aqua)
    composerModel.query = "solo accordion legato"; composerWindow.refresh()
    try require(composerWindow.search.searchMenuTemplate == nil, "Search has no dropdown menu")
    try require(composerModel.outline.nodes.filter { $0.kind == .instrument }.count == 1, "Multiword musical query finds exact instrument")
    let instrumentNode = try select(composerWindow, kind: .instrument)
    try require(composerWindow.detail.string.contains("Last used   Unknown") && composerWindow.detail.string.contains("Date added   Unknown"), "Instrument lifecycle facts remain independent of library dates")
    try require(!composerWindow.detail.string.contains(composerRoot.path), "Default library inspector excludes paths")
    try require(composerModel.tagSummary(instrumentNode).contains("accordion"), "List metadata summarizes selected instrument")
    try require(descendants(composerWindow.window!.contentView!).compactMap { $0 as? NSTextView }.contains { $0.isSelectable && $0.string == instrumentNode.location } && composerWindow.revealButton.toolTip == instrumentNode.location && composerWindow.revealButton.isEnabled, "Finder targets selected instrument location")
    let heading = composerWindow.revealButton.superview!
    try require(heading.subviews.contains { ($0 as? NSTextField)?.stringValue == "Location" }, "Finder sits beside Location")
    composerWindow.window?.setContentSize(NSSize(width: 1220, height: 780))
    try await Task.sleep(for: .milliseconds(100))
    for key in ["name", "format", "size", "installed", "reference"] {
        try clickHeader(composerWindow, key: key)
        let initialDirection = composerModel.sortReversed
        try clickHeader(composerWindow, key: key)
        try require(composerModel.sortReversed != initialDirection && composerWindow.selectedNode?.id == instrumentNode.id, "Header sort reverses and preserves selection: " + key)
    }
    try await capture("simple-browsing-inspector", target: composerWindow.window)
    composerWindow.clearFilters()
    try require(composerModel.usageFilter == .all, "Clear filters resets usage")
    composerModel.query = "solo accordion legato"; composerWindow.refresh()
    try select(composerWindow, kind: .instrument)
    try require(composerModel.canEditMetadata(composerWindow.selectedNode!), "Saved instrument metadata is editable")
    composerWindow.showMetadataEditor()
    let editor = composerWindow.metadataEditor!
    try require(editor.fields[.character]?.accessibilityLabel() == "Character", "Metadata input has an accessible label")
    let suggestion = editor.suggestionButtons[.character]!
    suggestion.state = .off; activate(suggestion)
    editor.fields[.character]?.stringValue = "dark, warm"
    editor.window?.makeFirstResponder(editor.fields[.character])
    try await capture("composer-metadata-editor", target: editor.window)
    activate(editor.cancelButton)
    try require(composerModel.metadataOverrides.isEmpty, "Cancel does not persist draft metadata")
    composerWindow.showMetadataEditor()
    let savedEditor = composerWindow.metadataEditor!
    let savedSuggestion = savedEditor.suggestionButtons[.character]!
    savedSuggestion.state = .off; activate(savedSuggestion)
    savedEditor.fields[.character]?.stringValue = "dark, warm"
    let catalogURL = composerRoot.appendingPathComponent("catalog.sqlite")
    let validCatalog = try Data(contentsOf: catalogURL)
    try Data("synthetic corrupt catalog".utf8).write(to: catalogURL)
    activate(savedEditor.saveButton)
    let failureDeadline = Date().addingTimeInterval(5)
    while savedEditor.isSaving && Date() < failureDeadline { try await Task.sleep(for: .milliseconds(20)) }
    try require(composerWindow.window?.attachedSheet != nil && savedEditor.fields[.character]?.stringValue == "dark, warm" && savedEditor.saveButton.isEnabled, "Failed metadata save retains draft and retry controls")
    try await capture("composer-metadata-save-error", target: savedEditor.window)
    try validCatalog.write(to: catalogURL)
    activate(savedEditor.saveButton)
    let editDeadline = Date().addingTimeInterval(5)
    while savedEditor.isSaving && Date() < editDeadline { try await Task.sleep(for: .milliseconds(20)) }
    try require(!savedEditor.isSaving && composerWindow.window?.attachedSheet == nil, "Metadata Save finishes and closes sheet")
    composerModel.query = "dark accordion"; composerWindow.refresh()
    try select(composerWindow, kind: .instrument)
    try require(composerWindow.tagPills.pills.contains { $0.value == "dark" } && composerWindow.tagPills.pills.contains { $0.value == "warm" }, "Edited musical metadata is visible with provenance")
    composerWindow.window?.setContentSize(NSSize(width: 1040, height: 680))
    try await capture("composer-search-compact", target: composerWindow.window)
    composerWindow.clearFilters()
    composerWindow.search.stringValue = "warm"; composerWindow.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    try require(composerModel.outline.nodes.filter { $0.kind == .instrument }.count == 1, "Plain tag search selects edited value")
    try select(composerWindow, kind: .instrument)
    try await capture("composer-facet-light", target: composerWindow.window)
    let editedSubject = composerModel.subject(asset: instrumentNode.asset!, instrument: instrumentNode.instrument)!
    try await composerModel.saveMetadata(MusicalMetadata(fields: ["character": ["dark"]]), subject: editedSubject)
    composerWindow.refresh()
    try require(composerModel.outline.nodes.isEmpty && composerWindow.search.stringValue == "warm", "Query stays visible after editing last match")
    try await composerModel.undoMetadata(); composerWindow.refresh()
    try require(composerModel.outline.nodes.filter { $0.kind == .instrument }.count == 1, "Undo restores tag search results")
    let reopenedComposer = CatalogModel(catalogStore: composerStore); reopenedComposer.standardPlugins = false
    reopenedComposer.addRoots([composerRoot.appendingPathComponent("Libraries")], kind: .libraries)
    reopenedComposer.addRoots([composerRoot.appendingPathComponent("Samples")], kind: .samples)
    reopenedComposer.category = .library
    await reopenedComposer.restoreSavedCatalog(); reopenedComposer.query = "warm accordion"
    try require(reopenedComposer.outline.nodes.filter { $0.kind == .instrument }.count == 1, "Edited musical query survives restart")
    activate(composerWindow.undoMetadataButton)
    let undoDeadline = Date().addingTimeInterval(5)
    while composerModel.canUndoMetadata || composerModel.isSavingMetadata {
        if Date() > undoDeadline { break }; try await Task.sleep(for: .milliseconds(20))
    }
    try require(composerModel.metadataOverrides.isEmpty, "Native Undo restores suggested metadata")
    composerWindow.clearFilters()
    composerModel.query = "accordion"; composerWindow.refresh()
    try select(composerWindow, kind: .instrument)
    activate(composerWindow.tagPills.addButton)
    let entry = composerWindow.tagEntry!
    entry.categoryMenu.selectItem(withTitle: MusicalFacet.character.title)
    entry.valueField.stringValue = "soft"
    try await capture("tag-pill-add", target: entry.view.window)
    let pillCatalog = try Data(contentsOf: catalogURL)
    try Data("synthetic failed tag save".utf8).write(to: catalogURL)
    activate(entry.addButton)
    composerWindow.tagPopover.performClose(nil)
    try require(composerWindow.tagPopover.isShown, "Saving pill draft cannot dismiss")
    while entry.isSaving { try await Task.sleep(for: .milliseconds(20)) }
    try require(entry.valueField.stringValue == "soft" && entry.addButton.isEnabled && !entry.message.stringValue.isEmpty, "Pill failed save retains draft and retry")
    try pillCatalog.write(to: catalogURL)
    activate(entry.addButton)
    while entry.isSaving { try await Task.sleep(for: .milliseconds(20)) }
    try require(composerWindow.tagPills.pills.contains { $0.value == "soft" }, "Plus pill saves a searchable tag")
    let legatoPill = composerWindow.tagPills.pills.first { $0.value == "legato" }!
    try require(legatoPill.removeButton.accessibilityLabel()?.contains("Technique") == true, "Pill removal exposes category accessibly")
    composerWindow.window?.makeFirstResponder(composerWindow.search)
    let hoverEvent = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: composerWindow.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
    legatoPill.mouseEntered(with: hoverEvent)
    try require(legatoPill.removeButton.showsRemove, "Hover reveals removal")
    try await capture("tag-pills-hover", target: composerWindow.window)
    legatoPill.mouseExited(with: hoverEvent)
    try require(!legatoPill.removeButton.showsRemove, "Leaving pill hides removal")
    composerWindow.window?.makeFirstResponder(legatoPill.removeButton)
    try require(composerWindow.window?.firstResponder === legatoPill.removeButton, "Pill delete keyboard reachable")
    try await capture("tag-pills-keyboard", target: composerWindow.window)
    let spaceUp = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: composerWindow.window!.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
    NSApp.postEvent(spaceUp, atStart: true)
    legatoPill.removeButton.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: composerWindow.window!.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!)
    try await Task.sleep(for: .milliseconds(100))
    while composerModel.isSavingMetadata { try await Task.sleep(for: .milliseconds(20)) }
    try require(!composerWindow.tagPills.pills.contains { $0.value == "legato" }, "Pill deletes suggested tag")
    try await composerModel.undoMetadata(); composerWindow.refresh()
    try require(composerWindow.tagPills.pills.contains { $0.value == "legato" }, "One Undo restores removed pill")
    try await composerModel.undoMetadata(); composerWindow.refresh()
    try require(!composerWindow.tagPills.pills.contains { $0.value == "soft" }, "Next Undo removes added pill")
    composerWindow.clearFilters()
    try file("Composer/Libraries/New Colors/Colors.nicnt", "<ProductHints><Product><Name>New Colors</Name><Company>Example Audio</Company></Product></ProductHints>")
    try file("Composer/Libraries/New Colors/Cello Tremolo.nki")
    try await finishStateScan(composerModel)
    composerWindow.refresh()
    try select(composerWindow, kind: .library, title: "New Colors")
    try require(composerWindow.detail.string.contains("Date added   During") && composerWindow.detail.string.contains("move or restored copy"), "New library arrival is qualified rather than an exact acquisition: " + composerWindow.detail.string)
    composerWindow.window?.appearance = NSAppearance(named: .darkAqua)
    try await capture("simple-browsing-dark", target: composerWindow.window)
    let overflowNode = composerWindow.selectedNode!
    let overflowSubject = composerModel.subject(asset: overflowNode.asset!)!
    try await composerModel.saveMetadata(MusicalMetadata(fields: ["role": (1...24).map { "Orchestral texture variation \($0)" }]), subject: overflowSubject)
    composerWindow.refresh(); composerWindow.window?.contentView?.layoutSubtreeIfNeeded()
    composerWindow.tagPills.layoutSubtreeIfNeeded()
    composerWindow.tagPills.scrollToVisible(composerWindow.tagPills.addButton.frame)
    try require(composerWindow.tagPills.visibleRect.intersects(composerWindow.tagPills.addButton.frame), "Trailing plus reachable in long tag list")
    try await capture("tag-pills-overflow", target: composerWindow.window)
    try await composerModel.undoMetadata(); composerWindow.refresh()
    try require(instrumentNode.instrument?.name == "Solo Accordion Legato", "Fixture retains instrument identity")
    composerWindow.clearFilters()
    composerWindow.changeCategory(composerWindow.categoryButtons[1])
    try select(composerWindow, kind: .sample)
    composerWindow.showMetadataEditor()
    let sampleEditor = composerWindow.metadataEditor!
    let bpmSuggestion = sampleEditor.suggestionButtons[.bpm]!
    bpmSuggestion.state = .off; activate(bpmSuggestion)
    sampleEditor.fields[.bpm]?.stringValue = "-3"
    activate(sampleEditor.saveButton)
    try require(!sampleEditor.isSaving && composerWindow.window?.attachedSheet != nil && sampleEditor.fields[.bpm]?.stringValue == "-3", "Invalid BPM retains editable draft")
    try await capture("composer-sample-validation", target: sampleEditor.window)
    activate(sampleEditor.cancelButton)
    composerWindow.close()
    // Exercise real Settings controls with inherited app appearance, not per-window overrides.
    window.appearance = nil
    try require(controller.folderButton.title == "Settings…", "Sidebar opens Settings")
    let settingsEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
        timestamp: 0, windowNumber: window.windowNumber, context: nil,
        characters: ",", charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43)!
    window.makeKeyAndOrderFront(nil)
    try require(NSApp.mainMenu?.performKeyEquivalent(with: settingsEvent) == true, "Command-comma opens Settings")
    let preferences = controller.setup!
    try require(window.attachedSheet === preferences.window && preferences.scanButton.title == "Save", "Settings uses Save without Scan")
    func chooseAppearance(_ sheet: SetupWindow, _ mode: CatalogAppearance) {
        sheet.appearancePicker.selectItem(at: CatalogAppearance.allCases.firstIndex(of: mode)!)
        _ = sheet.appearancePicker.sendAction(sheet.appearancePicker.action, to: sheet.appearancePicker.target)
    }
    try require(preferences.appearancePicker.titleOfSelectedItem == "Light", "Appearance defaults to Light")
    chooseAppearance(preferences, .dark)
    try require(NSApp.appearance?.name == .darkAqua && model.appearance == .light, "Dark preview leaves accepted preference unchanged")
    try await capture("settings-dark", target: preferences.window)
    try require(preferences.window?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua, "Settings sheet inherits dark preview")
    activate(preferences.skipButton)
    try await Task.sleep(for: .milliseconds(250))
    try require(NSApp.appearance?.name == .aqua && CatalogModel(store: store).appearance == .light, "Cancel reverts preview and persistence")
    let originalDirty = model.configurationChanged
    for mode in [CatalogAppearance.dark, .system, .light] {
        activate(controller.folderButton)
        let settings = controller.setup!
        chooseAppearance(settings, mode)
        if mode == .system { try require(NSApp.appearance == nil && window.appearance == nil, "System mode removes overrides for live AppKit following") }
        if mode == .light { try await capture("settings-light", target: settings.window) }
        activate(settings.scanButton)
        try await Task.sleep(for: .milliseconds(250))
        try require(!model.isScanning && model.configurationChanged == originalDirty && CatalogModel(store: store).appearance == mode, "Appearance Save persists without scan or dirtying locations")
    }
    let failedPreferences = SetupWindow(model: CatalogModel(store: SetupStore(url: fixture.appendingPathComponent("blocked-store/preferences.json"))), settings: true)
    window.beginSheet(failedPreferences.window!, completionHandler: nil)
    chooseAppearance(failedPreferences, .dark); activate(failedPreferences.scanButton)
    try require(window.attachedSheet === failedPreferences.window && failedPreferences.draft.appearance == .dark && !failedPreferences.sessionButton.isHidden, "Failed preference save retains preview and recovery")
    try await capture("settings-save-error", target: failedPreferences.window)
    activate(failedPreferences.skipButton)
    try await Task.sleep(for: .milliseconds(250))
    try require(NSApp.appearance?.name == .aqua, "Cancel after save failure restores accepted mode")
    let sessionModel = CatalogModel(store: SetupStore(url: fixture.appendingPathComponent("blocked-store/session.json")))
    let sessionPreferences = SetupWindow(model: sessionModel, settings: true)
    window.beginSheet(sessionPreferences.window!, completionHandler: nil)
    chooseAppearance(sessionPreferences, .system); activate(sessionPreferences.scanButton); activate(sessionPreferences.sessionButton)
    try require(sessionModel.appearance == .system && !sessionModel.isScanning && NSApp.appearance == nil, "Session-only preference applies without scan")
    try await Task.sleep(for: .milliseconds(250))
    // One row per Soundtoys product, section-scoped Scan captured before tab switching.
    for (name, identity) in [("Devil-Loc", "DevilLoc"), ("Devil-Loc_Deluxe", "DevilLocDeluxe")] {
        for (format, token) in [("component", "audiounit"), ("vst", "vst"), ("vst3", "vst3"), ("aaxplugin", "aax")] {
            try file("Sections/Plugins/\(name).\(format)/Contents/Info.plist", "<plist><dict><key>CFBundleIdentifier</key><string>com.soundtoys.\(token).\(identity)</string></dict></plist>")
        }
    }
    try file("Sections/Samples/Kick.wav"); try file("Sections/Libraries/Strings/Violin.nki")
    let sectionModel = CatalogModel(); sectionModel.setStandardPlugins(false)
    for kind in [RootKind.plugins, .samples, .libraries] { sectionModel.addRoots([fixture.appendingPathComponent("Sections/" + kind.rawValue)], kind: kind) }
    try await finishStateScan(sectionModel)
    let sectionWindow = CatalogWindow(model: sectionModel); sectionWindow.showWindow(nil)
    try require(sectionModel.pluginProducts.count == 2 && sectionModel.pluginProducts.allSatisfy { $0.installations.count == 4 }, "Soundtoys products group all formats but preserve Deluxe")
    try require(sectionWindow.table.tableColumn(withIdentifier: .init("format"))?.isHidden == true, "Plugins have no duplicate format column")
    try await capture("plugin-products-simple", target: sectionWindow.window)
    try require(descendants(sectionWindow.table).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "AAX, AU, VST2, VST3" }, "Formats appear under product names")
    try require(!descendants(sectionWindow.window!.contentView!).compactMap { $0 as? NSButton }.contains { $0.title == "Tag settings…" }, "Separate Tag settings removed")
    try file("Sections/Samples/New.wav")
    activate(sectionWindow.scanButton)
    try require(sectionModel.scanningKinds == [.plugin], "Scan captures focused Plugins section")
    activate(sectionWindow.categoryButtons[1])
    while sectionModel.isScanning { try await Task.sleep(for: .milliseconds(20)) }
    try require(sectionModel.report?.assets.filter { $0.kind == .sample }.count == 1 && sectionModel.report?.assets.contains { $0.kind == .library } == true, "Plugin Scan preserves other sections without scanning them")
    activate(sectionWindow.scanButton)
    while sectionModel.isScanning { try await Task.sleep(for: .milliseconds(20)) }
    try require(sectionModel.report?.assets.filter { $0.kind == .sample }.count == 2 && sectionModel.pluginProducts.count == 2, "Samples Scan updates only samples")
    sectionWindow.close()
    // Date UI fixtures are isolated from installed plugins and the user's catalog.
    let dateRoot = fixture.appendingPathComponent("DateEvidence")
    for name in ["Fixture Synth.component", "Fixture Synth.vst3", "Earlier.component", "Unknown.component"] {
        let id = name.hasPrefix("Fixture Synth") ? "org.example.synth" : "org.example." + name
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
        try file("DateEvidence/" + name + "/Contents/Info.plist", String(decoding: data, as: UTF8.self))
    }
    let dateCatalog = CatalogStore(url: store.url.deletingLastPathComponent().appendingPathComponent("DatePresentation/catalog.sqlite"))
    let dateModel = CatalogModel(catalogStore: dateCatalog)
    dateModel.setStandardPlugins(false); dateModel.addRoots([dateRoot], kind: .plugins)
    try await finishStateScan(dateModel); await dateModel.reloadInstallerRecords()
    let dateWindow = CatalogWindow(model: dateModel); dateWindow.showWindow(nil)
    dateWindow.window?.appearance = NSAppearance(named: .aqua)
    dateWindow.window?.setContentSize(NSSize(width: 1220, height: 780))
    let synthNode = try select(dateWindow, kind: .plugin, title: "Fixture Synth")
    let synth = dateModel.report!.assets.first { $0.name == "Fixture Synth" && $0.format == "component" }!
    let earlier = dateModel.report!.assets.first { $0.name == "Earlier" }!
    dateWindow.showFormats()
    let dateFormats = dateWindow.formatsWindow!
    func fixtureReceipt(_ asset: Asset, id: String, time: Double) -> AssetDateEvidence {
        AssetDateEvidence(sourceID: PackageReceiptProvenance.sourceID, evidenceID: id, subjectID: asset.catalogID!,
            kind: .installationRecord, eventDate: Date(timeIntervalSince1970: time), ingestedAt: Date(),
            packageReceipt: PackageReceiptProvenance(packageID: "org.example." + id, packageVersion: "1.0",
                bundlePath: asset.path, bundleIdentifier: asset.bundleIdentifier!, bundleVersions: ["1.0"]))
    }
    try await dateCatalog.appendDateEvidence([fixtureReceipt(synth, id: "synth.receipt", time: 1_758_067_200),
                                            fixtureReceipt(earlier, id: "earlier.receipt", time: 1_735_689_600)], asOf: Date())
    await dateModel.reloadInstallerRecords()
    try require(dateFormats.installerLabels.contains { $0.stringValue.contains("org.example.synth.receipt") }
                && dateFormats.installerLabels.contains { $0.stringValue.contains("Unknown") }, "Open format sheet updates only exact installation evidence")
    try await capture("installer-record-formats-light", target: dateFormats.window)
    activate(dateFormats.closeButton); try await Task.sleep(for: .milliseconds(150))
    try require(dateWindow.detail.string.contains("Records for 1 of 2 installations") && dateWindow.detail.string.contains("Date added   By "), "Partial receipt coverage does not imply acquisition")
    try clickHeader(dateWindow, key: "installed")
    try require(dateModel.visibleAssets.map(\.name) == ["Earlier", "Fixture Synth", "Unknown"], "Equal present-by dates use stable name ordering")
    try clickHeader(dateWindow, key: "installed")
    try require(dateModel.visibleAssets.map(\.name) == ["Earlier", "Fixture Synth", "Unknown"] && dateWindow.selectedNode?.id == synthNode.id, "Date sorting preserves selection")
    let column = try requireColumn(dateWindow.table, id: "installed")
    let row = dateWindow.table.row(forItem: dateWindow.selectedNode!)
    let dateCell = dateWindow.table.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView
    try require(dateCell?.textField?.accessibilityLabel()?.contains("present by") == true || dateCell?.textField?.accessibilityLabel()?.contains("Present by") == true,
                "Date cell accessibility exposes presence-bound meaning")
    try require(dateWindow.table.tableColumns[column].title == "Date added", "Shared addition header uses accurate meaning")
    try await capture("installer-record-light", target: dateWindow.window)
    dateWindow.window?.setContentSize(NSSize(width: 1040, height: 680)); dateWindow.window?.appearance = NSAppearance(named: .darkAqua)
    try await Task.sleep(for: .milliseconds(100))
    let lastColumn = try requireColumn(dateWindow.table, id: "reference")
    try require(dateWindow.table.rect(ofColumn: lastColumn).maxX <= dateWindow.table.visibleRect.maxX,
                "Installer record, size and last use fit compact plugin layout")
    let headerWidth = ("Date added" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]).width + 26
    try require(dateWindow.table.tableColumns[column].width >= headerWidth, "Receipt header and sort indicator fit")
    let sizeIndex = try requireColumn(dateWindow.table, id: "size")
    let sizeCell = dateWindow.table.view(atColumn: sizeIndex, row: row, makeIfNecessary: true) as? NSTableCellView
    if let text = sizeCell?.textField, let font = text.font {
        try require((text.stringValue as NSString).size(withAttributes: [.font: font]).width <= text.bounds.width,
                    "Compact size status fits without truncation")
    } else { throw SmokeError.failed("Missing compact size cell") }
    for locale in ["en_US", "de_DE", "ar_SA", "th_TH"] {
        let text = Date(timeIntervalSince1970: 1_758_067_200).formatted(.dateTime.locale(Locale(identifier: locale)).year().month(.twoDigits).day(.twoDigits))
        try require((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width <= dateWindow.table.tableColumns[column].width - 16,
                    "Localized numeric date fits: " + locale)
    }
    try await capture("installer-record-dark-compact", target: dateWindow.window)
    try file("DateEvidence/New Arrival.component/Contents/Info.plist", "<plist><dict><key>CFBundleIdentifier</key><string>org.example.arrival</string></dict></plist>")
    try await finishStateScan(dateModel)
    try select(dateWindow, kind: .plugin, title: "New Arrival")
    try require(dateWindow.detail.string.contains("Date added   During"), "Prospective arrival preserves interval precision")
    dateWindow.window?.setContentSize(NSSize(width: 1220, height: 780)); dateWindow.window?.appearance = NSAppearance(named: .aqua)
    try await capture("addition-arrival-light", target: dateWindow.window)
    // An isolated synthetic history exercises cross-year bounds through persistence.
    let rangeRoot = fixture.appendingPathComponent("AdditionRange")
    try FileManager.default.createDirectory(at: rangeRoot, withIntermediateDirectories: true)
    var rangeRequest = ScanRequest(); rangeRequest.plugins = [rangeRoot]
    let rangeScope = CatalogScope(rangeRequest)
    let rangeStore = CatalogStore(url: store.url.deletingLastPathComponent().appendingPathComponent("AdditionRange/catalog.sqlite"))
    let rangeStart = Date(timeIntervalSince1970: 1_704_067_200)
    let rangeEnd = Date(timeIntervalSince1970: 1_735_776_000)
    _ = try await rangeStore.ingest(Scanner().scan(rangeRequest), scope: rangeScope, at: rangeStart,
        additionContext: AdditionScanContext(scope: rangeScope, startedAt: rangeStart))
    try file("AdditionRange/Range Synth.component/Contents/Info.plist", "<plist><dict><key>CFBundleIdentifier</key><string>org.example.range</string></dict></plist>")
    _ = try await rangeStore.ingest(Scanner().scan(rangeRequest), scope: rangeScope, at: rangeEnd,
        additionContext: AdditionScanContext(scope: rangeScope, startedAt: rangeEnd))
    let rangeModel = CatalogModel(catalogStore: rangeStore)
    rangeModel.setStandardPlugins(false); rangeModel.addRoots([rangeRoot], kind: .plugins)
    await rangeModel.restoreSavedCatalog()
    let rangeWindow = CatalogWindow(model: rangeModel); rangeWindow.showWindow(nil)
    rangeWindow.window?.setContentSize(NSSize(width: 1040, height: 680)); rangeWindow.window?.appearance = NSAppearance(named: .darkAqua)
    try select(rangeWindow, kind: .plugin, title: "Range Synth")
    try await Task.sleep(for: .milliseconds(150))
    let arrivalRow = rangeWindow.table.row(forItem: rangeWindow.selectedNode!)
    let arrivalCell = rangeWindow.table.view(atColumn: column, row: arrivalRow, makeIfNecessary: true) as? NSTableCellView
    try require(arrivalCell?.textField?.stringValue.contains("–\n") == true && arrivalCell?.textField?.accessibilityLabel()?.contains("between") == true, "Range endpoints and accessible meaning retained")
    try await capture("addition-range-dark-compact", target: rangeWindow.window)
    rangeWindow.close()
    let usageLog = """
    2026-09-25T12:00:00.000000: info: Init: Version: 'Live 12.4.6 Build: fixture' 1
    2026-09-25T12:00:01.000000: info: Loading document "/fixture/Test.als"
    2026-09-25T12:00:02.000000: info: VST3: Going to restore: Fixture Synth
    2026-09-25T12:00:03.000000: info: VST3: plugin processor successfully loaded: Example 'Fixture Synth' v1.0 (cid: {12345678-1234-5678-ABCD-123456789ABC})
    2026-09-25T12:00:04.000000: info: VST3: Restored: Fixture Synth
    2026-09-25T12:00:05.000000: info: Loaded document was created by Ableton Live 12.4.6
    2026-09-25T12:00:06.000000: info: Default App: Begin ExchangeDocument
    2026-09-25T12:00:07.000000: info: Default App: End ExchangeDocument

    """
    let usage = try LiveUsageLog.parse(Data(usageLog.utf8)).events.first!
    let usageNode = dateModel.report!.assets.first { $0.name == "Fixture Synth" && $0.format == "vst3" }!.catalogID!
    try await dateCatalog.appendDateEvidence([AssetDateEvidence(sourceID: HostUsageProvenance.sourceID,
        evidenceID: usage.eventID(subjectID: usageNode), subjectID: usageNode, kind: .confirmedUse,
        eventDate: nil, ingestedAt: Date(), hostUsage: usage)], asOf: Date())
    await dateModel.reloadUsage()
    try select(dateWindow, kind: .plugin, title: "Fixture Synth")
    dateWindow.window?.setContentSize(NSSize(width: 1220, height: 780)); dateWindow.window?.appearance = NSAppearance(named: .aqua)
    try require(dateWindow.detail.string.contains("Last used   2026-09-25 DAW local") && dateWindow.detail.string.contains("product history"), "Qualified local usage is visible with class scope")
    try clickHeader(dateWindow, key: "reference")
    try require(dateModel.visibleAssets.first?.name == "Fixture Synth", "Qualified usage sorts before unknown")
    try await capture("last-used-live-light", target: dateWindow.window)
    dateWindow.window?.setContentSize(NSSize(width: 1040, height: 680)); dateWindow.window?.appearance = NSAppearance(named: .darkAqua)
    try await Task.sleep(for: .milliseconds(150))
    let useRow = dateWindow.table.row(forItem: dateWindow.selectedNode!)
    let useCell = dateWindow.table.view(atColumn: lastColumn, row: useRow, makeIfNecessary: true) as? NSTableCellView
    try require(useCell?.textField?.accessibilityLabel()?.contains("time zone unknown") == true, "Usage accessibility retains clock precision")
    try await capture("last-used-live-dark-compact", target: dateWindow.window)
    dateWindow.close()
    let savedDates = CatalogModel(catalogStore: dateCatalog)
    savedDates.setStandardPlugins(false); savedDates.addRoots([dateRoot], kind: .plugins)
    await savedDates.restoreSavedCatalog()
    let savedDatesWindow = CatalogWindow(model: savedDates); savedDatesWindow.showWindow(nil)
    savedDatesWindow.window?.appearance = NSAppearance(named: .aqua)
    savedDatesWindow.window?.setContentSize(NSSize(width: 1040, height: 680))
    try select(savedDatesWindow, kind: .plugin, title: "Fixture Synth")
    try require(savedDatesWindow.detail.string.contains("current installation not verified"), "Restored date is visibly historical")
    try await capture("installer-record-cached-light-compact", target: savedDatesWindow.window)
    savedDatesWindow.close()
    let failedDates = CatalogModel(catalogStore: dateCatalog, installerRecordLoader: { _, _, _ in throw CatalogStoreError.invalid })
    failedDates.setStandardPlugins(false); failedDates.addRoots([dateRoot], kind: .plugins)
    await failedDates.restoreSavedCatalog()
    let failedDatesWindow = CatalogWindow(model: failedDates); failedDatesWindow.showWindow(nil)
    failedDatesWindow.window?.setContentSize(NSSize(width: 1040, height: 680))
    try select(failedDatesWindow, kind: .plugin, title: "Fixture Synth")
    try require(failedDatesWindow.detail.string.contains("Unavailable") && failedDatesWindow.detail.string.contains("Scan to retry"), "Date read error is distinct and recoverable")
    try await capture("installer-record-unavailable", target: failedDatesWindow.window)
    failedDatesWindow.close()
    let result: [String: Any] = ["status": "passed", "fixture_samples": 3000, "cached_restore_seconds": restoreSeconds, "screenshots": screenshots,
                                "checks": ["installer-record sorting both ways, partial coverage, live format sheet, accessible source labels, locale widths, cached and read-error states", "section-scoped Scan and Soundtoys product grouping", "Settings appearance preview/cancel/save/session recovery and Command-comma", "single-page setup add/remove/cancel/scan controls", "draft cancellation", "setup reopen restores accepted roots", "explicit first scan", "actual scan/category controls", "async completion", "discovery counts and determinate reading progress", "search", "selection retention", "sample provenance", "unavailable matching", "coverage issues", "accessibility labels", "keyboard search focus", "centered padded cells", "inventory browsing before analysis completes", "long folder removal focus", "save error recovery", "grouped plugin formats", "cancel removal keeps all", "real Trash of synthetic fixtures only", "selective and whole-product removal", "durable catalog reopening", "cached removal disabled", "removed plugins stay absent after reopen", "offline library and instrument labels", "stale removal disabled", "catalog save failure retains live browsing", "corrupt catalog preserved", "native outline accessibility role", "native arrow expand and collapse", "library maker and instrument hierarchy", "search prunes unrelated patches", "search clear and category restoration", "metadata-only matches explicit", "distinct overlapping sample roots", "flat sample search and cross-root sort", "sample rescan selection restoration", "musical metadata cancel/save/undo", "edited metadata survives restart", "multiword musical search", "actual column header clicks toggle every sort and preserve selection", "search has no dropdown", "Finder beside Location targets selected instrument", "compact lifecycle columns visible", "installed date never inferred from scan", "plain tag search updates after edits and Undo", "Settings opt-in tag fetch and source tooltip", "compact single-page setup", "standard folders automatic", "pill add/delete/Undo and keyboard focus", "pill failed save preserves draft", "hover and Space key tag removal", "saving popover cannot dismiss", "long tag list plus reachable", "invalid BPM retains draft", "failed metadata save retains draft and retry"],
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
    appMenu.addItem(withTitle: "Quit Prism", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let editItem = NSMenuItem(); menu.addItem(editItem)
    let edit = NSMenu(title: "Edit"); editItem.submenu = edit
    for (title, selector, key) in [("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
        edit.addItem(withTitle: title, action: selector, keyEquivalent: key)
    }
    application.mainMenu = menu
    let delegate = AppDelegate(); application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
