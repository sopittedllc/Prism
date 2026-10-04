import Foundation
import CSQLite
import CryptoKit
import Darwin

/// Exact configured scope; overlapping roots retain observation history.
public struct CatalogScope: Codable, Sendable {
    public let roots: [String: [String]]
    public init(_ request: ScanRequest) {
        roots = ["plugins": request.plugins, "samples": request.samples,
                 "libraries": request.libraries, "projects": request.projects]
            .mapValues { Array(Set($0.map { $0.standardizedFileURL.path })).sorted() }
    }
    static func contains(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }
    func roots(for kind: String) -> [String] {
        roots[kind == "plugin" ? "plugins" : kind == "sample" ? "samples" : "libraries"] ?? []
    }
    func exclusions(kind: String, root: String) -> [String] {
        let opposite = kind == "sample" ? "library" : "sample"
        guard kind != "plugin" else { return [] }
        return roots(for: opposite).filter {
            Self.contains($0, root: root) && (kind == "library" || $0 != root)
        }
    }
    func includes(kind: String, path: String) -> Bool {
        roots(for: kind).contains { root in
            Self.contains(path, root: root) && !exclusions(kind: kind, root: root).contains { Self.contains(path, root: $0) }
        }
    }
    var key: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try! encoder.encode(self)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct CatalogObservation: Codable, Sendable {
    public let id: String
    public let firstSeen: Date
    public let lastSeen: Date
    /// This means newly indexed, never an installation timestamp.
    public let baseline: Bool
    public let stale: Bool
    public var addition: AdditionDateEvidence? = nil
    public func isRecent(at now: Date = Date()) -> Bool {
        !baseline && firstSeen <= now && now.timeIntervalSince(firstSeen) <= 30 * 24 * 60 * 60
    }
}
public struct CatalogSnapshot: Sendable {
    public let report: ScanReport
    public let savedAt: Date
    public let observations: [String: CatalogObservation]
    public let metadata: [String: MusicalMetadata]
}

public enum CatalogStoreError: LocalizedError {
    case unavailable, incompatible, invalid, busy
    public var errorDescription: String? {
        switch self {
        case .unavailable: "The saved catalog is unavailable. Current scan results can still be used."
        case .incompatible: "The saved catalog belongs to an unsupported version and has been left unchanged."
        case .invalid: "The saved catalog could not be read and has been left unchanged."
        case .busy: "The saved catalog is busy. Current scan results can still be used."
        }
    }
}

/// Local inventory graph. All SQLite work is serialized by this actor, off the UI actor.
/// Only final scans are ingested. Missing observations are retained and labeled stale.
public actor CatalogStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var application: CatalogStore {
        CatalogStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Simplify/catalog.sqlite"))
    }

