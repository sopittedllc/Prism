import Foundation
import Testing
@testable import SimplifyCore

private func liveDocument(_ body: String, major: String = "5", minor: String = "12.0_12402", creator: String = "Ableton Live 12.4.5") -> Data {
    Data("<Ableton MajorVersion=\"\(major)\" MinorVersion=\"\(minor)\" Creator=\"\(creator)\"><LiveSet>\(body)</LiveSet></Ableton>".utf8)
}
private func liveTrack(_ devices: String, type: String = "MidiTrack") -> String {
    "<Tracks><\(type)><DeviceChain><DeviceChain><Devices>\(devices)</Devices></DeviceChain></DeviceChain></\(type)></Tracks>"
}
private func livePlugin(_ name: String, extra: String = "") -> String {
    "<PluginDevice><PluginDesc><Vst3PluginInfo><Name Value=\"\(name)\"/>\(extra)</Vst3PluginInfo></PluginDesc></PluginDevice>"
}

@Test func liveVst3DescriptorsAreCandidatesEvenWhenBypassedOrMissing() throws {
    for track in ["AudioTrack", "MidiTrack", "ReturnTrack"] {
        let device = livePlugin("Example", extra: "<IsPlaceholderDevice Value=\"true\"/><Preset><Vst3Preset><IsOn Value=\"false\"/><Name Value=\"Wrong preset\"/></Vst3Preset></Preset>")
        let refs = try ProjectReader.parseAbleton(liveDocument(liveTrack(device + device, type: track)))
        #expect(refs.count == 2) // Preserve separate declarations, not unique display names.
        #expect(refs.allSatisfy { $0.kind == .plugin && $0.value == "Example" && $0.resolvedPath == nil })
        #expect(refs.allSatisfy { $0.evidence.contains("candidate") && $0.evidence.contains("successful load unverified") })
    }
}

@Test func liveVst3IgnoresNamesOutsideProvenTrackRoute() throws {
    let plugin = livePlugin("Decoy")
    for body in [plugin, "<Browser>\(liveTrack(plugin))</Browser>",
                 "<UndoHistory>\(liveTrack(plugin))</UndoHistory>",
                 liveTrack("<Rack><Devices>\(plugin)</Devices></Rack>"),
                 liveTrack(plugin, type: "MasterTrack"),
                 "<Tracks><MidiTrack><Name Value=\"Decoy\"/>\(plugin)</MidiTrack></Tracks>",
                 liveTrack("<PluginDevice><PluginDesc><Vst3PluginInfo><Preset><Name Value=\"Decoy\"/></Preset></Vst3PluginInfo></PluginDesc></PluginDevice>"),
                 liveTrack(livePlugin("") + livePlugin(" &#10; &#9; "))] {
        #expect(try ProjectReader.parseAbleton(liveDocument(body)).isEmpty)
    }
}

@Test func liveUnknownSchemaRetainsOnlyPriorSampleCandidates() throws {
    let body = liveTrack(livePlugin("Example")) + "<SampleRef><FileRef><Path Value=\"/candidate.wav\"/></FileRef></SampleRef>"
    for xml in [liveDocument(body, major: "6"), liveDocument(body, minor: "future"),
                liveDocument(body, creator: "Ableton Live 13.0"), liveDocument(body, creator: ""),
                Data("<Ableton><LiveSet>\(body)</LiveSet></Ableton>".utf8)] {
        let refs = try ProjectReader.parseAbleton(xml)
        #expect(refs.count == 1 && refs.first?.kind == .sample)
    }
}

@Test func liveDescriptorReaderRetainsDepthAndMalformedInputBounds() {
    let deeplyNested = liveDocument(String(repeating: "<N>", count: 129) + String(repeating: "</N>", count: 129))
    for xml in [deeplyNested, Data([0x1f, 0x8b, 0, 0]), Data("<Ableton><LiveSet>".utf8),
                Data(repeating: 32, count: ProjectReader.maximumInputBytes + 1)] {
        #expect(throws: (any Error).self) { try ProjectReader.parseAbleton(xml) }
    }
}
