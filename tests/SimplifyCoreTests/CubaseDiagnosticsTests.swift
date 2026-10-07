import CryptoKit
import Foundation
import Testing
@testable import SimplifyCore

// Synthetic token sequences, deliberately not represented as a complete CPR schema.
private func cprToken(_ text: String) -> Data {
    let bytes = Array(text.utf8) + [0]
    return Data([UInt8(bytes.count)] + bytes)
}
private func cprMetadata(_ version: String = "Version 15.0.30", app: String = "Cubase", rif2: Bool = true) -> Data {
    Data("PAppVersion\0".utf8) + Data(repeating: 0, count: rif2 ? 13 : 9)
        + cprToken(app) + Data(repeating: 0, count: 3) + cprToken(version)
}
private func cprRecord(_ name: String = "Example", uid: String = String(repeating: "A", count: 32), original: String? = nil) -> Data {
    var data = Data("Plugin UID\0".utf8) + Data(repeating: 0, count: 22) + cprToken(uid)
    data += Data(repeating: 0, count: 3) + cprToken("Plugin Name")
    data += Data(repeating: 0, count: 5) + cprToken(name) + Data(repeating: 0, count: 3)
    if let original {
        data += cprToken("Original Plugin Name") + Data(repeating: 0, count: 5) + cprToken(original)
    } else { data += cprToken("Next field") }
    return data
}
private func cprDocument(_ body: Data = Data(), rif2: Bool = true) -> Data {
    Data((rif2 ? "RIF2" : "RIFF").utf8) + cprMetadata(rif2: rif2) + body
}

@Test func cubaseDiagnosticPreservesDescriptorsAndProvenanceWithoutUsageClaims() throws {
    for rif2 in [true, false] {
        let header = cprDocument(rif2: rif2)
        let record = cprRecord("Renamed track", original: "Actual plugin")
        let input = header + record + record
        let report = try CubaseDiagnostics.parse(input)
        #expect(report.coverage == "diagnostic-only" && report.hostVersion == "15.0.30")
        #expect(report.adapterVersion == 1)
        #expect(report.descriptors.map(\.name) == ["Actual plugin", "Actual plugin"])
        #expect(report.descriptors.map(\.byteOffset) == [header.count, header.count + record.count])
        #expect(report.inputSHA256 == SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined())
        #expect(report.limitations.contains { $0.contains("current ownership") })
        #expect(report.limitations.contains { $0.contains("No usage timestamp") })
    }
}

@Test func cubaseLabelsAreIgnoredButOpaqueTypedDecoysRemainExplicitlyUnresolved() throws {
    let labels = Data("Diva 01\0OwnInputBus\0Diva\0RecorderBus\0Diva 01\0".utf8)
    #expect(try CubaseDiagnostics.parse(cprDocument(labels)).descriptors.isEmpty)
    let opaque = Data("Opaque plugin state begin".utf8) + cprRecord("Decoy") + Data("state end".utf8)
    let report = try CubaseDiagnostics.parse(cprDocument(labels + opaque))
    #expect(report.descriptors.map(\.name) == ["Decoy"])
    #expect(report.coverage == "diagnostic-only")
    #expect(report.limitations.contains { $0.contains("opaque state") })
    // Diagnostic data has no ProjectReference, last-used or resolved-asset field.
    let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
    #expect(json["references"] == nil && json["lastUsed"] == nil && json["resolvedPath"] == nil)
}

@Test func cubaseMetadataMustBeUnambiguousAndSupported() {
    for input in [Data(), Data("NOPE".utf8) + cprMetadata(), Data("RIF2".utf8),
                  Data("RIF2".utf8) + cprMetadata("Version 15.0.31"),
                  Data("RIF2".utf8) + cprMetadata(app: "Nuendo"),
                  cprDocument() + cprMetadata(), cprDocument() + cprMetadata("Version 14.0"),
                  Data(cprDocument().dropLast(2))] {
        #expect(throws: (any Error).self) { try CubaseDiagnostics.parse(input) }
    }
}

@Test func cubaseRejectsMalformedTokensAndDoesNotSalvagePartialOutput() {
    for bad in [cprRecord(""), cprRecord(" \t"), cprRecord(uid: "123"),
                cprRecord(uid: String(repeating: "Z", count: 32)), cprRecord(original: ""),
                Data("Plugin UID\0".utf8)] {
        #expect(throws: (any Error).self) { try CubaseDiagnostics.parse(cprDocument(cprRecord() + bad)) }
    }
    let record = cprRecord()
    for length in 1..<record.count {
        #expect(throws: (any Error).self) {
            try CubaseDiagnostics.parse(cprDocument(Data(record.prefix(max(11, length)))))
        }
    }
    var invalidUTF8 = cprRecord()
    let range = invalidUTF8.range(of: Data("Example".utf8))!
    invalidUTF8[range.lowerBound] = 0xff
    #expect(throws: (any Error).self) { try CubaseDiagnostics.parse(cprDocument(invalidUTF8)) }
    var wrongKey = cprRecord()
    let keyRange = wrongKey.range(of: Data("Plugin Name".utf8))!
    wrongKey[keyRange.lowerBound] = 88
    #expect(throws: (any Error).self) { try CubaseDiagnostics.parse(cprDocument(wrongKey)) }
}

@Test func cubaseDiagnosticBudgetsAreEnforced() throws {
    let record = cprRecord()
    var input = cprDocument()
    for _ in 0..<CubaseDiagnostics.maximumRecords { input += record }
    #expect(try CubaseDiagnostics.parse(input).descriptors.count == CubaseDiagnostics.maximumRecords)
    input += record
    #expect(throws: CubaseDiagnosticError.tooManyRecords) { try CubaseDiagnostics.parse(input) }
    #expect(throws: ProjectReadError.tooLarge) {
        try CubaseDiagnostics.parse(Data(repeating: 0, count: CubaseDiagnostics.maximumInputBytes + 1))
    }
}

@Test func cubaseFileInspectionIsReadOnlyAndMalformedProjectIsNotAdmitted() throws {
    // Keep fixtures in the workspace; system temporary URLs may traverse /var.
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".work/scratch/cubase-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("test.cpr")
    let input = cprDocument(cprRecord())
    try input.write(to: file)
    let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    #expect(try CubaseDiagnostics.inspect(file).descriptors.count == 1)
    #expect(try Data(contentsOf: file) == input)
    #expect(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
    let normal = ProjectReader.read(file)
    #expect(normal.coverage == "failed" && normal.references.isEmpty && normal.kontaktStates == nil)
    let link = root.appendingPathComponent("link.cpr")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    #expect(throws: (any Error).self) { try CubaseDiagnostics.inspect(link) }
    let directoryLink = root.appendingPathComponent("linked-directory")
    try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: root)
    #expect(throws: (any Error).self) { try CubaseDiagnostics.inspect(directoryLink.appendingPathComponent("test.cpr")) }
    #expect(throws: (any Error).self) { try CubaseDiagnostics.inspect(root) }
    #expect(throws: (any Error).self) { try CubaseDiagnostics.inspect(root.appendingPathComponent("missing.cpr")) }
}
