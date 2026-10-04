# Pro Tools restore usage: local clock and stable event IDs

Status: scoped parser, persistence and native restore regression verified; parent
cleanup-essentials remains open. Risk tier: 2. Owner: Codex bounded QA/test writer.
No native Pro Tools manual-use promotion is admitted.

## Outcome and boundary
Preserve historical Pro Tools restore evidence while replacing the v1 UTC Date
guess and cross-launch ID collisions. New v2 evidence is AAX product history from
an observed completed session restore only. Manual insert, sample use, Kontakt
instrument identity and four-host completeness remain outside this slice.

## Source evidence and design
The native full diagnostic header contains an immutable Digidesign Session Trace
line with PID/version and a Starting Timestamp line with launch monotonic time.
Hash these two lines for a per-run identity; never hash a growing log or its path.
Each Host Instantiate record retains its byte offset and exact raw-line digest.
Its source event ID also binds canonical source-local time and the monotonic
seconds' floating-point bit pattern; the catalog evidence ID additionally
binds the exact subject ID.
The retained reopen-baseline capture is a tail excerpt without launch header, so
it cannot mint new authoritative IDs. Do not prepend a synthetic header and call
that native evidence.

Native anchor 928141.282315 reported 2026-09-26 15:43:16. Event
928141.985707 is nominally 15:43:16.703392 before precision reduction. The
anchor reports whole seconds only, so v2 stores 15:43:16.000000 as a source-local
nominal second and no Date/UTC offset. If ±1 second around a nominal event
crosses a civil date boundary, that event is excluded. Multiple anchors must
agree with monotonic progression within their two-second combined uncertainty;
a conflict invalidates the launch clock. Ordering uses civil day/second, then a
stable run hash, then monotonic seconds within that run, then evidence ID.

## Interfaces and failure policy
ProToolsPluginUse adds optional v2 civil/provenance fields, leaving v1 Codable
payloads decodable. AssetDateResolver validates source/provenance and keeps v1
raw history, but excludes its known-invalid Date from lastUsed. CatalogStore
replays v2 by source/subject event ID and omits v1 from latestHostUsage.
UsageDatePresentation labels v2 as DAW local with unknown time zone.
The existing PutDocumentInfo restore fence is retained. A missing launch
header, missing/contradictory anchor, clock rollback, known
kCantInstantiatePlugIn marker, incomplete terminal line, unsupported completion
grammar or session boundary cannot turn an attempt into v2 use. This is
conservative coverage, not proof that every Pro Tools failure form is known.
Exact unique installed-AAX name binding remains product association, not
stable plugin-instance identity.

## Acceptance and verification
- Synthetic tests cover the observed anchor delta, different machine zones,
  multiple anchors, midnight ambiguity on both sides, conflict, append/replay,
  same-relative-time launches, failure/reset/truncation and v1 decode/exclusion.
- Catalog test covers v2 unique-AAX binding, store/reopen, stable replay and UI.
- Run targeted Swift tests, then configured `unit-tests` via
  `python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests unit-tests`.
- Independent read-only review must confirm v1 remains non-authoritative and
  no manual-use claim slipped in. Native runtime qualification uses the opt-in
  captured restore below; the broader cleanup-essentials runtime gate remains open.

## Native controlled restore — 2026-10-03

Codex QA verified the private `build/date-evidence/manual-protools/runtime-before.log`
full diagnostic snapshot, including its original Digidesign Session Trace and Starting
Timestamp header; no header was synthesized. Snapshot SHA-256 is
`086b8ff591348b73f3b7abc860a03c747a7060f10e482112f20f9fbf48d636ac`. Parsing yields
the three expected restored products: FabFilter Pro-Q 4, Kontakt 8 and Diva. It also
yields one host-internal `AudioInjection PlugIn` Host-instantiation candidate, which
has no unique installed AAX asset. The production collector leaves that row unbound
(one coverage failure per each of the three copied snapshots) and records only the
three unique exact-name AAX products. The known startup `kCantInstantiatePlugIn`
failure for Glow contributes no use.

Before/after manual insert and removal snapshots retain the immutable header and
restore rows. They contain `Host InstantiatePlugIn FabFilter Pro-Q 4 Audio 2` and
`Host FreePlugIn FabFilter Pro-Q 4 Audio 2`, with no `PutDocumentInfo` completion in
that manual delta. Parser output remains identical across all three snapshots, so
manual insertion is not promoted. Accessibility control showed Audio 2 added then
removed while Audio 1, Inst 1 and Inst 2 remained; the session was not saved and its
PTX hash remained `7d278650d24321c83fbd17f833c96643ec18724451d00bae96c976f1000f3217`.

Opt-in test `nativeProToolsRestoreV2Runtime` verifies snapshot byte counts and hashes,
restore candidates, startup failure and manual-use fences, unique installed AAX binding,
record/reopen/replay, and Pro Tools-local date presentation in an isolated catalog.
Exact runner: `python3 scripts/run_check.py --task protools-evidence-v2 --gate
runtime_tests protools-restore-v2-runtime`. It passed one native runtime test at
revision `content:45be3f078fedeb72dc979b862a47d56a2137433bc33960aba20d344c2c249709`;
log and evidence are `.workflow/evidence/protools-evidence-v2/logs/protools-restore-v2-runtime.log`
and `.workflow/evidence/protools-evidence-v2/runtime_tests.json`.

Prior configured full unit evidence remains at revision
`content:73d27734dc9ed56741a4769d00289e288b5e720dd2a9828cd2c502cdaa06fa51` and
records 225 passing tests in `.workflow/evidence/cleanup-essentials/logs/unit-tests.log`.
It was not rerun for this test-only qualification. Neither this scoped runtime result
nor artifact packaging completes the parent four-host cleanup task.
