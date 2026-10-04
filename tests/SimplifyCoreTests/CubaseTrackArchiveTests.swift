import Foundation
import Testing
@testable import SimplifyCore

private let archiveUID = "1234567890ABCDEF1234567890ABCDEF"
private func archivePlugin(_ name: String = "Example", original: String? = nil) -> String {
    "<member name=\"Plugin\"><string name=\"Plugin Name\" value=\"\(name)\"/>"
    + (original.map { "<string name=\"Original Plugin Name\" value=\"\($0)\"/>" } ?? "")
    + "<member name=\"Plugin UID\"><string name=\"GUID\" value=\"\(archiveUID)\"/></member></member>"
}
private func archiveTrack(_ content: String, name: String = "Track", instrument: Bool = true) -> String {
    let kind = instrument ? "MInstrumentTrack" : "MAudioTrack"
    return "<obj class=\"\(kind)Event\"><obj class=\"MListNode\" name=\"Node\"><string name=\"Name\" value=\"\(name)\"/></obj><obj class=\"\(kind)\" name=\"Track Device\"><member name=\"DeviceAttributes\">\(content)</member></obj></obj>"
}
private func archiveSynth(_ plugin: String) -> String { "<member name=\"Synth Slot\">\(plugin)</member>" }
private func archiveInserts(_ items: String) -> String { "<member name=\"InsertFolder\"><list name=\"Slot\" type=\"list\">\(items)</list></member>" }
private func archiveXML(_ tracks: String, extra: String = "") -> Data {
    Data("<tracklist2><list name=\"track\" type=\"obj\">\(tracks)</list>\(extra)</tracklist2>".utf8)
}

@Test func archiveOwnersPreserveDuplicatesAndOriginalPluginNames() throws {
    let first = archiveTrack(archiveSynth(archivePlugin()), name: "Same")
    let renamed = archiveTrack(archiveSynth(archivePlugin("Renamed", original: "Example")), name: "Same")
    let audio = archiveTrack(archiveInserts("<item>\(archivePlugin("EQ Test"))</item><item>\(archivePlugin("EQ Test"))</item>"), instrument: false)
    let report = try CubaseTrackArchiveReader.parse(archiveXML(first + renamed + audio))
    #expect(report.tracks.map(\.ordinal) == [0, 1, 2])
    #expect(report.tracks.map(\.name) == ["Same", "Same", "Track"])
    #expect(report.tracks.flatMap(\.plugins).map(\.name) == ["Example", "Example", "EQ Test", "EQ Test"])
    #expect(report.tracks.flatMap(\.plugins).map(\.role) == ["instrument", "instrument", "insert", "insert"])
    #expect(report.tracks.flatMap(\.plugins).allSatisfy { $0.uid == archiveUID })
    #expect(report.coverage == "partial-export" && report.unsupportedTrackCount == 0)
}

@Test func archiveRemovalAndUnrelatedStateDoNotBecomePluginReferences() throws {
    let decoy = archivePlugin("Decoy")
    let excluded = "<member name=\"Opaque State\">\(archiveSynth(decoy))</member>"
        + "<member name=\"Browser\">\(decoy)</member>"
        + "<member name=\"Synth Slot\"><member name=\"History\">\(decoy)</member></member>"
        + "<member name=\"InputFilter\">\(decoy)</member>"
        + "<member name=\"StripFolder\"><list name=\"Slot\" type=\"list\"><item>\(decoy)</item></list></member>"
    let unsupported = "<obj class=\"UnknownTrack\">\(archiveTrack(archiveSynth(decoy)))</obj>"
    let report = try CubaseTrackArchiveReader.parse(archiveXML(archiveTrack(excluded, name: "Diva") + unsupported,
                                                              extra: archiveTrack(archiveSynth(decoy))))
    #expect(report.tracks.count == 1 && report.tracks[0].plugins.isEmpty)
    #expect(report.unsupportedTrackCount == 1)
    #expect(report.limitations.contains { $0.contains("never establish") })
    #expect(try CubaseTrackArchiveReader.parse(archiveXML(archiveTrack(archiveSynth(decoy), instrument: false))).tracks[0].plugins.isEmpty)
}

