# Plan: durable catalog date evidence

**Status:** IMPLEMENTED — source/state review passed; final checks recorded separately
**Owner:** Codex coordinator/implementer
**Last updated:** 2026-09-26
**Task ID:** cleanup-essentials
**Risk tier:** 2 (intent explicit; no product decisions pending)
**Domains:** persistence

## Outcome and scope
Retain validated date evidence across catalog reopen, offline scans and verified
moves, with atomic ingestion and local backup. This is the storage boundary needed
by the two priority date features. No UI/provider is admitted by storing claims.
Initial subjects are exact existing catalog node IDs (plugin installations, samples,
library installations); instrument subjects and cross-format product lineage are
explicitly deferred. Do not attach evidence by name or transfer it to replacement
nodes. Original dates stay with the old node until identity migration is validated.

## Evidence / interfaces
CatalogStore is an actor with transaction-owned SQLite connections. Schema 2 stores
nodes, scopes and first discovery but no qualified date history. AssetDateResolver
now validates exact byte identities and chronological bounds; reuse it. Change:
CatalogStore.swift, AssetDateEvidence.swift (stable raw Codable kinds/records),
CatalogPersistenceRegistry.swift, feature-registry.json, catalog_state_check.py,
CatalogStoreTests.swift, AssetDateEvidenceTests.swift, frozen tests/fixtures/catalog-v2.sql,
architecture overview/state-completeness documentation, this plan and parent.
Read existing TOOLCHAIN.md, state-completeness and collaboration contracts.

## Contract
- Schema 3 adds date_evidence(source_id TEXT COLLATE BINARY, evidence_id TEXT COLLATE
  BINARY, subject_id TEXT COLLATE BINARY, payload TEXT), source+evidence primary key,
  subject FK to nodes, indexed by subject. JSON retains full immutable evidence.
  Stable explicit enum raw values; unknown kinds/corrupt JSON fail, not skip.
- appendDateEvidence(records, asOf:) validates all input before opening database;
  every subject must be an existing node. Atomic transaction across all subjects;
  same source+ID and byte-equal payload values is a no-op; conflicting persisted or
  batch duplicate rolls back all additions. Duplicate equality includes ingestion.
- Input <=10,000 records. Retain <=10,000 unique records per node; overflow rejects
  atomically, never evicts old dates. This is an explicit initial operational bound;
  compaction requires a later lossless policy. Query at most 10,001 rows for a node,
  and bound each payload at 32 KiB before decoding. Validate decoded fields against
  row keys and the shared reducer; invalid stored dates or wrong keys fail closed.
- dateEvidence(for:asOf:) and dateSummary(for:asOf:) read one existing node in a
  consistent transaction. Missing database/subject errors rather than inventing
  an empty history. An existing node with no evidence returns empty/unknown.
- No automatic promotion of first_seen, receipts, project dates, or host logs. Scans
  never mutate this ledger. Node IDs survive proven filesystem moves; unchanged nodes
  retain history when offline. Replacement inode remains separate; no false merge.
- v1/v2 migration takes one verified SQLite backup named for original version,
  performs all schema updates transactionally, and sets v3 only on success. Existing
  values remain unchanged; ledger starts empty. Future/foreign DBs are preserved.
  Fresh DB creates v3 directly. Local backup includes the ledger; old binary rejects
  v3 and can recover from backup. No import, merge, corrections, or deletion API added.
  Reserve the writer lock and recheck schema version before backup; use a separate
  read-only source connection for backup while keeping that reservation through ALTER.
  Native SQLite control verified that arrangement and rejection of a competing write.
  Ledger row reads use exact-length UTF-8 validation, reject NUL/non-text and bound
  payload bytes before decoding (existing generic C-string reads are insufficient).

## Risks / ownership / privacy
Single actor writer; SQLite IMMEDIATE transactions serialize other store instances.
SQL parameters bind values; binary comparisons prevent normalization collisions.
Late validation/disk/constraint failures roll back. No raw log/project content in
fixtures or uploaded; private catalog retains only source IDs and qualified events.
Durable evidence is not a guarantee the source classifier is valid. Clock changes can
make a caller's asOf invalid; report an error rather than silently changing timestamps.

## Cross-cutting coverage
New registry field catalog.date_evidence, introduced_in 3, default {}. Presets and DAW
project persistence excluded (local inventory). Empty default; session reset retains
history. Migration and local backup included. Undo/copy-paste/sync/analytics excluded
(no edit/clipboard/cloud/telemetry feature). Automation excluded (internal API only).
Accessibility not applicable to this storage increment; existing error route unchanged,
no controls added. Privacy included (local private DB). No new setting IDs or UI state.

## Implementation and acceptance
1. Independent specification critique before changes.
2. Add schema/backup migration and stable serialization, registry and policies.
3. Implement atomic append and validated read/summary methods.
4. Native tests: populated v2 and existing v1 migrate with untouched dates/metadata;
   backup includes evidence; reopen, move and offline retention; duplicate replay;
   conflicting batch/persisted IDs and missing subjects leave DB unchanged; corrupt
   rows fail; cross-node isolation; capacity failure and injected write failure roll
   back; unsupported DB preserved. No original source/provider time is fabricated.
5. Fresh independent source and state-completeness review; configured checks.

## Verification / runtime
`python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package`
Tests exercise native SQLite reopen/transactions/migration/backup on synthetic files;
never open/migrate the user's real catalog for validation. No GUI behavior changes.
Run `python3 scripts/workflow_gate.py check-complete`; parent release gates remain open.
All concerns recorded in authoritative registry; native exact-ID check must pass.

## Gate dependencies / resume
Code or schema repair reruns affected native checks and fresh review. Final docs precede
final fingerprint-bound verification. Alternate-client authentication previously failed;
distinct read-only Codex critic/reviewer roles are the available fallback.

## Completed checkpoint
Independent Codex critic group_source_review passed with strict UTF-8 row reads and
lock-bound backup requirements. Native SQLite prototype verified a separate read-only
backup under the writer reservation, including rejection of a competing write.
Implementation uses explicit actor-local transaction boundaries after Swift rejected
passing the database through a captured transaction closure; no unchecked Sendable
conformance or concurrency suppression was introduced.

Eight storage tests passed with the existing suite (142 tests). A ninth new regression
freezes all persisted enum spellings and a record's JSON shape; final suite/check
results are stored in automated_tests.json under the parent evidence directory.
Fresh independent source/state reviewer container_review passed after the explicit
enum spelling regression was added. Current source callers remain storage APIs/tests;
no provider or UI qualification is claimed. No user's catalog or audio file was
migrated or altered for validation. All database tests use disposable synthetic data.

Pro Tools research found Avid's supported Shift-open inactive-plugin control, which
can separate saved inclusion from instantiation without changing installed plugins.
It has not been run for this increment and is not a failed-restore substitute.
No supported 24.10.2 command to deliberately fail one real plugin was established.
Next: qualified installer evidence with exact installed-bundle association, then
host-source qualification. Preserve installation-record dates separately from original
Date added; no receipt, scan or project-modification timestamp may become Last used.

Primary references: [SQLite backup API](https://www.sqlite.org/backup.html),
[SQLite transactions](https://www.sqlite.org/lang_transaction.html),
[Avid inactive-plugin troubleshooting](https://kb.avid.com/pkb/articles/en_US/Knowledge/Pro-Tools-cannot-launch-Some-sessions-cannot-be-opened-Frequent-AAE-9173-errors?popup=true).
