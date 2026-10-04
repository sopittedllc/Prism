import Foundation

/// Coverage of one bounded corroboration pass, never complete installation history.
public struct PackageReceiptCollection: Sendable {
    public enum Status: String, Sendable { case complete, incomplete, cancelled }
    public let status: Status
    public let commands: Int
    /// Index file-list queries; fresh verification queries are included in commands instead.
    public let payloadQueries: Int
    public let attempted: Int
    /// Successful bindings, including idempotent replays.
    public let recorded: Int
    /// Failed package/bundle operations, not distinct products or commands.
    public let failures: Int
}

/// Local receipt discovery with no vendor-name guesses or private database access.
/// Worker owns transient buffers; only qualified evidence reaches CatalogStore.
public enum PackageReceiptCollector {
    typealias Acquire = @Sendable ([String], Int, Double) throws -> Data
    struct Limits: Sendable {
        var assets = 2_048, packages = 4_096, payloads = 512, observations = 256
        var bytes = 64 * 1024 * 1024
        var seconds = 120.0
    }
    private enum Stop: Error { case budget }

    /// Runs off the caller's actor. Cancellation propagates to command polling and
    /// queued catalog writes. Existing evidence is retained on failure/cancellation.
    public static func collect(assets: [Asset], store: CatalogStore) async -> PackageReceiptCollection {
        await collect(assets: assets, store: store, limits: Limits()) { args, limit, seconds in
            try BoundedCommand.read("/usr/sbin/pkgutil", arguments: args, limit: limit,
                                    seconds: seconds, rejectDiagnostics: true)
        }
    }
    static func collect(assets: [Asset], store: CatalogStore, limits: Limits,
                        acquire: @escaping Acquire) async -> PackageReceiptCollection {
        let worker = Task.detached(priority: .utility) {
            await run(assets: assets, store: store, limits: limits, acquire: acquire)
        }
        return await withTaskCancellationHandler(operation: {
            if Task.isCancelled { worker.cancel() }
            return await worker.value
        }, onCancel: { worker.cancel() })
    }