@Test func archiveRejectsDuplicateAndMissingSupportedFields() {
    let plugin = archivePlugin()
    let normal = archiveTrack(archiveSynth(plugin))
    let guid = "<string name=\"GUID\" value=\"\(archiveUID)\"/>"
    let name = "<string name=\"Plugin Name\" value=\"Example\"/>"
    let node = "<obj class=\"MListNode\" name=\"Node\"><string name=\"Name\" value=\"Track\"/></obj>"
    let device = "<obj class=\"MInstrumentTrack\" name=\"Track Device\"><member name=\"DeviceAttributes\">\(archiveSynth(plugin))</member></obj>"
    let attributes = "<member name=\"DeviceAttributes\">\(archiveSynth(plugin))</member>"
    var invalid = [
        plugin.replacingOccurrences(of: guid, with: ""), plugin.replacingOccurrences(of: guid, with: guid + guid),
        plugin.replacingOccurrences(of: name, with: ""), plugin.replacingOccurrences(of: name, with: name + name),
        plugin.replacingOccurrences(of: archiveUID, with: "not-a-guid"), archivePlugin(" "),
        archivePlugin(String(repeating: "X", count: 1_025)), archivePlugin(original: ""),
        plugin.replacingOccurrences(of: "<member name=\"Plugin UID\">", with: "<member name=\"Plugin UID\"/><member name=\"Plugin UID\">")
    ].map { archiveXML(archiveTrack(archiveSynth($0))) }
    invalid += [
        normal.replacingOccurrences(of: node, with: node + node),
        normal.replacingOccurrences(of: node, with: ""),
        normal.replacingOccurrences(of: device, with: device + device),
        normal.replacingOccurrences(of: attributes, with: attributes + attributes),
        archiveTrack(archiveSynth(plugin + plugin)),
        archiveTrack(archiveSynth(plugin) + archiveSynth(plugin)),
        archiveTrack(archiveInserts("<item>\(plugin)\(plugin)</item>")),
        archiveTrack(archiveInserts("<item>\(plugin)</item>") + archiveInserts("")),
    ].map { archiveXML($0) }
    for data in invalid { #expect(throws: (any Error).self) { try CubaseTrackArchiveReader.parse(data) } }
}

@Test func archiveRejectsMalformedXMLNamespacesAndResourceExhaustion() {
    let valid = archiveXML(archiveTrack(archiveSynth(archivePlugin())))
    let text = String(data: valid, encoding: .utf8)!
    let invalid = [Data(), Data([0xff]), Data(text.dropLast().utf8),
                   Data(("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>" + text).utf8),
                   Data(text.replacingOccurrences(of: "tracklist2", with: "other").utf8),
                   Data(("<!DOCTYPE tracklist2 [<!ENTITY x 'Example'>]>" + text).utf8),
                   Data(text.replacingOccurrences(of: "<tracklist2>", with: "<tracklist2 xmlns=\"urn:other\">").utf8),
                   Data(text.replacingOccurrences(of: "name=\"Plugin\"", with: "name=\"Plugin\" xmlns=\"urn:other\"").utf8),
                   Data("<tracklist2><list name=\"track\" type=\"obj\"/><list name=\"track\" type=\"obj\"/></tracklist2>".utf8),
                   archiveXML("", extra: String(repeating: "<x>", count: 65) + String(repeating: "</x>", count: 65)),
                   archiveXML("", extra: String(repeating: "<x/>", count: CubaseTrackArchiveReader.maximumElements)),
                   archiveXML(String(repeating: "<obj class=\"Other\"/>", count: CubaseTrackArchiveReader.maximumTracks + 1)),
                   archiveXML(archiveTrack(archiveInserts(String(repeating: "<item>\(archivePlugin())</item>", count: CubaseTrackArchiveReader.maximumReferences + 1)))),
                   Data(repeating: 32, count: CubaseTrackArchiveReader.maximumInputBytes + 1)]
    for data in invalid { #expect(throws: (any Error).self) { try CubaseTrackArchiveReader.parse(data) } }
}

@Test func archiveFileInspectionStaysSeparateFromCatalogInput() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".work/scratch/archive-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("export.xml"), link = root.appendingPathComponent("link.xml")
    let bytes = archiveXML(archiveTrack(archiveSynth(archivePlugin())))
    try bytes.write(to: file)
    #expect(try CubaseTrackArchiveReader.inspect(file).tracks[0].plugins.count == 1)
    #expect(try Data(contentsOf: file) == bytes)
    #expect(ProjectReader.read(file).coverage == "unsupported")
    #expect(ProjectReader.read(file).references.isEmpty)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    #expect(throws: (any Error).self) { try CubaseTrackArchiveReader.inspect(link) }
    let linkedRoot = root.appendingPathComponent("linked")
    try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: root)
    #expect(throws: (any Error).self) { try CubaseTrackArchiveReader.inspect(linkedRoot.appendingPathComponent("export.xml")) }
    #expect(throws: (any Error).self) { try CubaseTrackArchiveReader.inspect(root) }
    #expect(throws: (any Error).self) { try CubaseTrackArchiveReader.inspect(root.appendingPathComponent("missing")) }
}

