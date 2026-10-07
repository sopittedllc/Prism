import Darwin
import Foundation
import Testing
@testable import SimplifyCore

// Run each memory test alone with PRISM_PROJECT_MEMORY_RUNTIME=1 to keep other tests' allocations
// out of the process high-water mark. The fixture is capped at 192 MiB on disk.
@Test func projectScanMemoryReleasesFileBuffersBetweenProjects() throws {
    guard ProcessInfo.processInfo.environment["PRISM_PROJECT_MEMORY_RUNTIME"] == "1" else { return }
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/SimplifyTests/prism-memory-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try autoreleasepool {
        let data = Data(repeating: 0, count: 8 * 1024 * 1024)
        for index in 0..<24 {
            try data.write(to: root.appendingPathComponent("Malformed-\(index).cpr"))
        }
    }
    var before = rusage()
    #expect(getrusage(RUSAGE_SELF, &before) == 0)
    // Simulate one long-lived worker pool, so success cannot depend on the
    // caller's thread/run-loop draining Foundation temporaries for us.
    let report = autoreleasepool {
        var request = ScanRequest(); request.projects = [root]; request.completeProjectScan = true
        return Scanner().scan(request, scannedKinds: [.sample])
    }
    var after = rusage()
    #expect(getrusage(RUSAGE_SELF, &after) == 0)
    let growth = after.ru_maxrss - before.ru_maxrss
    print("Project scan memory: peak growth \(growth) bytes; peak \(after.ru_maxrss) bytes; 24 x 8 MiB inputs")
    #expect(report.projects.count == 24)
    #expect(report.projects.allSatisfy { $0.coverage == "failed" })
    #expect(growth < 96 * 1024 * 1024)
}

@Test func projectScanMemoryAbletonPreflight() throws {
    guard ProcessInfo.processInfo.environment["PRISM_PROJECT_MEMORY_RUNTIME"] == "1" else { return }
    let xml = Data(("<Ableton><Name Value=\"Café 🎹\"/><Opaque>" + String(repeating: "0123456789ABCDEF", count: 262_144) + "</Opaque></Ableton>").utf8)
    var before = rusage()
    #expect(getrusage(RUSAGE_SELF, &before) == 0)
    let references = try autoreleasepool { try ProjectReader.parseAbleton(xml) }
    #expect(references.isEmpty)
    var after = rusage()
    #expect(getrusage(RUSAGE_SELF, &after) == 0)
    let growth = after.ru_maxrss - before.ru_maxrss
    print("Ableton preflight memory: peak growth \(growth) bytes; peak \(after.ru_maxrss) bytes; 4 MiB XML")
    #expect(growth < 32 * 1024 * 1024)
}

@Test func projectScanMemoryPreflightPreservesUTF8AndDTDRejection() throws {
    let valid = Data("<Ableton><SampleRef><FileRef><Name Value=\"Café 🎹.wav\"/></FileRef></SampleRef></Ableton>".utf8)
    #expect(try ProjectReader.parseAbleton(valid).first?.value == "Café 🎹.wav")
    // Even in a comment, mixed-case tokens retain the reader's conservative
    // rejection policy. Place them beyond the initial XML header as well.
    for token in ["<!DOCTYPE", "<!doctype", "<!DoCtYpE"] {
        let input = Data(("<Ableton><!--" + String(repeating: "x", count: 4096) + token + "--></Ableton>").utf8)
        #expect(throws: ProjectReadError.self) { try ProjectReader.parseAbleton(input) }
    }
    #expect(throws: ProjectReadError.self) {
        try ProjectReader.parseAbleton(Data("<Ableton>".utf8) + Data([0xff]) + Data("</Ableton>".utf8))
    }
    #expect(throws: ProjectReadError.self) {
        try ProjectReader.parseAbleton(Data("<!DOCTYPE Ableton [<!ENTITY x 'expanded'>]><Ableton>&x;</Ableton>".utf8))
    }
}

@Test func projectScanMemoryBackupPrefixPreservesGzipDetection() throws {
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/SimplifyTests/prism-backup-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    // gzip of a synthetic Ableton document containing one /fixture.wav reference.
    let gzip = try #require(Data(base64Encoded: "H4sIAAAAAAAC/7NxTMpJLcnPs7MJTswtyEkNSk2zs3HLhDICEksyFMISc0pTbZX00zIrSkqLUvXKE8uU9O1s9OGq9JG06sPMAwC4rh9VWQAAAA=="))
    let project = root.appendingPathComponent("Song.als")
    let backup = root.appendingPathComponent("Song.als.bak")
    try gzip.write(to: project); try gzip.write(to: backup)
    let original = ProjectReader.read(project), copy = ProjectReader.read(backup)
    #expect(original.coverage == "partial" && copy.coverage == "partial")
    #expect(original.references.count == 1 && copy.references.count == 1)
    #expect(copy.references.first?.value == original.references.first?.value)
    #expect(copy.sourceSHA256 == original.sourceSHA256)
}

@Test func projectScanMemoryAbletonBatchPreservesReferencesAcrossOverlappingRoots() throws {
    guard ProcessInfo.processInfo.environment["PRISM_PROJECT_MEMORY_RUNTIME"] == "1" else { return }
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/SimplifyTests/prism-als-memory-" + UUID().uuidString)
    let child = root.appendingPathComponent("Projects")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try autoreleasepool {
        let xml = Data(("<Ableton><Name Value=\"Café 🎹\"/><Opaque>" + String(repeating: "0123456789ABCDEF", count: 262_144)
            + "</Opaque><SampleRef><FileRef><Name Value=\"Fixture.wav\"/></FileRef></SampleRef></Ableton>").utf8)
        for index in 0..<24 { try xml.write(to: child.appendingPathComponent("Song-\(index).als")) }
        try Data([0]).write(to: child.appendingPathComponent("Unrelated.wav"))
    }
    var before = rusage()
    #expect(getrusage(RUSAGE_SELF, &before) == 0)
    let report = autoreleasepool {
        var request = ScanRequest(); request.projects = [child, root, root]; request.maximumEntries = 1
        return Scanner().scan(request, scannedKinds: [.sample])
    }
    var after = rusage()
    #expect(getrusage(RUSAGE_SELF, &after) == 0)
    let growth = after.ru_maxrss - before.ru_maxrss
    print("Ableton batch memory: peak growth \(growth) bytes; peak \(after.ru_maxrss) bytes; 24 x 4 MiB XML")
    #expect(report.projects.count == 24)
    #expect(report.issues.isEmpty)
    #expect(report.projects.allSatisfy { $0.coverage == "partial" && $0.references.count == 1 && $0.references.first?.value == "Fixture.wav" })
    #expect(growth < 64 * 1024 * 1024)
}
