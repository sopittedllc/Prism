# Persistent catalog foundation

Acting implementer: Codex. Required independent Codex critic/reviewer; alternate
client runner unavailable. Second increment of library-catalog-redesign.md.

## Outcome
Open Simplify with the last saved inventory while fresh scans run. Persist normalized
library/instrument/content relationships and first/last-seen observations. Current
results vanish on quit; only setup.json persists. Ownership foundation is committed.

## Scope and boundaries
SimplifyCore/CatalogStore.swift: actor-owned SQLite operations off main actor; connections
never cross isolation. Version 1, application ID, transaction for initialization and each
scan ingestion. Tables for nodes (asset headers), instruments, physical memberships,
scope snapshots and observed membership. Not a single serialized report cache. Existing
ScanReport is a compatibility projection reconstructed from rows. Project evidence stays
per-snapshot serialized until incremental DAW adapters arrive.
Stable UUID node IDs resolve through vendor ID where proven, otherwise volume UUID +
inode + birthtime for existing nonlinked local files, otherwise a path identity explicitly
limited to that locator. First seen survives a verified same-volume move, vendor-ID move,
reopen and rescan. Do not merge by display name. No cross-volume reconciliation claims.
Old/offline nodes are retained, never deleted by absence or partial scans; only nodes seen
in a completed scan are updated. A latest snapshot merges earlier same-scope members,
marks unseen records stale, and never calls them currently installed. Different selected
root sets get distinct snapshots; changing folders must not restore unrelated scope.
First scan/new scope is a baseline, not installation time. Additions qualify only after a
prior issue-free scan of the identical scope; otherwise first seen is newly indexed.

CatalogModel + App startup: asynchronous restore; stale-load guards prevent late cache
from replacing a new scan or different setup. Only final scan commits; progressive
inventory never replaces durable results. Cached plugin identities are stripped and
cached assets cannot authorize removal. Live scan stays usable if saving fails; a visible
status explains persistence failure. Successful reviewed plugin removal must not resurrect
cached copies on restart. Reset clears session view only and cancels stale restore.

Private app-support database (0700 directory/0600 file), bounded busy wait, reject symlink
or special-file paths and unsupported/corrupt schema without overwrite. SQLite rollback
journal handles interrupted writes; backup API provides a consistent local export with
no implicit upload. No migration from session-only inventory; existing setup is untouched.
Version-1 frozen SQL fixture + future-version/corrupt/rollback/backup tests. Future schema
migrations require a pre-migration backup; no speculative v2 schema in this increment.

Authoritative CatalogPersistenceRegistry enumerates logical persisted fields and full
cross-cutting policies alongside existing settings registry. Exact ID/default coverage
check extends catalog_state_check.py. Derived inventory is not a preset or DAW project;
no sync/analytics; reset view retains catalog; no UI tag editor/undo yet. Import/merge and
editable overrides remain later steps, not an empty promise in current schema.

## Steps / acceptance
1. Critic pass; verify SQLite transaction/version/backup and Apple volume UUID docs.
2. Store + versioned contract/normalized reconstruction; deterministic failure tests.
3. App/model async restore/save and cached/stale safety; state registry coverage.
4. Reopen/move/offline/partial/corrupt/newer/schema0 rollback/backup/model race fixtures.
5. Release/package/native runtime, independent source/completeness review, workflow close.
AC1: Reopen reconstructs assets/instruments/memberships and first seen; identities survive
same-volume rename and distinct vendor collections sharing a file stay separate.
AC2: Partial/offline scans retain earlier members with stale state, never resurrect removed
plugins, never treat first baseline/new roots as recent installations.
AC3: Atomic rollback, unsupported/corrupt/special files preserved; backup roundtrip.
AC4: App restores asynchronously without overwriting fresh scans/settings, writes only
final results, shows persistence errors, and disallows cached removal.
AC5: Registry full policies and exact IDs; automated tests, package and native smoke pass.

## Non-goals / resume
No outline browser yet (next), no full incremental scanner/checkpoints, no edited tags,
no new usage adapters, no storage totals, no removal of real user audio. Catalog graph
is deliberately the inventory subset; usage/dependency/override entities arrive with
those features. Query scaling and million-item indexed search remain separate targets.

## Exact checks
swift test; swift build -c release; python3 scripts/build_app.py;
build/Simplify.app/Contents/MacOS/Simplify --ui-smoke captures/catalog;
python3 scripts/run_check.py --task persistent-catalog --gate automated_tests integration-tests template-integrity adapter-integrity catalog-state;
python3 scripts/workflow_gate.py check-complete.
Runtime uses disposable database and generated audio/plugin fixtures only.

## Sources
https://www.sqlite.org/lang_transaction.html (atomic commit/rollback and busy behavior)
https://www.sqlite.org/pragma.html#pragma_user_version (application-managed schema version)
https://www.sqlite.org/backup.html (consistent database snapshot export)
https://developer.apple.com/documentation/foundation/urlresourcekey/volumeuuidstringkey

Critique clarification: logical product identity is a separate product_key on nodes;
node UUID identifies an installation observation, resolved by vendor key PLUS verified
physical identity (or path fallback), not vendor key alone. Two same-vendor assets at
separate physical locations stay distinct. Same-volume moves preserve node UUID through
physical evidence. A vendor-ID-only move is not reconciled; prior observation stays
stale until reconciliation is supported. For current SINE adapter a node is an aggregate
observation anchored at its representative metadata file, not a claim that every mic
is a distinct installation. Physical member rows retain all known locations. Replacing
that anchor without physical proof retains a stale prior observation, never silently
merges installations. Asset adds optional catalogID; library selection prefers that ID
when persisted. Golden duplicate-vendor/different-location fixture is mandatory.
AC1 vendor-ID move wording is superseded by this conservative physical-evidence rule.

Review repairs: baseline lives per scope membership, not solely on shared nodes.
Physical member reconstruction reads normalized membership rows and retains unobserved
paths with per-member stale evidence. Scoped instrument/header payloads prevent a scan
of different configured roots from leaking content into an earlier snapshot. Persistent
removal intent precedes Trash; failed operations become visible in cache after rescan.
Native smoke now measures 3,000-sample restore and checks cached removal controls and
post-removal reopen. Existing semantic controls carry saved/stale/error copy, so UI-UX
review gates apply despite unchanged composition.

## Resumed verification after outage
Codex resumed from uncommitted implementation and historical review reports. Claude
CLI is installed but not authenticated, so independent Codex review remains the
available alternate lens. No simultaneous product writers. Native hook enforcement
was not exercised; deterministic run_check/record_gate/workflow_gate commands provide
the recorded gates.

Added explicit preservation of a populated foreign schema-0 database and a successful
pending restore versus changed scope/new scan regression. The initial native run caught
a fixture-only persistence failure: Foundation retains the /var symlink even after
resolvingSymlinksInPath, and the store rejects linked ancestors. Native smoke now uses
the same disposable home-cache fixture convention as core tests, and asserts the save
before testing reopen. Application storage and symlink refusal remain unchanged.
Architecture/setup documentation now describes durable inventory separately from setup.
Fresh UX review also identified stale setup-screen copy and a zero-kept cached format
summary. Both semantic peers now describe persistence and distinguish installations
that need a scan. Native smoke adds saved/light/compact, offline library/instrument,
stale plugin-format and corrupt-catalog notice cases; inspect their captures before close.

Resume from this task's evidence and gate state. Once all applicable checks pass,
continue with the native maker/library/instrument outline specified in
library-catalog-redesign.md. Do not equate this persistence increment with editable
metadata, validated usage history, or sample/library removal.
