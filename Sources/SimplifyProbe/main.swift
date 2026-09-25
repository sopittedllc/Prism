import Foundation
import SimplifyCore

let help = """
Simplify read-only discovery prototype
Usage: simplify-probe [--standard-plugins] [--plugins DIR] [--samples DIR]
                          [--libraries DIR] [--projects DIR] [--metrics]
Repeat folder options for multiple roots. No arguments or --help performs no scan.
JSON includes local paths. Keep reports private. No files are changed and no plugins run.
Project readers are experimental and partial. Recency uses project modification time,
not exact use time. No references found never means safe to delete.
Exit: 0 = scan finished (project coverage may be partial), 2 = issues/partial scan,
      64 = invalid arguments, 1 = output error.
"""

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.count == 2, arguments[0] == "--inspect-project" {
    let report = ProjectReader.read(URL(fileURLWithPath: arguments[1]))
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    do {
        try FileHandle.standardOutput.write(contentsOf: encoder.encode(report) + Data([10]))
        exit(report.coverage == "partial" ? 0 : 2)
    } catch { exit(1) }
}
if arguments.isEmpty || arguments == ["--help"] { print(help); exit(0) }
final class ScanMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var first: Double?
    private var basic: Double?
    func record(_ update: InventorySnapshot) {
        lock.lock(); defer { lock.unlock() }
        if first == nil && !update.assets.isEmpty { first = update.elapsedSeconds }
        if update.discoveryComplete { basic = update.elapsedSeconds }
    }
    func output(_ report: ScanReport) -> [String: Double] {
        lock.lock(); defer { lock.unlock() }
        var result = ["durationSeconds": report.durationSeconds, "assets": Double(report.assets.count), "projects": Double(report.projects.count), "issues": Double(report.issues.count)]
        result["firstInventorySeconds"] = first; result["basicInventorySeconds"] = basic
        return result
    }
}
var metricsOnly = false
var request = ScanRequest()
var index = 0
while index < arguments.count {
    let flag = arguments[index]
    if flag == "--metrics" { metricsOnly = true; index += 1; continue }
    if flag == "--standard-plugins" {
        request.plugins.append(contentsOf: ScanRequest.standardPluginRoots)
        index += 1
        continue
    }
    guard ["--plugins", "--samples", "--libraries", "--projects"].contains(flag),
          index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--"),
          !arguments[index + 1].isEmpty else {
        FileHandle.standardError.write(Data(("Invalid option or missing folder: \(flag)\n" + help + "\n").utf8))
        exit(64)
    }
    let url = URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath).standardizedFileURL
    switch flag {
    case "--plugins": request.plugins.append(url)
    case "--samples": request.samples.append(url)
    case "--libraries": request.libraries.append(url)
    default: request.projects.append(url)
    }
    index += 2
}
let metrics = ScanMetrics()
let report = Scanner().scan(request, inventory: metricsOnly ? metrics.record : nil)
do {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try metricsOnly ? encoder.encode(metrics.output(report)) : encoder.encode(report)
    try FileHandle.standardOutput.write(contentsOf: data + Data([10]))
    exit(report.issues.isEmpty ? 0 : 2)
} catch {
    FileHandle.standardError.write(Data("Could not write report: \(error)\n".utf8))
    exit(1)
}
