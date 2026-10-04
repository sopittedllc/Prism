# Plan: attach installer evidence to exact catalog installations

**Status:** IMPLEMENTED — scoped verification recorded separately; parent feature open
**Owner:** Codex coordinator/implementer
**Last updated:** 2026-09-26
**Task ID:** cleanup-essentials
**Risk tier:** 2; explicit intent, no unresolved product decision
**Domains:** persistence, source integration

## Outcome / scope
Connect the verified receipt source to durable date history, retaining provenance and
making repeat scans idempotent. No automatic receipt enumeration, UI change, product
aggregation, usage qualification or original-addition claim. Receipt records are
installation-level history, not current-version certification after future updates.

## Current evidence / files
PackageReceiptReader checks paths/version/metadata but returns a serializable report
without its verification stamps. CatalogStore appends existing-node evidence without
current physical correspondence. Nodes use volume/inode/birth identity or weak path
fallback; product rows may aggregate several nodes. Installed UI is hardcoded unknown
and its sort has no dates. Researcher usage_feasibility verified these boundaries.
Change PackageReceiptReader.swift, AssetDateEvidence.swift, CatalogStore.swift and
their tests; state/architecture documentation and registry policy text; plans.

## Contract
- Reader adds an immutable Sendable Observation token, not Codable and with no public
  initializer. It retains its report and private bundle/Info/executable stamps and
  metadata. Existing inspect/report API and CLI keep their read-only behavior.
  A public observe factory uses the same bounded acquisition; an internal injected
  factory supports synthetic tests. Token revalidation rereads current bundle metadata
  and compares exact metadata and stamps. This narrows filesystem races but does not
  claim protection against hostile concurrent mutation or a content hash.
- CatalogStore.recordPackageReceipt(observation, for: nodeID, at: ingestionDate) accepts
  only associated observations, with finite observation <= ingestion. It validates
  subject/time before opening the database and holds one IMMEDIATE transaction through
  identity checks, append, revalidation and commit. No pkgutil process runs under this
  transaction. Token revalidates before and after the ledger write.
- Exact node must be a plugin, path byte-equal to report, with strong file identity
  equal to the current volume/inode/birth key; reject path fallback. Latest known
  scope_members header for that node must have matching catalogID, plugin format,
  path and bundle identifier. Tied latest observed_at headers must all agree on those fields; conflicting ties reject. Removal intent rejects attachment. Database writer lock
  holds catalog state stable; callers remain responsible for active-scope selection.
  Offline or replaced bundles fail; a node need not be relabeled fresh by attachment.
- Persist only installationRecord. Optional typed packageReceipt provenance on
  AssetDateEvidence retains packageID, packageVersion, bundlePath, bundleIdentifier,
  bundleVersions. Dates remain eventDate/first ingestedAt. Provenance strings are
  bounded nonblank/control-free (path 4,096 UTF-8 bytes, other fields 1,024; full payload 32 KiB); versions count 1–2 in reader order (short version then bundle version, retaining duplicates); package version must byte-match
  one bundle version. Provenance requires the reserved source namespace
  macos.pkgutil.receipt.v1, installationRecord kind and a known event date; that
  namespace requires provenance. Invalid combinations reject.
- Stable event ID = SHA256 of JSON string array [subjectID, packageID, packageVersion,
  receipt Unix seconds, bundlePath, bundleIdentifier, ordered bundleVersions...], with
  explicit no-slash-escaping encoding and a fixed test vector. The source is fixed and schema-versioned.
  Repeat observations exclude observation/ingestion time from event identity. On replay
  retain prior ingestedAt and require byte-exact provenance equality. Changed receipts
  produce new events; contradictory IDs still fail. Do not change global generic
  appendDateEvidence replay semantics. Return the retained/new evidence for callers.
- Provenance equality is UTF-8 byte exact. Existing schema-3 JSON without the optional
  field decodes nil; no SQL DDL change or new setting ID. Local backup retains the field.
  Legacy binary unknown-field decoding does not rewrite records on replay; no promise
  of richer metadata display in older versions. No Date added/use/baseline promotion.

## Ownership / risks / recovery
Catalog actor owns its connection/transaction. Reader observations are immutable;
filesystem I/O stays off UI/audio callbacks. Reuse the existing PhysicalKeys formatter for both scan and binding so their physical identity cannot drift. Reuse transaction-internal ledger append
logic rather than nesting transactions. Invalid token/node/provenance, injected write
failure or post-write mutation rolls back. Historical provenance can contain a former
path after a verified move; do not rewrite old records. Current UI source labels and
replacement lineage remain future work; plain Installed must not display this date.

## State completeness
Existing catalog.date_evidence registry group covers additive source provenance.
Presets/DAW projects/undo/external automation/clipboard/sync/telemetry excluded; private
local catalog only. Default nil; old records remain readable; session reset retains
history; local backups included; no import/merge/UI controls. Update policy text for
additive compatibility/privacy. Provenance validation and legacy/new roundtrip tests
must pass. No new state IDs, schema version, settings or accessibility surface.

## Steps and acceptance
1. Independent specification critique; then implement boundary/provenance/binding.
2. Synthetic native tests: observe→bind→reopen→backup roundtrip; replay retains original
   ingestion and count; changed receipt creates a separate record; unknown source times
   never advance dateAdded/lastUsed. Wrong node/format/ID, weak path identity, removal
   intent, unavailable/replaced/changed bundle reject with no writes. Generic ledger
   conflict/rollback behavior remains tested. Frozen old JSON decodes; malformed new
   provenance rejects. Test observed-at future and non-associated observations.
3. Opt-in native real-host-source test via documented swift test filter/environment:
   observe existing FabFilter/Kontakt AU and Diva; ingest only their synthetic scan
   headers into disposable catalog; bind matching records, reject Diva, reopen/replay
   and verify dates/provenance. No user's catalog or installed bundle is modified.
4. Fresh independent source/state review; configured checks and scoped runtime evidence.

## Verification
`python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package`
Add documented receipt-binding-runtime toolchain entry for opt-in native test before
running it. Final docs precede fingerprint-bound checks. Parent
`python3 scripts/workflow_gate.py check-complete` remains open on full feature gates.

## Resume
Implemented Observation, additive typed provenance and atomic catalog binder. Independent
Codex specification critic group_source_review and fresh source/state reviewer
container_review passed (alternate Claude OAuth remained unavailable). Reader, store,
evidence and binding-test hashes are captured in scoped review evidence. Targeted
`swift test` passed 157 tests with the opt-in real-source test skipped; documented native
runtime separately passed against the three installed AU receipts. Final configured
checks are recorded under .workflow/evidence/cleanup-essentials. A test-fixture compile
failure from assigning immutable Asset properties was fixed by constructing the desired
headers; production source compiled on its first run.

Next: source discovery/orchestration and an honestly labeled date projection remain
unimplemented. Do not label a receipt as original Date added or plain Installed. Last
used still needs qualified successful-use adapters for all primary hosts, including
samples and individual library instruments. No automatic catalog migration of receipt
reports, no source enumeration and no user-catalog mutation occurred in this increment. Prior alternate-client OAuth failure means separate read-only Codex
critic/reviewer fallback; parent remains sole writer. No approval requested or needed.
