import Foundation
import Testing
@testable import SimplifyCore

private final class ContainerFixture {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".work/scratch/container-" + UUID().uuidString)
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }
    @discardableResult func file(_ path: String, _ text: String = "fixture") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }
    func scan(_ request: ScanRequest) -> (assets: [Asset], issues: [ScanIssue]) {
        var issues: [ScanIssue] = []
        let assets = LibraryDiscovery.scan(request, sineDatabase: root.appendingPathComponent("absent.db"), issues: &issues)
        return (assets, issues)
    }
}

@Test func unownedSamplesContainersReachSameManifestFromAncestorOrDirectScope() throws {
    let f = try ContainerFixture()
    let product = "Disk/Samples/Collection/Samples/Example Folk"
    let manifest = try f.file(product + "/Example.nicnt", "<ProductHints><Product><Name>Example Folk</Name><Company>Example Maker</Company></Product></ProductHints>")
    let patch = try f.file(product + "/Instruments/Accordion.nki")
    try f.file(product + "/Samples/Not an instrument.nki")
    var request = ScanRequest(); request.libraries = [f.root.appendingPathComponent("Disk")]
    let ancestor = f.scan(request)
    request.libraries = [f.root.appendingPathComponent(product)]
    let direct = f.scan(request)
    #expect(ancestor.issues.isEmpty && direct.issues.isEmpty)
    #expect(ancestor.assets.count == 1 && direct.assets.count == 1)
    #expect(ancestor.assets.map(\.path) == direct.assets.map(\.path))
    #expect(ancestor.assets.first?.libraryMetadata?.identity == direct.assets.first?.libraryMetadata?.identity)
    #expect(ancestor.assets.first?.path == manifest.path)
    #expect(ancestor.assets.first?.libraryMetadata?.identity?.evidence == .manifest)
    #expect(ancestor.assets.first?.libraryMetadata?.maker == "Example Maker")
    #expect(ancestor.assets.first?.libraryMetadata?.instruments.map(\.path) == [patch.path])
    #expect(direct.assets.first?.libraryMetadata?.instruments.map(\.path) == [patch.path])
}

@Test func proposedOwnerStillExcludesPayloadAndRespectsSampleScope() throws {
    let f = try ContainerFixture()
    let product = "Disk/Samples/Collection/Example Strings"
    let patch = try f.file(product + "/Instruments/Violin.nki")
    try f.file(product + "/Samples/Decoy.nki")
    var request = ScanRequest(); request.libraries = [f.root.appendingPathComponent("Disk")]
    let result = f.scan(request)
    #expect(result.assets.count == 1 && result.issues.isEmpty)
    #expect(result.assets.first?.libraryMetadata?.identity?.evidence == .proposed)
    #expect(result.assets.first?.libraryMetadata?.instruments.map(\.path) == [patch.path])
    request.samples = [f.root.appendingPathComponent("Disk/Samples")]
    #expect(f.scan(request).assets.isEmpty)
    request.libraries.append(f.root.appendingPathComponent(product))
    #expect(f.scan(request).assets.first?.libraryMetadata?.instruments.map(\.path) == [patch.path])
}

@Test func newlyReachableContainersPreserveLinksDepthAndEntryGuards() throws {
    let f = try ContainerFixture()
    try f.file("Actual/Collection/Instruments/Banjo.nki")
    try f.file("Actual/Collection/Samples/payload.wav")
    let linkedRoot = f.root.appendingPathComponent("LinkedRoot")
    try FileManager.default.createDirectory(at: linkedRoot, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: linkedRoot.appendingPathComponent("Samples"), withDestinationURL: f.root.appendingPathComponent("Actual"))
    var request = ScanRequest(); request.libraries = [linkedRoot]
    #expect(f.scan(request).assets.isEmpty)
    try f.file("Disk/Samples/Collection/Instruments/Banjo.nki")
    try f.file("Disk/Samples/Collection/Samples/payload.wav")
    request.libraries = [f.root.appendingPathComponent("Disk")]
    request.maximumEntries = 2
    let limited = f.scan(request)
    #expect(limited.assets.isEmpty && limited.issues.contains { $0.reason.contains("incomplete") })
    request.maximumEntries = 100_000; request.maximumDepth = 1
    let shallow = f.scan(request)
    #expect(shallow.assets.isEmpty && shallow.issues.contains { $0.reason.contains("depth limit") })
    request.maximumDepth = 64
    #expect(f.scan(request).assets.count == 1)
}
