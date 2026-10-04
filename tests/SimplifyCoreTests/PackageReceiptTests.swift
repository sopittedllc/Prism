import Foundation
import Darwin
import Testing
@testable import SimplifyCore

final class ReceiptFixture: @unchecked Sendable {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".work/scratch/receipt-" + UUID().uuidString)
    var bundle: URL { root.appendingPathComponent("Unit.component") }
    var info: URL { bundle.appendingPathComponent("Contents/Info.plist") }
    var executable: URL { bundle.appendingPathComponent("Contents/MacOS/Unit") }
    let now = Date(timeIntervalSince1970: 1_000)
    var receipt: [String: Any] {
        ["pkgid": "pkg.independent", "pkg-version": "2.1", "install-time": 500,
         "receipt-plist-version": 1.0, "volume": "/", "install-location": root.path]
    }
    var files: Data { Data("Unit.component/Contents/Info.plist\nUnit.component/Contents/MacOS/Unit\n".utf8) }
    init() throws {
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic non-executable content".utf8).write(to: executable)
        try writeInfo()
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func writeInfo(version: String = "2.1") throws {
        let plist = ["CFBundleIdentifier": "dev.example.instrument", "CFBundleExecutable": "Unit",
                     "CFBundleShortVersionString": version, "CFBundleVersion": "21"]
        try data(plist).write(to: info)
    }
    func data(_ value: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    }
    func observe(receipt: [String: Any]? = nil, files: Data? = nil) throws -> PackageReceiptReader.Observation {
        let metadata = try data(receipt ?? self.receipt)
        return try PackageReceiptReader.observe(packageID: "pkg.independent", bundle: bundle, observedAt: now) { args, _ in
            args[0] == "--files" ? (files ?? self.files) : metadata
        }
    }
    func inspect(receipt: [String: Any]? = nil, files: Data? = nil, bundle: URL? = nil) throws -> PackageReceiptReport {
        let metadata = try data(receipt ?? self.receipt)
        return try PackageReceiptReader.inspect(packageID: "pkg.independent", bundle: bundle ?? self.bundle, observedAt: now) { args, _ in
            args[0] == "--files" ? (files ?? self.files) : metadata
        }
    }
}

@Test func installerRecordRequiresExactPathsAndVersionsButIndependentPackageIdentity() throws {
    let f = try ReceiptFixture()
    let report = try f.inspect()
    #expect(report.status == .associated && report.matchedVersion == "2.1")
    #expect(report.packageID != report.bundleIdentifier)
    #expect(report.receiptDate == Date(timeIntervalSince1970: 500))
    #expect(report.limitations.contains { $0.contains("not original Date added or Last used") })
    var receipt = f.receipt; receipt["pkg-version"] = "2.1.0"
    #expect(try f.inspect(receipt: receipt).status == .versionMismatch)
    receipt["pkg-version"] = "21"
    #expect(try f.inspect(receipt: receipt).matchedVersion == "21")
    for missing in ["", "Unit.component/Contents/Info.plist\n", "Unit.component/Contents/MacOS/Unit\n",
                    "unit.component/Contents/Info.plist\nUnit.component/Contents/MacOS/Unit\n"] {
        let result = try f.inspect(files: Data(missing.utf8))
        #expect(result.status == .notListed && result.matchedVersion == nil)
    }
    receipt["pkg-version"] = "unmatched"
    #expect(try f.inspect(receipt: receipt, files: Data()).status == .notListed)
}

@Test func installerRecordRejectsTraversalAmbiguousPathsAndWrongVolumes() throws {
    let f = try ReceiptFixture()
    for bad in ["/absolute", "../outside", "a/../b", "./a", "a//b", "a/", "a\\b", "a\r", "a\t", "a\0", "a\n\n"] {
        #expect(throws: PackageReceiptError.self) { try f.inspect(files: Data(bad.utf8)) }
    }
    for location in ["//", "../outside", "/a/../b", "/a//b", "/a\\b"] {
        var value = f.receipt; value["install-location"] = location
        #expect(throws: PackageReceiptError.self) { try f.inspect(receipt: value) }
    }
    var value = f.receipt; value["volume"] = "/Volumes/Unavailable"
    #expect(throws: PackageReceiptError.self) { try f.inspect(receipt: value) }
    for root in ["", "/"] {
        value = f.receipt; value["install-location"] = root
        let files = f.files.split(separator: 10).map { String(f.root.path.dropFirst()) + "/" + String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
        #expect(try f.inspect(receipt: value, files: Data(files.utf8)).status == .associated)
    }
}

@Test func installerRecordRejectsUntrustedTypesDatesAndIDs() throws {
    let f = try ReceiptFixture()
    for timestamp: Any in [true, "500", -1, 0, 1_001, 500.5] {
        var value = f.receipt; value["install-time"] = timestamp
        #expect(throws: PackageReceiptError.self) { try f.inspect(receipt: value) }
    }
    for (key, invalid): (String, Any) in [("pkgid", "other"), ("pkg-version", ""), ("pkg-version", 21),
                                          ("receipt-plist-version", true), ("receipt-plist-version", 2), ("volume", false)] {
        var value = f.receipt; value[key] = invalid
        #expect(throws: PackageReceiptError.self) { try f.inspect(receipt: value) }
    }
    for id in ["", "-option", "bad\0id", String(repeating: "a", count: 1_025)] {
        #expect(throws: PackageReceiptError.self) {
            try PackageReceiptReader.inspect(packageID: id, bundle: f.bundle, observedAt: f.now) { _, _ in Issue.record("Invalid ID reached acquisition"); return Data() }
        }
    }
    #expect(throws: PackageReceiptError.self) {
        try PackageReceiptReader.inspect(packageID: "pkg.independent", bundle: f.bundle, observedAt: Date(timeIntervalSince1970: .nan)) { _, _ in Data() }
    }
}