    private static func run(assets: [Asset], store: CatalogStore, limits: Limits,
                            acquire: Acquire) async -> PackageReceiptCollection {
        let deadline = ProcessInfo.processInfo.systemUptime + limits.seconds
        var bytes = 0, commands = 0, payloads = 0, attempted = 0, recorded = 0, failures = 0
        func summary(_ status: PackageReceiptCollection.Status) -> PackageReceiptCollection {
            PackageReceiptCollection(status: status, commands: commands, payloadQueries: payloads,
                                     attempted: attempted, recorded: recorded, failures: failures)
        }
        func check() throws {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Stop.budget }
        }
        func query(_ args: [String], _ limit: Int) throws -> Data {
            try check()
            guard bytes < limits.bytes else { throw Stop.budget }
            let remaining = min(limit, limits.bytes - bytes)
            commands += 1
            bytes += remaining // Charge the full allowance if acquisition fails.
            let output = try acquire(args, remaining, min(5, deadline - ProcessInfo.processInfo.systemUptime))
            guard output.count <= remaining else { throw Stop.budget }
            bytes -= remaining - output.count
            try check()
            return output
        }
        do {
            try check()
            guard assets.count <= limits.assets else { throw Stop.budget }
            var bundles: [(asset: Asset, info: PackageReceiptReader.BundleInfo)] = []
            var seen = Set<Data>()
            for asset in assets.sorted(by: { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) })
                where asset.kind == .plugin && asset.catalogStale != true && asset.catalogID != nil {
                try check()
                guard seen.insert(Data(asset.path.utf8)).inserted else { continue }
                do { bundles.append((asset, try PackageReceiptReader.readBundle(URL(fileURLWithPath: asset.path)))) }
                catch { failures += 1 }
            }
            guard !bundles.isEmpty else { return summary(failures == 0 ? .complete : .incomplete) }
            let ids = try packageIDs(query(["--pkgs-plist"], 1_048_576), maximum: limits.packages)
            for start in stride(from: 0, to: ids.count, by: 32) {
                try check()
                let batch = Array(ids[start..<min(start + 32, ids.count)])
                let documents: [Data]
                do { documents = try metadataDocuments(query(batch.flatMap { ["--pkg-info-plist", $0] }, 262_144), count: batch.count) }
                catch is CancellationError { throw CancellationError() }
                catch is Stop { throw Stop.budget }
                catch { failures += batch.count; continue }
                // Validate the whole batch's IDs before accepting any of its contents.
                var receipts: [PackageReceiptReader.Receipt] = []
                do {
                    for (id, data) in zip(batch, documents) {
                        receipts.append(try PackageReceiptReader.receipt(data, expectedID: id, at: Date()))
                    }
                } catch { failures += batch.count; continue }
                for receipt in receipts {
                    try check()
                    let candidates = bundles.filter { item in
                        let prefix = receipt.location + "/"
                        return item.asset.path.utf8.starts(with: prefix.utf8)
                            && item.info.versions.contains(where: { $0.utf8.elementsEqual(receipt.version.utf8) })
                    }
                    guard !candidates.isEmpty else { continue }
                    guard payloads < limits.payloads else { throw Stop.budget }
                    payloads += 1
                    do {
                        let paths = try PackageReceiptReader.paths(query(["--files", receipt.id], PackageReceiptReader.filesLimit))
                        let absolute = Set(paths.map { Data((receipt.location + "/" + $0).utf8) })
                        for candidate in candidates {
                            let required = [candidate.asset.path + "/Contents/Info.plist",
                                            candidate.asset.path + "/Contents/MacOS/" + candidate.info.executable]
                            guard required.allSatisfy({ absolute.contains(Data($0.utf8)) }) else { continue }
                            try check()
                            guard attempted < limits.observations else { throw Stop.budget }
                            attempted += 1
                            do {
                                let observation = try PackageReceiptReader.observe(packageID: receipt.id,
                                    bundle: URL(fileURLWithPath: candidate.asset.path), observedAt: Date(), acquire: query)
                                guard observation.report.status == .associated else { failures += 1; continue }
                                try check()
                                _ = try await store.recordPackageReceipt(observation, for: candidate.asset.catalogID!, at: Date())
                                recorded += 1
                            } catch is CancellationError { throw CancellationError() }
                            catch is Stop { throw Stop.budget }
                            catch { failures += 1 }
                        }
                    } catch is CancellationError { throw CancellationError() }
                    catch is Stop { throw Stop.budget }
                    catch { failures += 1 }
                }
            }
            return summary(failures == 0 ? .complete : .incomplete)
        } catch is CancellationError { return summary(.cancelled) }
        catch { return summary(.incomplete) }
    }

    static func packageIDs(_ data: Data, maximum: Int = 4_096) throws -> [String] {
        guard data.count <= 1_048_576,
              let ids = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String],
              ids.count <= maximum else { throw PackageReceiptError.invalidReceipt }
        var seen = Set<Data>()
        for id in ids {
            try AssetDateResolver.validateIdentifier(id)
            guard !id.hasPrefix("-"), seen.insert(Data(id.utf8)).inserted else { throw PackageReceiptError.invalidReceipt }
        }
        return ids.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    // pkgutil emits separate XML documents for sequential commands. Text values are
    // XML escaped. Any changed framing, extra/missing document or trailing junk fails.
    static func metadataDocuments(_ data: Data, count: Int) throws -> [Data] {
        let header = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        guard data.count <= 262_144, let text = String(data: data, encoding: .utf8), text.hasPrefix(header) else {
            throw PackageReceiptError.invalidReceipt
        }
        let chunks = text.components(separatedBy: header)
        guard chunks.first == "", chunks.count == count + 1 else { throw PackageReceiptError.invalidReceipt }
        return try chunks.dropFirst().map { chunk in
            let document = header + chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            let parser = XMLParser(data: Data(document.utf8)); parser.shouldResolveExternalEntities = false
            guard document.hasSuffix("</plist>"),
                  !document.contains("<!ENTITY"), parser.parse(),
                  (try PropertyListSerialization.propertyList(from: Data(document.utf8), options: [], format: nil)) is [String: Any] else {
                throw PackageReceiptError.invalidReceipt
            }
            return Data(document.utf8)
        }
    }
}
