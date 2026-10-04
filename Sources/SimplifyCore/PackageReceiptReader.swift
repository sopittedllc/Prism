import Foundation
import CoreFoundation
import Darwin

public enum PackageReceiptError: Error { case invalidReceipt, invalidPaths, unavailableBundle, changedDuringRead }
public enum PackageReceiptStatus: String, Codable, Sendable { case associated, notListed, versionMismatch }

/// A corroborated historical installer record, never proof of original addition or use.
/// Matching path/version cannot exclude skipped installs, restores or same-version replacement.
public struct PackageReceiptReport: Codable, Sendable {
    public let adapterVersion: Int
    public let status: PackageReceiptStatus
    public let packageID: String
    public let packageVersion: String
    public let receiptDate: Date
    public let observedAt: Date
    public let bundlePath: String
    public let bundleIdentifier: String
    public let bundleVersions: [String]
    public let matchedVersion: String?
    public let limitations: [String]
}

/// Read-only, synchronous and bounded. Call from a worker; no plugin is loaded or run.
/// Uses public pkgutil queries for one explicit receipt and one current bundle.
public enum PackageReceiptReader {
    static let infoLimit = 256 * 1024
    static let filesLimit = 4 * 1024 * 1024

    /// Opaque live verification snapshot. It cannot be restored from a serialized report.
    public struct Observation: Sendable {
        public let report: PackageReceiptReport
        fileprivate let snapshot: BundleInfo
        fileprivate init(report: PackageReceiptReport, snapshot: BundleInfo) {
            self.report = report; self.snapshot = snapshot
        }
        func revalidate() throws {
            let current = try PackageReceiptReader.readBundle(URL(fileURLWithPath: report.bundlePath))
            guard snapshot.stamps == current.stamps, snapshot.key == current.key else {
                throw PackageReceiptError.changedDuringRead
            }
        }
    }

    public static func inspect(packageID: String, bundle: URL, observedAt: Date = Date()) throws -> PackageReceiptReport {
        try observe(packageID: packageID, bundle: bundle, observedAt: observedAt).report
    }

    /// Acquire an immutable verification snapshot for later exact-installation binding.
    /// Synchronous bounded filesystem/process work; call outside UI/audio callbacks.
    public static func observe(packageID: String, bundle: URL, observedAt: Date = Date()) throws -> Observation {
        try observe(packageID: packageID, bundle: bundle, observedAt: observedAt) { args, limit in
            try BoundedCommand.read("/usr/sbin/pkgutil", arguments: args, limit: limit)
        }
    }

    // Injectable acquisition keeps command-failure and changing-input tests deterministic.
    static func inspect(packageID: String, bundle: URL, observedAt: Date,
                        acquire: ([String], Int) throws -> Data) throws -> PackageReceiptReport {
        try observe(packageID: packageID, bundle: bundle, observedAt: observedAt, acquire: acquire).report
    }
    static func observe(packageID: String, bundle: URL, observedAt: Date,
                        acquire: ([String], Int) throws -> Data) throws -> Observation {
        guard validText(packageID, limit: 1_024), !packageID.hasPrefix("-"),
              observedAt.timeIntervalSince1970.isFinite else { throw PackageReceiptError.invalidReceipt }
        let before = try readBundle(bundle)
        let first = try receipt(acquire(["--pkg-info-plist", packageID], infoLimit), expectedID: packageID, at: observedAt)
        let files = try paths(acquire(["--files", packageID], filesLimit))
        let second = try receipt(acquire(["--pkg-info-plist", packageID], infoLimit), expectedID: packageID, at: observedAt)
        let after = try readBundle(bundle)
        guard first.key == second.key, before.stamps == after.stamps,
              before.key == after.key else { throw PackageReceiptError.changedDuringRead }
        let required = [bundle.path + "/Contents/Info.plist", bundle.path + "/Contents/MacOS/" + before.executable]
        let fullPaths = Set(files.map { Data((first.location + "/" + $0).utf8) })
        let listed = required.allSatisfy { fullPaths.contains(Data($0.utf8)) }
        let matched = before.versions.first { $0.utf8.elementsEqual(first.version.utf8) }
        let report = PackageReceiptReport(adapterVersion: 1,
            status: !listed ? .notListed : (matched == nil ? .versionMismatch : .associated),
            packageID: packageID, packageVersion: first.version, receiptDate: first.date,
            observedAt: observedAt, bundlePath: bundle.path, bundleIdentifier: before.identifier,
            bundleVersions: before.versions, matchedVersion: listed ? matched : nil,
            limitations: ["Installer receipt time is not original Date added or Last used.",
                          "Path and version association does not prove when current bytes were installed; skipped installs, restores and replacements remain possible.",
                          "This report is not automatically attached to a catalog identity."])
        return Observation(report: report, snapshot: after)
    }