@Test func installerRecordEnforcesBoundsAndUTF8() throws {
    let f = try ReceiptFixture()
    for files in [Data([0xff]), Data(repeating: 65, count: PackageReceiptReader.filesLimit + 1),
                  Data(String(repeating: "x\n", count: 100_001).utf8), Data(String(repeating: "x", count: 4_097).utf8)] {
        #expect(throws: PackageReceiptError.self) { try f.inspect(files: files) }
    }
    #expect(throws: PackageReceiptError.self) {
        try PackageReceiptReader.inspect(packageID: "pkg.independent", bundle: f.bundle, observedAt: f.now) { _, _ in
            Data(repeating: 65, count: PackageReceiptReader.infoLimit + 1)
        }
    }
    #expect(try f.inspect(files: Data(String(repeating: "x\n", count: 100_000).utf8)).status == .notListed)
}

@Test func installerRecordRejectsChangedReceiptOrBundleDuringAcquisition() throws {
    let f = try ReceiptFixture()
    var calls = 0
    #expect(throws: PackageReceiptError.self) {
        try PackageReceiptReader.inspect(packageID: "pkg.independent", bundle: f.bundle, observedAt: f.now) { args, _ in
            calls += 1
            if args[0] == "--files" { return f.files }
            var value = f.receipt; if calls > 1 { value["install-time"] = 600 }
            return try f.data(value)
        }
    }
    #expect(throws: PackageReceiptError.self) {
        try PackageReceiptReader.inspect(packageID: "pkg.independent", bundle: f.bundle, observedAt: f.now) { args, _ in
            if args[0] == "--files" { try f.writeInfo(version: "changed"); return f.files }
            return try f.data(f.receipt)
        }
    }
}

@Test func installerRecordRejectsLinkedMissingSpecialAndHelperBundles() throws {
    let f = try ReceiptFixture()
    let linked = f.root.appendingPathComponent("Linked.component")
    try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: f.bundle)
    #expect(throws: PackageReceiptError.self) { try f.inspect(bundle: linked) }
    #expect(throws: PackageReceiptError.self) { try f.inspect(bundle: f.bundle.appendingPathComponent("Contents/Helper.bundle")) }
    try FileManager.default.removeItem(at: f.executable)
    #expect(throws: PackageReceiptError.self) { try f.inspect() }
    #expect(mkfifo(f.executable.path, 0o600) == 0)
    #expect(throws: PackageReceiptError.self) { try f.inspect() }
    try FileManager.default.removeItem(at: f.executable)
    try FileManager.default.createSymbolicLink(at: f.executable, withDestinationURL: f.info)
    #expect(throws: PackageReceiptError.self) { try f.inspect() }
}

@Test func boundedReceiptCommandsReturnOutputAndRejectFailureOrExcess() throws {
    #expect(try BoundedCommand.read("/usr/bin/printf", arguments: ["receipt"], limit: 7) == Data("receipt".utf8))
    #expect(throws: BoundedCommandError.nonzeroExit) { try BoundedCommand.read("/usr/bin/false", arguments: [], limit: 32) }
    #expect(throws: BoundedCommandError.outputTooLarge) { try BoundedCommand.read("/usr/bin/yes", arguments: [], limit: 32) }
    #expect(throws: BoundedCommandError.launchFailed) { try BoundedCommand.read("/nonexistent/prism-command", arguments: [], limit: 32) }
}

@Test func boundedReceiptCommandsHandleTimeoutIgnoredTerminationAndEarlyEOF() throws {
    for script in ["exec /bin/sleep 2", "trap '' TERM; exec /bin/sleep 2", "exec 1>&-; exec /bin/sleep 2"] {
        let start = ProcessInfo.processInfo.systemUptime
        #expect(throws: BoundedCommandError.timeout) {
            try BoundedCommand.read("/bin/sh", arguments: ["-c", script], limit: 32, seconds: 0.1)
        }
        #expect(ProcessInfo.processInfo.systemUptime - start < 1.5)
    }
}