    public func load(scope: CatalogScope) throws -> CatalogSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do { try seedScope(db, scope: scope); try invalidateOmittedCoverage(db, scope: scope); try db.execute("COMMIT") }
        catch { try? db.execute("ROLLBACK"); throw error }
        return try read(db, scope: scope)
    }

    /// Writes inventory, graph memberships and observations in a single transaction.
    /// The returned projection strips removal identities; callers keep fresh identities
    /// only for items independently observed by their current scan.
    public func ingest(_ report: ScanReport, scope: CatalogScope, scannedKinds: Set<AssetKind> = Set(AssetKind.allCases), at date: Date = Date(), additionContext: AdditionScanContext? = nil) throws -> CatalogSnapshot {
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            let priorGeneration = try db.rows("SELECT generation FROM scopes WHERE id=?", [scope.key]).first?.first
            try seedScope(db, scope: scope)
            if (priorGeneration == nil || priorGeneration == "unscanned") && scannedKinds != Set(AssetKind.allCases) {
                try seedCompatibleSections(db, scope: scope, scannedKinds: scannedKinds)
            }
            try invalidateOmittedCoverage(db, scope: scope)
            let completedRoots = try db.rows("SELECT kind,path,exclusions FROM root_baselines WHERE complete=1")
            guard date.timeIntervalSince1970.isFinite else { throw CatalogStoreError.invalid }
            // Only comparable complete root scans establish an absence/presence interval.
            var continuousRoots: [(kind: String, root: String, exclusions: [String], identity: String, lower: Date?)] = []
            for kind in scannedKinds.map(\.rawValue) {
                for root in scope.roots(for: kind) {
                    let exclusions = scope.exclusions(kind: kind, root: root)
                    let encoded = try encode(exclusions)
                    let prior = try db.strictRows("SELECT policy,root_identity,CAST(started AS TEXT),CAST(finished AS TEXT) FROM scan_coverage WHERE kind=? AND root=? AND exclusions=?", [kind, root, encoded]).first
                    let incomplete = report.issues.contains { issue in
                        if issue.reason.hasPrefix("Project reference coverage:") { return false }
                        if issue.reason.contains("Entry limit") { return true }
                        if kind == "library", issue.reason.contains("SINE") { return true }
                        return CatalogScope.contains(issue.path, root: root) || CatalogScope.contains(root, root: issue.path)
                    }
                    let identity = incomplete ? nil : additionContext?.identity(for: root, scope: scope, finishedAt: date)
                    var lower: Date?
                    if let prior, let identity, let context = additionContext,
                       prior[0] == AdditionScanContext.policy, prior[1].utf8.elementsEqual(identity.utf8),
                       let start = Double(prior[2]), let end = Double(prior[3]), start.isFinite, end.isFinite,
                       start <= end, end <= context.startedAt.timeIntervalSince1970 {
                        lower = Date(timeIntervalSince1970: start)
                    }
                    // A gap or policy change invalidates continuity, including other exclusion variants.
                    try db.run("DELETE FROM scan_coverage WHERE kind=? AND root=?", [kind, root])
                    if let identity, let context = additionContext {
                        continuousRoots.append((kind, root, exclusions, identity, lower))
                        try db.run("INSERT INTO scan_coverage(kind,root,exclusions,policy,root_identity,started,finished) VALUES(?,?,?,?,?,?,?)",
                                   [kind, root, encoded, AdditionScanContext.policy, identity, stamp(context.startedAt), stamp(date)])
                    }
                }
            }
            let generation = UUID().uuidString
            let old = try db.rows("SELECT evidence,generation,complete FROM scopes WHERE id=?", [scope.key]).first
            let previous = try old.map { try decode(ScanReport.self, $0[0]) }
            // Carry generation membership forward without claiming a new observation.
            if let old {
                for kind in AssetKind.allCases where !scannedKinds.contains(kind) {
                    for table in ["scope_members", "instruments", "physical_members"] {
                        try db.run("UPDATE \(table) SET generation=? WHERE scope_id=? AND generation=? AND node_id IN (SELECT id FROM nodes WHERE kind=?)", [generation, scope.key, old[1], kind.rawValue])
                    }
                }
            }
            var identities = PhysicalKeys()
            for asset in report.assets where scannedKinds.contains(asset.kind) {
                let product = asset.libraryMetadata?.identity?.productID ?? ""
                let physicalKey = identities.key(asset.path)
                let identity = asset.kind.rawValue + ":" + asset.format + ":" + product + ":" + physicalKey
                let existing = try db.rows("SELECT id FROM nodes WHERE identity=?", [identity]).first?.first
                let id = existing ?? UUID().uuidString
                let covered = try completedRoots.contains { row in
                    guard row[0] == asset.kind.rawValue, CatalogScope.contains(asset.path, root: row[1]) else { return false }
                    return try !decode([String].self, row[2]).contains { CatalogScope.contains(asset.path, root: $0) }
                }
                let knownReplacement = try !db.rows("SELECT id FROM nodes WHERE kind=? AND path=?", [asset.kind.rawValue, asset.path]).isEmpty
                let baseline = !covered || knownReplacement
                var header = asset; header.catalogID = id; header.fileIdentity = nil
                let instruments = header.libraryMetadata?.instruments ?? []
                header.libraryMetadata?.instruments = []
                try db.run("""
                    INSERT INTO nodes(id,identity,product_key,kind,path,first_seen,last_seen,baseline)
                    VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
                    path=excluded.path,last_seen=excluded.last_seen
                    """, [id, identity, product, asset.kind.rawValue, asset.path, stamp(date), stamp(date), baseline ? "1" : "0"])
                if existing == nil {
                    let lower = knownReplacement || !physicalKey.hasPrefix("file:") ? nil : continuousRoots.filter {
                        $0.kind == asset.kind.rawValue && CatalogScope.contains(asset.path, root: $0.root)
                            && !$0.exclusions.contains(where: { CatalogScope.contains(asset.path, root: $0) })
                    }.compactMap(\.lower).min()
                    let bounds = try AdditionDateEvidence(basis: lower == nil ? .presentBy : .observedArrival, lower: lower, upper: date)
                    try db.run("INSERT INTO node_addition_bounds(node_id,payload) VALUES(?,?)", [id, try encode(bounds)])
                }
                // Retain unobserved children; a bounded adapter cannot prove their absence.
                for instrument in instruments {
                    let key = instrument.vendorID ?? identities.key(instrument.path)
                    try db.run("""
                        INSERT INTO instruments(scope_id,node_id,id,payload,generation,observed_at) VALUES(?,?,?,?,?,?)
                        ON CONFLICT(scope_id,node_id,id) DO UPDATE SET payload=excluded.payload,generation=excluded.generation,observed_at=excluded.observed_at
                        """, [scope.key, id, key, try encode(instrument), generation, stamp(date)])
                    for path in instrument.contentPaths ?? [] {
                        try db.run("INSERT INTO physical_members(scope_id,node_id,instrument_id,path,generation,observed_at) VALUES(?,?,?,?,?,?) ON CONFLICT(scope_id,node_id,instrument_id,path) DO UPDATE SET generation=excluded.generation,observed_at=excluded.observed_at", [scope.key, id, key, path, generation, stamp(date)])
                    }
                }
                try db.run("DELETE FROM scope_members WHERE scope_id=? AND path=? AND node_id!=? AND node_id IN (SELECT id FROM nodes WHERE product_key=? AND kind=?)", [scope.key, asset.path, id, product, asset.kind.rawValue])
                try db.run("INSERT INTO scope_members(scope_id,node_id,path,payload,generation,baseline,observed_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(scope_id,node_id) DO UPDATE SET path=excluded.path,payload=excluded.payload,generation=excluded.generation,observed_at=excluded.observed_at", [scope.key, id, asset.path, try encode(header), generation, baseline ? "1" : "0", stamp(date)])
                if asset.kind == .plugin { try db.run("DELETE FROM removals WHERE path=?", [asset.path]) }
            }
            let evidence = ScanReport(schemaVersion: report.schemaVersion, assets: [], projects: report.projects,
                sampleInclusions: report.sampleInclusions, issues: report.issues, durationSeconds: report.durationSeconds).merging(previous: previous, scannedKinds: scannedKinds)
            try db.run("""
                INSERT INTO scopes(id,configuration,evidence,saved_at,generation,complete) VALUES(?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET evidence=excluded.evidence,saved_at=excluded.saved_at,
                generation=excluded.generation,complete=MAX(scopes.complete,excluded.complete)
                """, [scope.key, try encode(scope), try encode(evidence), stamp(date), generation, scannedKinds == Set(AssetKind.allCases) && report.issues.isEmpty ? "1" : (old?[2] ?? "0")])
            for kind in scannedKinds.map(\.rawValue) {
                for root in scope.roots(for: kind) {
                    let incomplete = report.issues.contains { issue in
                        if issue.reason.hasPrefix("Project reference coverage:") { return false }
                        if issue.reason.contains("Entry limit") { return true }
                        if kind == "library", issue.reason.contains("SINE") { return true }
                        return CatalogScope.contains(issue.path, root: root) || CatalogScope.contains(root, root: issue.path)
                    }
                    if !incomplete {
                        try db.run("INSERT INTO root_baselines(kind,path,exclusions,complete) VALUES(?,?,?,1) ON CONFLICT(kind,path,exclusions) DO UPDATE SET complete=1", [kind, root, try encode(scope.exclusions(kind: kind, root: root))])
                    }
                }
            }
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
        guard let snapshot = try read(db, scope: scope) else { throw CatalogStoreError.invalid }
        return snapshot
    }

    /// Atomic replacement. Empty facet values are durable suppression; nil resets all overrides.
    public func saveMetadata(_ value: MusicalMetadata?, for subject: MetadataSubject) throws {
        try saveMetadataBatch([(subject, value)])
    }

    /// Atomically retain immutable evidence for exact existing catalog node IDs.
    /// No source qualification, instrument/product association or timestamp inference occurs.
    /// Replays retain their original ingestion date. Each node retains at most 10,000
    /// records; capacity/conflicts reject the batch without pruning history.
    public func appendDateEvidence(_ records: [AssetDateEvidence], asOf: Date) throws {
        _ = try AssetDateResolver.summarize(records, for: "validation", asOf: asOf)
        guard !records.isEmpty else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { throw CatalogStoreError.unavailable }
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            try appendDateEvidence(records, asOf: asOf, to: db)
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    // Caller owns the writer transaction and has validated the incoming batch.
    private nonisolated func appendDateEvidence(_ records: [AssetDateEvidence], asOf: Date,
                                                to db: CatalogDatabase) throws {
        var counts: [Data: Int] = [:]
        for record in records {
            let key = Data(record.subjectID.utf8)
            if counts[key] == nil {
                counts[key] = try readDateEvidence(db, for: record.subjectID, asOf: asOf).count
            }
        }
        for record in records {
            let existing = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?", [record.sourceID, record.evidenceID])
            if let row = existing.first {
                guard try decodeDateEvidence(row) == record else { throw AssetDateEvidenceError.conflictingEvidenceID }
                continue
            }
            let key = Data(record.subjectID.utf8)
            guard counts[key, default: 0] < AssetDateResolver.maximumRecords else { throw AssetDateEvidenceError.tooManyRecords }
            let payload = try encode(record)
            guard payload.utf8.count <= CatalogDatabase.maximumDateTextBytes else { throw CatalogStoreError.invalid }
            try db.run("INSERT INTO date_evidence(source_id,evidence_id,subject_id,payload) VALUES(?,?,?,?)",
                       [record.sourceID, record.evidenceID, record.subjectID, payload])
            counts[key, default: 0] += 1
        }
    }

    /// Bind a live receipt observation to one exact, still-present plugin installation.
    /// Atomic and idempotent; preserves first ingestion and historical provenance.
    /// Rejects mismatched/stale physical identity, removal intent and changed bundles.
    /// Does not mark retained inventory fresh or establish original addition/actual use.
    public func recordPackageReceipt(_ observation: PackageReceiptReader.Observation,
                                     for nodeID: String, at ingestionDate: Date) throws -> AssetDateEvidence {
        try recordPackageReceipt(observation, for: nodeID, at: ingestionDate, beforeFinalValidation: {})
    }

    // Internal failure seam exercises rollback after insertion, before commit.
    func recordPackageReceipt(_ observation: PackageReceiptReader.Observation,
                              for nodeID: String, at ingestionDate: Date,
                              beforeFinalValidation: @Sendable () throws -> Void) throws -> AssetDateEvidence {
        try Task.checkCancellation()
        let report = observation.report
        _ = try AssetDateResolver.summarize([], for: nodeID, asOf: ingestionDate)
        guard report.status == .associated, report.observedAt.timeIntervalSince1970.isFinite,
              report.observedAt <= ingestionDate else { throw CatalogStoreError.invalid }
        let provenance = PackageReceiptProvenance(packageID: report.packageID, packageVersion: report.packageVersion,
            bundlePath: report.bundlePath, bundleIdentifier: report.bundleIdentifier, bundleVersions: report.bundleVersions)
        let eventID = try provenance.eventID(subjectID: nodeID, date: report.receiptDate)
        func evidence(ingestedAt: Date) -> AssetDateEvidence {
            AssetDateEvidence(sourceID: PackageReceiptProvenance.sourceID, evidenceID: eventID,
                subjectID: nodeID, kind: .installationRecord, eventDate: report.receiptDate,
                ingestedAt: ingestedAt, packageReceipt: provenance)
        }
        var record = evidence(ingestedAt: ingestionDate)
        _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: ingestionDate)
        guard FileManager.default.fileExists(atPath: url.path) else { throw CatalogStoreError.unavailable }
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            try observation.revalidate()
            var identities = PhysicalKeys()
            let physical = identities.key(report.bundlePath)
            let format = URL(fileURLWithPath: report.bundlePath).pathExtension.lowercased()
            guard physical.hasPrefix("file:"),
                  let node = try db.dateRows("SELECT identity,kind,path FROM nodes WHERE id=?", [nodeID]).first,
                  node[0].utf8.elementsEqual(("plugin:" + format + "::" + physical).utf8),
                  node[1] == "plugin", node[2].utf8.elementsEqual(report.bundlePath.utf8),
                  try db.dateRows("SELECT path FROM removals WHERE path=?", [report.bundlePath]).isEmpty else {
                throw CatalogStoreError.invalid
            }
            let headers = try db.dateRows("""
                SELECT payload,path FROM scope_members WHERE node_id=? AND observed_at=
                (SELECT MAX(observed_at) FROM scope_members WHERE node_id=?) LIMIT 10001
                """, [nodeID, nodeID])
            guard !headers.isEmpty, headers.count <= AssetDateResolver.maximumRecords else { throw CatalogStoreError.invalid }
            for row in headers {
                let header = try decode(Asset.self, row[0])
                guard header.kind == .plugin, header.catalogID?.utf8.elementsEqual(nodeID.utf8) == true,
                      header.format.utf8.elementsEqual(format.utf8),
                      header.path.utf8.elementsEqual(report.bundlePath.utf8),
                      row[1].utf8.elementsEqual(report.bundlePath.utf8),
                      header.bundleIdentifier?.utf8.elementsEqual(report.bundleIdentifier.utf8) == true else {
                    throw CatalogStoreError.invalid
                }
            }
            if let row = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?",
                                        [record.sourceID, eventID]).first {
                let previous = try decodeDateEvidence(row)
                record = evidence(ingestedAt: previous.ingestedAt)
                guard record == previous else { throw AssetDateEvidenceError.conflictingEvidenceID }
            }
            _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: ingestionDate)
            try appendDateEvidence([record], asOf: ingestionDate, to: db)
            try beforeFinalValidation()
            try observation.revalidate()
            try Task.checkCancellation()
            try db.execute("COMMIT")
            return record
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Retain a completed VST3 class-use event, associated with a currently verified
    /// catalog installation. This never asserts historical use of these physical bytes.
    /// Replays preserve first ingestion; cancellation/identity changes roll back writes.
    public func recordHostUsage(_ event: HostUsageProvenance, binding: LivePluginCache.Binding,
                                for nodeID: String, at date: Date, deadline: Double = .infinity) throws -> AssetDateEvidence {
        func check() throws {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CatalogStoreError.busy }
        }
        try check(); try event.validate()
        guard event.classID.utf8.elementsEqual(binding.classID.utf8), FileManager.default.fileExists(atPath: url.path) else {
            throw CatalogStoreError.invalid
        }
        let eventID = try event.eventID(subjectID: nodeID)
        func make(_ ingestion: Date) -> AssetDateEvidence {
            AssetDateEvidence(sourceID: event.eventSourceID, evidenceID: eventID, subjectID: nodeID,
                kind: .confirmedUse, eventDate: nil, ingestedAt: ingestion, hostUsage: event)
        }
        var record = make(date)
        _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: date)
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            try check(); try binding.revalidate()
            var identities = PhysicalKeys()
            let physical = identities.key(binding.path)
            guard physical.hasPrefix("file:"),
                  let node = try db.dateRows("SELECT identity,kind,path FROM nodes WHERE id=?", [nodeID]).first,
                  node[0].utf8.elementsEqual(("plugin:vst3::" + physical).utf8), node[1] == "plugin",
                  node[2].utf8.elementsEqual(binding.path.utf8),
                  try db.dateRows("SELECT path FROM removals WHERE path=?", [binding.path]).isEmpty else { throw CatalogStoreError.invalid }
            let headers = try db.dateRows("""
                SELECT payload,path FROM scope_members WHERE node_id=? AND observed_at=
                (SELECT MAX(observed_at) FROM scope_members WHERE node_id=?) LIMIT 10001
                """, [nodeID, nodeID])
            guard !headers.isEmpty, headers.count <= AssetDateResolver.maximumRecords else { throw CatalogStoreError.invalid }
            for row in headers {
                let header = try decode(Asset.self, row[0])
                guard header.kind == .plugin, header.catalogID?.utf8.elementsEqual(nodeID.utf8) == true,
                      header.format == "vst3", header.path.utf8.elementsEqual(binding.path.utf8),
                      row[1].utf8.elementsEqual(binding.path.utf8),
                      header.bundleIdentifier?.utf8.elementsEqual(binding.snapshot.identifier.utf8) == true else { throw CatalogStoreError.invalid }
            }
            if let row = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?",
                                        [record.sourceID, eventID]).first {
                let prior = try decodeDateEvidence(row); record = make(prior.ingestedAt)
                guard record == prior else { throw AssetDateEvidenceError.conflictingEvidenceID }
            }
            _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: date)
            try appendDateEvidence([record], asOf: date, to: db)
            try binding.revalidate(); try check()
            try db.execute("COMMIT"); return record
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Retain a Cubase completed-load event only when its current catalog node still
    /// points at the exact cache-resolved VST3 path. The class history is explicit;
    /// physical byte lineage is not inferred.
    public func recordCubaseUsage(_ use: CubaseBoundPluginUse, for nodeID: String, at date: Date) throws -> AssetDateEvidence {
        let record = AssetDateEvidence(sourceID: CubasePluginUse.sourceID, evidenceID: use.use.eventID,
            subjectID: nodeID, kind: .confirmedUse, eventDate: use.use.reportedDate, ingestedAt: date,
            cubaseUsage: use.use)
        _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: date)
        let db = try CatalogDatabase(url); try db.execute("BEGIN IMMEDIATE")
        do {
            let node = try db.dateRows("SELECT kind,path FROM nodes WHERE id=?", [nodeID]).first
            guard node?.count == 2, node?[0] == "plugin", node?[1] == use.pluginPath,
                  use.cid.utf8.count == 32 else { throw CatalogStoreError.invalid }
            if let row = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?", [record.sourceID, record.evidenceID]).first {
                let prior = try decodeDateEvidence(row)
                guard prior.subjectID == record.subjectID, prior.kind == record.kind,
                      prior.eventDate == record.eventDate, prior.cubaseUsage == record.cubaseUsage else { throw AssetDateEvidenceError.conflictingEvidenceID }
                try db.execute("COMMIT"); return prior
            } else { try appendDateEvidence([record], asOf: date, to: db) }
            try db.execute("COMMIT"); return record
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    public func recordProToolsUsage(_ use: ProToolsBoundPluginUse, for nodeID: String, at date: Date) throws -> AssetDateEvidence {
        let record = AssetDateEvidence(sourceID: ProToolsPluginUse.restoreV2SourceID,
            evidenceID: use.use.subjectEventID(nodeID),
            subjectID: nodeID, kind: .confirmedUse, eventDate: nil, ingestedAt: date,
            proToolsUsage: use.use)
        _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: date)
        let db = try CatalogDatabase(url); try db.execute("BEGIN IMMEDIATE")
        do {
            let node = try db.dateRows("SELECT kind,path FROM nodes WHERE id=?", [nodeID])
            guard node.count == 1, node[0].count == 2, node[0][0] == "plugin", node[0][1] == use.pluginPath else { throw CatalogStoreError.invalid }
            if let row = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?", [record.sourceID, record.evidenceID]).first {
                let prior = try decodeDateEvidence(row)
                guard prior.subjectID == record.subjectID, prior.kind == record.kind,
                      prior.eventDate == record.eventDate, prior.proToolsUsage == record.proToolsUsage else { throw AssetDateEvidenceError.conflictingEvidenceID }
                try db.execute("COMMIT"); return prior
            } else { try appendDateEvidence([record], asOf: date, to: db) }
            try db.execute("COMMIT"); return record
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    public func recordLogicUsage(_ use: LogicPluginUse, for nodeID: String, at date: Date) throws -> AssetDateEvidence {
        let record = AssetDateEvidence(sourceID: LogicPluginUse.sourceID, evidenceID: use.eventID,
            subjectID: nodeID, kind: .confirmedUse, eventDate: use.reportedDate, ingestedAt: date,
            logicUsage: use)
        _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: date)
        let db = try CatalogDatabase(url); try db.execute("BEGIN IMMEDIATE")
        do {
            let node = try db.dateRows("SELECT kind,path FROM nodes WHERE id=?", [nodeID])
            guard node.count == 1, node[0].count == 2, node[0][0] == "plugin", node[0][1].hasSuffix(".component") else { throw CatalogStoreError.invalid }
            if let row = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?", [record.sourceID, record.evidenceID]).first {
                let prior = try decodeDateEvidence(row)
                guard prior.subjectID == record.subjectID, prior.kind == record.kind,
                      prior.eventDate == record.eventDate, prior.logicUsage == record.logicUsage else { throw AssetDateEvidenceError.conflictingEvidenceID }
                try db.execute("COMMIT"); return prior
            } else { try appendDateEvidence([record], asOf: date, to: db) }
            try db.execute("COMMIT"); return record
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Latest reported use per exact node, preserving source and class scope.
    /// Same-day Live records compare their full source-local clock. Incomparable host
    /// clocks use a stable family order, never an inferred cross-host chronology.
    /// One atomic read; corruption yields no partial projection.
    public func latestHostUsage(for nodeIDs: [String], asOf: Date) throws -> [Data: AssetDateEvidence] {
        try Task.checkCancellation()
        guard nodeIDs.count <= 2048, FileManager.default.fileExists(atPath: url.path) else { throw CatalogStoreError.invalid }
        let db = try CatalogDatabase(url); try db.execute("BEGIN")
        do {
            var result: [Data: AssetDateEvidence] = [:], total = 0
            for id in nodeIDs {
                try Task.checkCancellation()
                let records = try readDateEvidence(db, for: id, asOf: asOf); total += records.count
                guard total <= 100_000 else { throw AssetDateEvidenceError.tooManyRecords }
                func family(_ record: AssetDateEvidence) -> Int {
                    if record.hostUsage != nil { return 0 }
                    if record.cubaseUsage != nil { return 1 }
                    if record.proToolsUsage != nil { return 2 }
                    return 3
                }
                let usage = records.filter {
                    $0.hostUsage != nil || $0.cubaseUsage != nil ||
                    ($0.sourceID == ProToolsPluginUse.restoreV2SourceID && $0.proToolsUsage != nil) ||
                    $0.logicUsage != nil
                }.sorted { a, b in
                    let ad = a.hostUsage?.localTime.dayKey ?? a.cubaseUsage?.reportedDate.formatted(.iso8601.year().month().day()) ?? a.proToolsUsage?.localTime?.dayKey ?? a.logicUsage?.reportedDate.formatted(.iso8601.year().month().day()) ?? ""
                    let bd = b.hostUsage?.localTime.dayKey ?? b.cubaseUsage?.reportedDate.formatted(.iso8601.year().month().day()) ?? b.proToolsUsage?.localTime?.dayKey ?? b.logicUsage?.reportedDate.formatted(.iso8601.year().month().day()) ?? ""
                    if ad != bd { return ad > bd }
                    let af = family(a), bf = family(b)
                    if af != bf { return af < bf }
                    if let al = a.hostUsage, let bl = b.hostUsage,
                       al.localTime.canonical != bl.localTime.canonical {
                        return al.localTime.canonical > bl.localTime.canonical
                    }
                    if let al = a.proToolsUsage, let bl = b.proToolsUsage {
                        if al.localTime != bl.localTime {
                            return (al.localTime?.canonical ?? "") > (bl.localTime?.canonical ?? "")
                        }
                        if al.runHash != bl.runHash {
                            return (al.runHash ?? "") < (bl.runHash ?? "")
                        }
                        if al.sourceSeconds != bl.sourceSeconds {
                            return al.sourceSeconds > bl.sourceSeconds
                        }
                    }
                    return a.evidenceID.utf8.lexicographicallyPrecedes(b.evidenceID.utf8)
                }
                if let first = usage.first { result[Data(id.utf8)] = first }
            }
            try db.execute("COMMIT"); return result
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Read a bounded, validated history in one database snapshot. Missing database/node
    /// and corrupt evidence throw; an existing node without history returns an empty array.
    public func dateEvidence(for nodeID: String, asOf: Date) throws -> [AssetDateEvidence] {
        _ = try AssetDateResolver.summarize([], for: nodeID, asOf: asOf)
        guard FileManager.default.fileExists(atPath: url.path) else { throw CatalogStoreError.unavailable }
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN")
        do {
            let records = try readDateEvidence(db, for: nodeID, asOf: asOf)
            try db.execute("COMMIT")
            return records
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Latest typed installer receipt per exact UTF-8 node ID, in one read snapshot.
    /// No partial result on corruption/missing nodes/budget overflow. At most 2,048
    /// requested IDs and 100,000 validated history records; unknown nodes are not inferred.
    public func latestInstallerRecords(for nodeIDs: [String], asOf: Date) throws -> [Data: AssetDateEvidence] {
        try Task.checkCancellation()
        guard nodeIDs.count <= 2_048 else { throw AssetDateEvidenceError.tooManyRecords }
        for id in nodeIDs { _ = try AssetDateResolver.summarize([], for: id, asOf: asOf) }
        _ = try AssetDateResolver.summarize([], for: "validation", asOf: asOf)
        guard !nodeIDs.isEmpty else { return [:] }
        guard FileManager.default.fileExists(atPath: url.path) else { throw CatalogStoreError.unavailable }
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN")
        do {
            var seen = Set<Data>(), result: [Data: AssetDateEvidence] = [:], count = 0
            for id in nodeIDs where seen.insert(Data(id.utf8)).inserted {
                try Task.checkCancellation()
                let records = try readDateEvidence(db, for: id, asOf: asOf)
                count += records.count
                guard count <= 100_000 else { throw AssetDateEvidenceError.tooManyRecords }
                // readDateEvidence is ordered by binary source/event; keep first at equal dates.
                for record in records where record.packageReceipt != nil {
                    if let date = record.eventDate, result[Data(id.utf8)]?.eventDate.map({ date > $0 }) ?? true {
                        result[Data(id.utf8)] = record
                    }
                }
            }
            try Task.checkCancellation()
            try db.execute("COMMIT")
            return result
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Derived from retained source events, never from catalog scan or restore time.
    public func dateSummary(for nodeID: String, asOf: Date) throws -> AssetDateSummary {
        try AssetDateResolver.summarize(dateEvidence(for: nodeID, asOf: asOf), for: nodeID, asOf: asOf)
    }

    private nonisolated func readDateEvidence(_ db: CatalogDatabase, for nodeID: String, asOf: Date) throws -> [AssetDateEvidence] {
        guard try !db.rows("SELECT id FROM nodes WHERE id=?", [nodeID]).isEmpty else { throw CatalogStoreError.invalid }
        let rows = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE subject_id=? ORDER BY source_id,evidence_id LIMIT 10001", [nodeID])
        let records = try rows.map(decodeDateEvidence)
        _ = try AssetDateResolver.summarize(records, for: nodeID, asOf: asOf)
        return records
    }

    private nonisolated func decodeDateEvidence(_ row: [String]) throws -> AssetDateEvidence {
        guard row.count == 4 else { throw CatalogStoreError.invalid }
        let record = try decode(AssetDateEvidence.self, row[3])
        guard record.sourceID.utf8.elementsEqual(row[0].utf8),
              record.evidenceID.utf8.elementsEqual(row[1].utf8),
              record.subjectID.utf8.elementsEqual(row[2].utf8) else { throw CatalogStoreError.invalid }
        return record
    }

    /// Commit all overrides together, including deletions. Any invalid subject rolls back the batch.
    public func saveMetadataBatch(_ edits: [(MetadataSubject, MusicalMetadata?)]) throws {
        let edits = try edits.map { ($0.0, try $0.1?.validated()) }
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            for (subject, value) in edits {
                guard try !db.rows("SELECT id FROM nodes WHERE id=?", [subject.nodeID]).isEmpty else { throw CatalogStoreError.invalid }
                if let value, !value.fields.isEmpty {
                    try db.run("INSERT INTO metadata_overrides(subject,node_id,payload) VALUES(?,?,?) ON CONFLICT(subject) DO UPDATE SET payload=excluded.payload", [subject.key, subject.nodeID, try encode(value)])
                } else { try db.run("DELETE FROM metadata_overrides WHERE subject=?", [subject.key]) }
            }
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Seed only selected locations from the latest known payload for each observation.
    /// A new scope has no fresh generation: transferred records are stale until scanned.
    private func invalidateOmittedCoverage(_ db: CatalogDatabase, scope: CatalogScope) throws {
        for row in try db.strictRows("SELECT kind,root,exclusions FROM scan_coverage") {
            guard scope.roots(for: row[0]).contains(row[1]),
                  try encode(scope.exclusions(kind: row[0], root: row[1])) == row[2] else {
                try db.run("DELETE FROM scan_coverage WHERE kind=? AND root=? AND exclusions=?", row)
                continue
            }
        }
    }

    private func seedScope(_ db: CatalogDatabase, scope: CatalogScope) throws {
        var inserted = try !db.rows("SELECT id FROM scopes WHERE id=?", [scope.key]).isEmpty
        let candidates = try db.rows("""
            SELECT m.scope_id,m.node_id,m.path,m.payload,m.baseline,n.kind,s.saved_at,m.observed_at
            FROM scope_members m JOIN nodes n ON n.id=m.node_id JOIN scopes s ON s.id=m.scope_id
            ORDER BY m.observed_at DESC,s.saved_at DESC,m.scope_id
            """)
        var seen = Set<String>(); var locations = Set<String>()
        for row in candidates where scope.includes(kind: row[5], path: row[2]) {
            let asset = try decode(Asset.self, row[3])
            let location = row[5] + ":" + row[2] + ":" + (asset.libraryMetadata?.identity?.productID ?? "")
            guard seen.insert(row[1]).inserted, locations.insert(location).inserted else { continue }
            if !inserted {
                let evidence = ScanReport(schemaVersion: 1, assets: [], projects: [], sampleInclusions: [], issues: [], durationSeconds: 0)
                try db.run("INSERT INTO scopes(id,configuration,evidence,saved_at,generation,complete) VALUES(?,?,?,?,?,0)", [scope.key, try encode(scope), try encode(evidence), row[6], "unscanned"])
                inserted = true
            }
            let previous = try db.rows("SELECT observed_at FROM scope_members WHERE scope_id=? AND node_id=?", [scope.key, row[1]]).first
            if row[0] != scope.key, previous == nil || (Double(row[7]) ?? 0) > (Double(previous![0]) ?? 0) {
                try db.run("DELETE FROM scope_members WHERE scope_id=? AND path=? AND node_id!=? AND node_id IN (SELECT id FROM nodes WHERE kind=? AND product_key=?)", [scope.key, row[2], row[1], row[5], asset.libraryMetadata?.identity?.productID ?? ""])
                try db.run("INSERT INTO scope_members(scope_id,node_id,path,payload,generation,baseline,observed_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(scope_id,node_id) DO UPDATE SET path=excluded.path,payload=excluded.payload,generation=excluded.generation,observed_at=excluded.observed_at", [scope.key, row[1], row[2], row[3], "retained", row[4], row[7]])
            }
            // Children carry their own observation dates: an offline scan must not win
            // over a newer patch/member merely because its containing scope was saved later.
            let children = try db.rows("SELECT id,payload,observed_at FROM instruments WHERE node_id=? ORDER BY observed_at DESC", [row[1]])
            var childIDs = Set<String>()
            for child in children where childIDs.insert(child[0]).inserted {
                let instrument = try decode(LibraryInstrument.self, child[1])
                guard scope.includes(kind: "library", path: instrument.path) else { continue }
                try db.run("INSERT INTO instruments(scope_id,node_id,id,payload,generation,observed_at) VALUES(?,?,?,?,'retained',?) ON CONFLICT(scope_id,node_id,id) DO UPDATE SET payload=excluded.payload,generation=excluded.generation,observed_at=excluded.observed_at WHERE excluded.observed_at>instruments.observed_at", [scope.key, row[1], child[0], child[1], child[2]])
                for member in try db.rows("SELECT path,MAX(observed_at) FROM physical_members WHERE node_id=? AND instrument_id=? GROUP BY path", [row[1], child[0]]) {
                    try db.run("INSERT INTO physical_members(scope_id,node_id,instrument_id,path,generation,observed_at) VALUES(?,?,?,?,'retained',?) ON CONFLICT(scope_id,node_id,instrument_id,path) DO UPDATE SET generation=excluded.generation,observed_at=excluded.observed_at WHERE excluded.observed_at>physical_members.observed_at", [scope.key, row[1], child[0], member[0], member[1]])
                }
            }
        }
    }

    /// Root changes in one section do not invalidate independently unchanged sections.
    private func seedCompatibleSections(_ db: CatalogDatabase, scope: CatalogScope, scannedKinds: Set<AssetKind>) throws {
        let candidates = try db.rows("SELECT id,configuration,evidence,generation,saved_at FROM scopes WHERE id!=? AND generation!='unscanned' ORDER BY CAST(saved_at AS REAL) DESC,id", [scope.key])
        var evidence = ScanReport(schemaVersion: 1, assets: [], projects: [], sampleInclusions: [], issues: [], durationSeconds: 0)
        for kind in AssetKind.allCases where !scannedKinds.contains(kind) {
            let dependencies = kind == .plugin ? ["plugins"] : kind == .sample ? ["samples", "libraries", "projects"] : ["libraries", "samples"]
            for row in candidates {
                let source = try decode(CatalogScope.self, row[1])
                guard dependencies.allSatisfy({ source.roots[$0] == scope.roots[$0] }) else { continue }
                let saved = try decode(ScanReport.self, row[2])
                let section = ScanReport(schemaVersion: saved.schemaVersion, assets: [],
                    projects: kind == .sample ? saved.projects : [], sampleInclusions: kind == .sample ? saved.sampleInclusions : [],
                    issues: saved.issues.filter { $0.kind == kind || $0.kind == nil }, durationSeconds: 0)
                evidence = section.merging(previous: evidence, scannedKinds: [kind])
                // Only equal observations transfer freshness. Newer incompatible observations
                // stay retained/stale; no observation or baseline timestamp is advanced.
                try db.run("""
                    UPDATE scope_members AS target SET generation='unscanned' WHERE scope_id=?
                    AND node_id IN (SELECT id FROM nodes WHERE kind=?) AND EXISTS
                    (SELECT 1 FROM scope_members source WHERE source.scope_id=? AND source.node_id=target.node_id
                    AND source.generation=? AND source.observed_at=target.observed_at)
                    """, [scope.key, kind.rawValue, row[0], row[3]])
                for (table, key) in [("instruments", "id"), ("physical_members", "instrument_id")] {
                    let pathMatch = table == "physical_members" ? " AND source.path=target.path" : ""
                    try db.run("""
                        UPDATE \(table) AS target SET generation='unscanned' WHERE scope_id=?
                        AND node_id IN (SELECT id FROM nodes WHERE kind=?) AND EXISTS
                        (SELECT 1 FROM \(table) source WHERE source.scope_id=? AND source.node_id=target.node_id
                        AND source.\(key)=target.\(key)\(pathMatch) AND source.generation=? AND source.observed_at=target.observed_at)
                        """, [scope.key, kind.rawValue, row[0], row[3]])
                }
                break
            }
        }
        try db.run("""
            INSERT INTO scopes(id,configuration,evidence,saved_at,generation,complete) VALUES(?,?,?,?, 'unscanned',0)
            ON CONFLICT(id) DO UPDATE SET evidence=excluded.evidence
            """, [scope.key, try encode(scope), try encode(evidence), candidates.first?[4] ?? "0"])
    }

    /// Durable intent precedes filesystem removal so a crash cannot resurrect an old
    /// cached plugin. Failed/canceled removals are restored by a subsequent fresh scan.
    public func recordRemovalIntent(paths: Set<String>) throws {
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            for path in paths { try db.run("INSERT OR IGNORE INTO removals(path) VALUES(?)", [path]) }
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Explicit local backup. Destination must not exist; no automatic upload/import.
    public func backup(to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CatalogStoreError.unavailable }
        let source = try CatalogDatabase(url)
        let target = try CatalogDatabase(destination)
        guard let backup = sqlite3_backup_init(target.handle, "main", source.handle, "main") else { throw CatalogStoreError.unavailable }
        let result = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else { throw CatalogStoreError.unavailable }
    }

    private func read(_ db: CatalogDatabase, scope: CatalogScope) throws -> CatalogSnapshot? {
        // Read transaction prevents mixing a snapshot header and rows from different commits.
        try db.execute("BEGIN")
        do {
            guard let snapshot = try db.rows("SELECT evidence,saved_at,generation FROM scopes WHERE id=?", [scope.key]).first else { try db.execute("COMMIT"); return nil }
            let evidence = try decode(ScanReport.self, snapshot[0])
            guard let time = Double(snapshot[1]) else { throw CatalogStoreError.invalid }
            let generation = snapshot[2]
            let rows = try db.rows("""
                SELECT n.id,m.payload,n.first_seen,n.last_seen,n.baseline,m.generation FROM nodes n
                JOIN scope_members m ON m.node_id=n.id WHERE m.scope_id=?
                AND NOT (n.kind='plugin' AND m.path IN (SELECT path FROM removals)) ORDER BY n.id
                """, [scope.key])
            let childRows = try db.rows("""
                SELECT i.node_id,i.payload,i.generation,i.id FROM instruments i
                JOIN scope_members m ON m.node_id=i.node_id AND m.scope_id=i.scope_id WHERE m.scope_id=? ORDER BY i.node_id,i.id
                """, [scope.key])
            let memberRows = try db.rows("SELECT node_id,instrument_id,path,generation FROM physical_members WHERE scope_id=? ORDER BY path", [scope.key])
            var members: [String: [String: [LibraryContentMember]]] = [:]
            for row in memberRows {
                members[row[0], default: [:]][row[1], default: []].append(LibraryContentMember(path: row[2], stale: row[3] != generation))
            }
            let staleParents = Set(rows.filter { $0[5] != generation }.map { $0[0] })
            var children: [String: [LibraryInstrument]] = [:]
            for row in childRows {
                var child = try decode(LibraryInstrument.self, row[1])
                child.catalogStale = row[2] != generation || staleParents.contains(row[0])
                if let known = members[row[0]]?[row[3]] {
                    child.contentMembers = known.map { LibraryContentMember(path: $0.path, stale: $0.stale || child.catalogStale == true) }; child.contentPaths = known.map(\.path)
                }
                children[row[0], default: []].append(child)
            }
            let additionRows = try db.strictRows("SELECT node_id,payload FROM node_addition_bounds WHERE node_id IN (SELECT node_id FROM scope_members WHERE scope_id=?)", [scope.key])
            var additions: [Data: AdditionDateEvidence] = [:]
            for row in additionRows {
                guard additions.updateValue(try decode(AdditionDateEvidence.self, row[1]).validated(), forKey: Data(row[0].utf8)) == nil else { throw CatalogStoreError.invalid }
            }
            var assets: [Asset] = []; var observations: [String: CatalogObservation] = [:]
            for row in rows {
                var asset = try decode(Asset.self, row[1]); asset.fileIdentity = nil
                asset.libraryMetadata?.instruments = children[row[0]] ?? []
                guard let first = Double(row[2]), let last = Double(row[3]) else { throw CatalogStoreError.invalid }
                let stale = row[5] != generation
                asset.catalogStale = stale
                assets.append(asset)
                observations[row[0]] = CatalogObservation(id: row[0], firstSeen: Date(timeIntervalSince1970: first),
                    lastSeen: Date(timeIntervalSince1970: last), baseline: row[4] == "1", stale: stale,
                    addition: try additions[Data(row[0].utf8)] ?? AdditionDateEvidence(basis: .presentBy, lower: nil, upper: Date(timeIntervalSince1970: first)))
            }
            let report = ScanReport(schemaVersion: evidence.schemaVersion, assets: assets, projects: evidence.projects,
                sampleInclusions: evidence.sampleInclusions, issues: evidence.issues, durationSeconds: evidence.durationSeconds)
            let metadataRows = try db.rows("SELECT subject,payload FROM metadata_overrides WHERE node_id IN (SELECT node_id FROM scope_members WHERE scope_id=?)", [scope.key])
            let metadata = try Dictionary(uniqueKeysWithValues: metadataRows.map { ($0[0], try decode(MusicalMetadata.self, $0[1]).validated()) })
            try db.execute("COMMIT")
            return CatalogSnapshot(report: report, savedAt: Date(timeIntervalSince1970: time), observations: observations, metadata: metadata)
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
    private nonisolated func stamp(_ date: Date) -> String { String(date.timeIntervalSince1970) }
    private nonisolated func encode<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    private nonisolated func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        do { return try JSONDecoder().decode(type, from: Data(text.utf8)) }
        catch { throw CatalogStoreError.invalid }
    }
}

struct PhysicalKeys {
    var volumes: [Int32: String] = [:]
    mutating func key(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        var info = stat()
        guard LibraryMetadataReader.safe(url), lstat(path, &info) == 0,
              (info.st_mode & S_IFMT == S_IFDIR || info.st_nlink == 1), info.st_mode & S_IFMT != S_IFLNK else { return "path:" + path }
        if volumes[info.st_dev] == nil {
            volumes[info.st_dev] = (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) ?? ""
        }
        guard let volume = volumes[info.st_dev], !volume.isEmpty else { return "path:" + path }
        return "file:\(volume):\(info.st_ino):\(info.st_birthtimespec.tv_sec):\(info.st_birthtimespec.tv_nsec)"
    }
}

/// Owned by one actor operation; prepared statements and connections never escape it.
private final class CatalogDatabase {
    var handle: OpaquePointer?
    private static let applicationID = 0x534D504C
    init(_ url: URL) throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        var existing = parent
        while !fm.fileExists(atPath: existing.path), existing.path != "/" { existing.deleteLastPathComponent() }
        guard LibraryMetadataReader.safe(existing) else { throw CatalogStoreError.unavailable }
        try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard LibraryMetadataReader.safe(parent) else { throw CatalogStoreError.unavailable }
        var info = stat()
        if lstat(url.path, &info) != 0 {
            let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw CatalogStoreError.unavailable }; close(descriptor)
        } else {
            guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { throw CatalogStoreError.unavailable }
        }
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }; handle = nil; throw CatalogStoreError.unavailable
        }
        do {
            sqlite3_busy_timeout(handle, 250)
            sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 16 * 1024 * 1024)
            let version = try rows("PRAGMA user_version").first?.first
            let application = try rows("PRAGMA application_id").first?.first
            if version == "0", application == "0" {
                guard try rows("SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'").isEmpty else { throw CatalogStoreError.incompatible }
                try transaction {
                    try execute(Self.schema)
                    try execute("PRAGMA application_id=\(Self.applicationID); PRAGMA user_version=4")
                }
            } else if application != String(Self.applicationID) || !["1", "2", "3", "4"].contains(version ?? "") { throw CatalogStoreError.incompatible }
            if let version, ["1", "2", "3"].contains(version) {
                try transaction {
                    guard try rows("PRAGMA user_version").first?.first == version else { throw CatalogStoreError.busy }
                    // Keep the writer reservation through backup and ALTER. A separate
                    // read-only connection can back up the unmodified committed state.
                    let backupURL = url.deletingLastPathComponent().appendingPathComponent("catalog-v\(version)-backup-" + UUID().uuidString + ".sqlite")
                    let target = try CatalogDatabase(backupURL)
                    var reader: OpaquePointer?
                    defer { if let reader { sqlite3_close(reader) } }
                    guard sqlite3_open_v2(url.path, &reader, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK,
                          let backup = sqlite3_backup_init(target.handle, "main", reader, "main") else { throw CatalogStoreError.unavailable }
                    let copied = sqlite3_backup_step(backup, -1); let finished = sqlite3_backup_finish(backup)
                    guard copied == SQLITE_DONE, finished == SQLITE_OK,
                          try target.rows("PRAGMA user_version").first?.first == version,
                          try target.rows("PRAGMA quick_check").first?.first == "ok" else { throw CatalogStoreError.unavailable }
                    if version == "1" {
                        try execute(Self.discoverySchema)
                        // Preserve only proven complete baselines. Incomplete scopes require a fresh inventory.
                        for row in try rows("SELECT configuration FROM scopes WHERE complete=1") {
                            guard let data = row[0].data(using: .utf8), let scope = try? JSONDecoder().decode(CatalogScope.self, from: data) else { throw CatalogStoreError.invalid }
                            for kind in ["plugin", "sample", "library"] {
                                for root in scope.roots(for: kind) {
                                    try run("INSERT OR IGNORE INTO root_baselines(kind,path,exclusions,complete) VALUES(?,?,?,1)", [kind, root, String(decoding: try JSONEncoder().encode(scope.exclusions(kind: kind, root: root)), as: UTF8.self)])
                                }
                            }
                        }
                    }
                    if version != "3" { try execute(Self.dateEvidenceSchema) }
                    try execute(Self.additionSchema)
                    try execute("PRAGMA user_version=4")
                }
            }
            try execute("PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL")
        } catch {
            sqlite3_close(handle); handle = nil; throw error
        }
    }
    deinit { if let handle { sqlite3_close(handle) } }
    func transaction<T>(isolation: isolated (any Actor)? = #isolation, _ operation: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try operation(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func readTransaction<T>(isolation: isolated (any Actor)? = #isolation, _ operation: () throws -> T) throws -> T {
        try execute("BEGIN")
        do { let result = try operation(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func execute(_ sql: String) throws {
        let result = sqlite3_exec(handle, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw result == SQLITE_BUSY ? CatalogStoreError.busy : CatalogStoreError.invalid }
    }
    func run(_ sql: String, _ values: [String] = []) throws { _ = try rows(sql, values) }
    static let maximumDateTextBytes = 32 * 1024
    func dateRows(_ sql: String, _ values: [String] = []) throws -> [[String]] {
        try rows(sql, values, strictDateText: true)
    }
    func strictRows(_ sql: String, _ values: [String] = []) throws -> [[String]] {
        try rows(sql, values, strictDateText: true, strictRowLimit: 1_000_000)
    }
    func rows(_ sql: String, _ values: [String] = [], strictDateText: Bool = false, strictRowLimit: Int = AssetDateResolver.maximumRecords + 1) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw CatalogStoreError.invalid }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            guard value.withCString({ sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient) }) == SQLITE_OK else { throw CatalogStoreError.invalid }
        }
        var result: [[String]] = []; var byteCount = 0; var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            byteCount += (0..<sqlite3_column_count(statement)).reduce(0) { $0 + Int(sqlite3_column_bytes(statement, $1)) }
            guard result.count < 1_000_000, byteCount <= 128 * 1024 * 1024 else { throw CatalogStoreError.invalid }
            if strictDateText {
                guard result.count < strictRowLimit else { throw AssetDateEvidenceError.tooManyRecords }
                result.append(try (0..<sqlite3_column_count(statement)).map { column in
                    let size = Int(sqlite3_column_bytes(statement, column))
                    guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
                          size <= Self.maximumDateTextBytes,
                          let bytes = sqlite3_column_text(statement, column) else { throw CatalogStoreError.invalid }
                    let data = Data(bytes: bytes, count: size)
                    guard !data.contains(0), let value = String(data: data, encoding: .utf8) else { throw CatalogStoreError.invalid }
                    return value
                })
            } else { result.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
            }) }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw status == SQLITE_BUSY ? CatalogStoreError.busy : CatalogStoreError.invalid }
        return result
    }
    static let discoverySchema = """
    ALTER TABLE scope_members ADD COLUMN observed_at REAL NOT NULL DEFAULT 0;
    ALTER TABLE instruments ADD COLUMN observed_at REAL NOT NULL DEFAULT 0;
    ALTER TABLE physical_members ADD COLUMN observed_at REAL NOT NULL DEFAULT 0;
    UPDATE scope_members SET observed_at=COALESCE((SELECT saved_at FROM scopes WHERE id=scope_id AND generation=scope_members.generation),0);
    UPDATE instruments SET observed_at=COALESCE((SELECT saved_at FROM scopes WHERE id=scope_id AND generation=instruments.generation),0);
    UPDATE physical_members SET observed_at=COALESCE((SELECT saved_at FROM scopes WHERE id=scope_id AND generation=physical_members.generation),0);
    CREATE TABLE root_baselines(kind TEXT NOT NULL,path TEXT NOT NULL,exclusions TEXT NOT NULL,complete INTEGER NOT NULL,PRIMARY KEY(kind,path,exclusions));
    CREATE TABLE metadata_overrides(subject TEXT PRIMARY KEY,node_id TEXT NOT NULL,payload TEXT NOT NULL,FOREIGN KEY(node_id) REFERENCES nodes(id));
    CREATE INDEX metadata_node ON metadata_overrides(node_id);
    """
    static let dateEvidenceSchema = """
    CREATE TABLE date_evidence(source_id TEXT COLLATE BINARY NOT NULL,evidence_id TEXT COLLATE BINARY NOT NULL,
      subject_id TEXT COLLATE BINARY NOT NULL,payload TEXT NOT NULL,
      PRIMARY KEY(source_id,evidence_id),FOREIGN KEY(subject_id) REFERENCES nodes(id));
    CREATE INDEX date_evidence_subject ON date_evidence(subject_id);
    """
    static let additionSchema = """
    CREATE TABLE scan_coverage(kind TEXT NOT NULL,root TEXT NOT NULL,exclusions TEXT NOT NULL,policy TEXT NOT NULL,root_identity TEXT NOT NULL,started REAL NOT NULL,finished REAL NOT NULL,PRIMARY KEY(kind,root,exclusions));
    CREATE TABLE node_addition_bounds(node_id TEXT PRIMARY KEY,payload TEXT NOT NULL,FOREIGN KEY(node_id) REFERENCES nodes(id));
    """
    static let schema = """
    CREATE TABLE nodes(id TEXT PRIMARY KEY,identity TEXT UNIQUE NOT NULL,product_key TEXT NOT NULL,
      kind TEXT NOT NULL,path TEXT NOT NULL,first_seen REAL NOT NULL,last_seen REAL NOT NULL,baseline INTEGER NOT NULL);
    CREATE TABLE instruments(scope_id TEXT NOT NULL,node_id TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,generation TEXT NOT NULL,PRIMARY KEY(scope_id,node_id,id), FOREIGN KEY(node_id) REFERENCES nodes(id), FOREIGN KEY(scope_id) REFERENCES scopes(id) DEFERRABLE INITIALLY DEFERRED);
    CREATE TABLE physical_members(scope_id TEXT NOT NULL,node_id TEXT NOT NULL,instrument_id TEXT NOT NULL,path TEXT NOT NULL,generation TEXT NOT NULL,PRIMARY KEY(scope_id,node_id,instrument_id,path), FOREIGN KEY(scope_id,node_id,instrument_id) REFERENCES instruments(scope_id,node_id,id));
    CREATE TABLE scopes(id TEXT PRIMARY KEY,configuration TEXT NOT NULL,evidence TEXT NOT NULL,saved_at REAL NOT NULL,generation TEXT NOT NULL,complete INTEGER NOT NULL);
    CREATE TABLE scope_members(scope_id TEXT NOT NULL,node_id TEXT NOT NULL,path TEXT NOT NULL,payload TEXT NOT NULL,generation TEXT NOT NULL,baseline INTEGER NOT NULL,PRIMARY KEY(scope_id,node_id), FOREIGN KEY(node_id) REFERENCES nodes(id), FOREIGN KEY(scope_id) REFERENCES scopes(id) DEFERRABLE INITIALLY DEFERRED);
    CREATE TABLE removals(path TEXT PRIMARY KEY);
    CREATE INDEX instruments_parent ON instruments(node_id);
    CREATE INDEX members_scope ON scope_members(scope_id);
    """ + discoverySchema + dateEvidenceSchema + additionSchema
}