private func archiveGroup(_ inserts: String, markers: String = "<int name=\"Type\" value=\"2\"/><string name=\"IDString\" value=\"GroupChannel\"/>", name: String = "Group") -> String {
    archiveTrack(inserts + markers, name: name, instrument: false)
        .replacingOccurrences(of: "MAudioTrackEvent", with: "MDeviceTrackEvent")
        .replacingOccurrences(of: "MAudioTrack", with: "MTrack")
}

@Test func archiveGroupUsesDirectSignatureAndRetainsBypassedDisabledReferences() throws {
    let insert = archiveInserts("<item>\(archivePlugin("Group EQ"))</item>")
        .replacingOccurrences(of: "<member name=\"InsertFolder\">", with: "<member name=\"InsertFolder\"><int name=\"Bypass\" value=\"1\"/>")
    let group = archiveGroup(insert + archiveSynth(archivePlugin("Not a group synth")))
    // This direct additional attribute appeared in the disabled host control.
    // Its semantics are not interpreted; saved references must remain intact.
    let disabled = archiveTrack(archiveSynth(archivePlugin("Disabled synth"))).replacingOccurrences(of: "<obj class=\"MInstrumentTrackEvent\">", with: "<obj class=\"MInstrumentTrackEvent\"><member name=\"Additional Attributes\"><int name=\"tion\" value=\"1\"/></member>")
    let report = try CubaseTrackArchiveReader.parse(archiveXML(group + disabled))
    #expect(report.adapterVersion == 2)
    #expect(report.tracks.map(\.name) == ["Group", "Track"])
    #expect(report.tracks.flatMap(\.plugins).map(\.name) == ["Group EQ", "Disabled synth"])
    #expect(report.tracks[0].plugins[0].role == "insert")
    #expect(report.limitations.contains { $0.contains("Output-channel inserts") && $0.contains("incomplete") })
}

@Test func archiveUnknownGroupSignaturesCannotLeakReferencesOrOwnerState() throws {
    let insert = archiveInserts("<item>\(archivePlugin("Excluded"))</item>")
    let known = archiveTrack(archiveSynth(archivePlugin("Known")))
    let markers = "<int name=\"Type\" value=\"2\"/><string name=\"IDString\" value=\"GroupChannel\"/>"
    for unsupported in ["", markers.replacingOccurrences(of: "value=\"2\"", with: "value=\"3\""),
                        markers.replacingOccurrences(of: "GroupChannel", with: "OutputChannel"),
                        "<member name=\"Nested\">\(markers)</member>"] {
        // Missing name on an unsupported provisional owner does not make it supported.
        let unknown = archiveGroup(insert, markers: unsupported).replacingOccurrences(of: "<string name=\"Name\" value=\"Group\"/>", with: "")
        let report = try CubaseTrackArchiveReader.parse(archiveXML(known + unknown + known))
        #expect(report.tracks.map(\.ordinal) == [0, 2])
        #expect(report.tracks.flatMap(\.plugins).map(\.name) == ["Known", "Known"])
        #expect(report.unsupportedTrackCount == 1)
    }
    for duplicate in [markers + markers,
                      markers + "<int name=\"Type\" value=\"2\"/>",
                      markers + "<string name=\"IDString\" value=\"GroupChannel\"/>"] {
        #expect(throws: (any Error).self) { try CubaseTrackArchiveReader.parse(archiveXML(archiveGroup(insert, markers: duplicate))) }
    }
    let many = archiveInserts(String(repeating: "<item>\(archivePlugin())</item>", count: CubaseTrackArchiveReader.maximumReferences))
    // Discarded provisional records must still consume the document's global budget.
    #expect(throws: (any Error).self) {
        try CubaseTrackArchiveReader.parse(archiveXML(archiveGroup(many, markers: "") + known))
    }
}