    struct Receipt {
        let id: String, version: String, location: String
        let date: Date
        var key: [Data] { [id, version, location, String(date.timeIntervalSince1970)].map { Data($0.utf8) } }
    }
    static func receipt(_ data: Data, expectedID: String, at observedAt: Date) throws -> Receipt {
        guard data.count <= infoLimit,
              let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let id = value["pkgid"] as? String, id.utf8.elementsEqual(expectedID.utf8),
              let version = value["pkg-version"] as? String, validText(version, limit: 1_024),
              let volume = value["volume"] as? String, volume == "/",
              let location = value["install-location"] as? String,
              let timestamp = number(value["install-time"]), timestamp > 0, timestamp.rounded(.towardZero) == timestamp,
              timestamp <= observedAt.timeIntervalSince1970,
              number(value["receipt-plist-version"]) == 1 else { throw PackageReceiptError.invalidReceipt }
        var relative = location
        if relative.hasPrefix("/") { relative.removeFirst() }
        if relative.hasSuffix("/") { relative.removeLast() }
        guard !relative.isEmpty || location.isEmpty || location == "/" else { throw PackageReceiptError.invalidPaths }
        if !relative.isEmpty { try validateRelativePath(relative) }
        return Receipt(id: id, version: version, location: relative.isEmpty ? "" : "/" + relative,
                       date: Date(timeIntervalSince1970: timestamp))
    }
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    static func paths(_ data: Data) throws -> [String] {
        guard data.count <= filesLimit, var text = String(data: data, encoding: .utf8) else { throw PackageReceiptError.invalidPaths }
        if text.hasSuffix("\n") { text.removeLast() }
        if text.isEmpty { return [] }
        let lines = text.components(separatedBy: "\n")
        guard lines.count <= 100_000 else { throw PackageReceiptError.invalidPaths }
        for line in lines { try validateRelativePath(line) }
        return lines
    }
    private static func validateRelativePath(_ value: String) throws {
        guard validText(value, limit: 4_096), !value.contains("\\"),
              value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw PackageReceiptError.invalidPaths
        }
    }
    private static func validText(_ value: String, limit: Int) -> Bool {
        value.utf8.prefix(limit + 1).count <= limit && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    struct BundleInfo: Sendable {
        let identifier: String, executable: String
        let versions: [String]
        let stamps: [FileStamp]
        var key: [Data] { ([identifier, executable] + versions).map { Data($0.utf8) } }
    }
    static func readBundle(_ url: URL) throws -> BundleInfo {
        guard url.isFileURL, url.path.utf8.elementsEqual(url.standardizedFileURL.path.utf8),
              ["component", "vst", "vst3", "aaxplugin", "clap"].contains(url.pathExtension.lowercased()),
              LibraryMetadataReader.safe(url) else { throw PackageReceiptError.unavailableBundle }
        let bundleStamp = try FileStamp(url, mode: S_IFDIR)
        let info = url.appendingPathComponent("Contents/Info.plist")
        guard LibraryMetadataReader.safe(info) else { throw PackageReceiptError.unavailableBundle }
        let infoStamp = try FileStamp(info, mode: S_IFREG)
        let data = try BoundedFile.read(info, limit: infoLimit)
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let id = plist["CFBundleIdentifier"] as? String, validText(id, limit: 1_024),
              let executable = plist["CFBundleExecutable"] as? String, validText(executable, limit: 1_024),
              !executable.contains("/"), !executable.contains("\\"), executable != ".", executable != ".." else { throw PackageReceiptError.unavailableBundle }
        var versions: [String] = []
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] where plist[key] != nil {
            guard let version = plist[key] as? String, validText(version, limit: 1_024) else { throw PackageReceiptError.unavailableBundle }
            versions.append(version)
        }
        guard !versions.isEmpty else { throw PackageReceiptError.unavailableBundle }
        let binary = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
        guard LibraryMetadataReader.safe(binary) else { throw PackageReceiptError.unavailableBundle }
        let executableStamp = try FileStamp(binary, mode: S_IFREG)
        guard try infoStamp == FileStamp(info, mode: S_IFREG) else { throw PackageReceiptError.changedDuringRead }
        return BundleInfo(identifier: id, executable: executable, versions: versions, stamps: [bundleStamp, infoStamp, executableStamp])
    }
    struct FileStamp: Equatable, Sendable {
        let device: Int32, inode: UInt64, size: Int64
        let times: [Int64]
        init(_ url: URL, mode: mode_t) throws {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == mode else { throw PackageReceiptError.unavailableBundle }
            device = info.st_dev; inode = info.st_ino; size = info.st_size
            times = [info.st_birthtimespec, info.st_mtimespec, info.st_ctimespec].flatMap { [Int64($0.tv_sec), Int64($0.tv_nsec)] }
        }
    }
}
