# Cubase native saved-project restore repair

Status: Implementation and independent code review passed. Final verification and
manual preview status are recorded in .workflow/evidence/cubase-native-restore/task.json.
Driver: Codex coordinator; implementation and independent review: separate gpt-6-sol agents.
Parent: cleanup-essentials. Scoped task: cubase-native-restore. Risk tier: 2.
No unresolved product decision; the user counts restored plugin inclusion without playback.

## Outcome and evidence

Accept the actual completed saved-project load captured on Cubase Pro 15.0.5.121,
bind its exact VST3 product through the existing cache path, and present its date
in the viewer's local timezone. Preserve partial/unknown coverage and historical data.
The user saved a disposable project containing Glow, closed it, and reopened it
without reinsertion or playback. The private before/after snapshots are under ignored
build/date-evidence/cubase-restore-before-reopen-2 and cubase-restore-after-reopen.
They share an exact byte prefix. The after snapshot contains project_added, a keyed
Glow Add, project_activated, and a keyed Load with kErrorNone. The existing compiled
parser returned zero for both snapshots. Native descriptors/status are child rows;
the existing parser expects flattened header fields and a nonexistent native event UID.

The captured Add timestamp 1791077544896 is 2026-10-04T01:32:24.896Z, within
the before/after capture interval, and October 3 in America/Los_Angeles. Current UI
prints the UTC day while labeling it Cubase local. Logic observations also store an
absolute Date and share this defect; Live/Pro Tools store source-local civil time.
Same-family Cubase/Logic events on one day currently fall back to evidence-ID order.

Official host source: https://helpcenter.steinberg.de/hc/en-us/articles/32371744743826-Usage-Logging
Logging is optional and local. The exact grammar/clock is empirically qualified only
for the captured version; unsupported native versions fail closed.

## Scope, ownership, compatibility

Pure synchronous bounded parsing in SimplifyCore; the existing collector owns file I/O
on its utility task, CatalogStore owns ledger transactions, and CatalogModel owns UI
state on MainActor. No new state, Codable field, schema migration, installation, service,
or GUI automation. Preserve CubasePluginUse's completed-load/absolute-Date semantics
and existing immutable ledger. Do not admit manual insertions, samples or instruments.
The earlier manual-reader draft is deferred; no code was implemented for it.

Files: CubaseUsageEvidence.swift plus a small native reader if useful; a shared Core
host-usage ordering/day helper; CatalogStore.latestHostUsage; CatalogModel usage sorting;
UsageDatePresentation; CatalogWindow accessibility help; corresponding Core/Catalog tests;
.workflow/toolchain.json and TOOLCHAIN.md for one opt-in captured-log runtime check;
this plan, docs/HANDOFF.md and the relevant existing usage-clock documentation.
Keep the unrelated cleanup-essentials parent open; scoped gate evidence uses its own ID.

## Native parser contract

1. Select native versus legacy decoding per instance. Presence of host product/version
   metadata fences that instance out of the old flattened path. Admit native only when
   instance_begin identifies Cubase Pro 15.0.5.121 with a nonempty session UID. Preserve
   existing flattened fixtures/history; never mix native children with legacy fields.
2. Native reports have a header (type report, name, nonnegative integer report UID, instance UID, time) and
   adjacent keyed children with the same report UID/session/time. Add keys, exactly once:
   Name, Vendor, Type, Version, Architecture; Type must equal Audio Module Class.
   Load keys: Status Code, File Size, Persistence Time. Their values are strings;
   only Status Code=kErrorNone qualifies completion. Remove uses the Add descriptor shape.
   Assemble/validate each whole group before acting. Missing, duplicate, conflicting,
   extra or foreign child rows cannot qualify. Native report UID supplies identity;
   do not invent a native smtg_event_uid or infer use from window/title events.
3. A project_added(session, project) opens one pending restore window. Collect valid
   Adds before matching project_activated, then emit only after that window's successful
   Load. Manual Adds after activation/completion never enter the pending set. A removal
   before completion removes the matching candidate; malformed/ambiguous removal clears
   pending candidates. Failed Load, project removal/transition, session transition/end,
   mismatched session/project UID, and source clock rollback cancel the pending window.
   Unknown unrelated diagnostic rows cannot supply any required step. No unrelated
   later save/load marker may complete a canceled window.
4. Preserve the Add's raw epoch milliseconds as reportedMilliseconds, not capture time.
   Required events must be ordered by line; equal milliseconds are allowed, regression
   is not. Accept nonnegative bounded timestamps representable by the existing Date
   contract. Native IDs hash a native-restore-v1 domain, session, project, and Add report
   UID with unambiguous framing. Replayed/duplicated identical IDs emit once; reused report
   UIDs with conflicting content fail closed. Append-only valid input preserves IDs.
5. Bounds: 64 MiB input, 100,000 lines, 256 KiB/line; 1,024 UTF-8 bytes/used field,
   256 bytes/UID, at most 8 children/report, 4,096 pending Adds/window. Exceeding a bound
   throws a provenance/limit error, with no partial output. Malformed complete native
   JSON lines/invalid UTF-8 also fail the entire parse. Unsupported native instances
   yield no native events. Ignore an incomplete final line; it cannot complete a report
   or restore. Do not accumulate parser state across calls.

## Date and ordering contract

Add one shared pure helper for host-usage day keys/comparison with an injectable
TimeZone defaulting to current. Cubase and Logic absolute instants use the Gregorian
calendar in that display zone. Live/PT retain exact source-local civil day strings.
After descending day: preserve stable host-family priority for incomparable clocks,
then compare full instants descending within Cubase or Logic. Preserve existing Live
canonical and PT canonical/run/source-second rules; final evidence-ID tie is deterministic.
Use this helper in store projection and grouped model selection so they cannot disagree.
Update Cubase/Logic display, details and accessibility to say local display time, not
an inferred source timezone. Update sort help for the mixed-clock contract. No layout change.

## Ordered work and acceptance

1. Independent critique PASS, then one implementer; an independent reviewer does not
   repair its own findings. Claude CLI was unavailable/unresponsive; record Codex fallback.
2. Add native parsing and regression tests without weakening the legacy restore fence.
3. Centralize the two absolute-Date peers' day/ordering semantics and test their consumers.
4. Run configured checks and opt-in replay, review, package, and have the user inspect
   Glow's restored Last used in the running preview. Do not request another normal-load
   confirmation; the user's done means the specified steps completed normally.

Binary acceptance:
- Native before-reopen/manual controls emit no use; after-reopen emits exactly one
  restored Glow use, bound to one exact current cache class. Hash-check originals and
  prefix; source timestamp falls between captured UTC boundaries. Replay preserves IDs.
- Synthetic failed/missing status, manual Add, activation alone, wrong version/UID,
  malformed/duplicate/partial groups, removal before success, interleaved projects,
  rollback and bounds emit no false positives. Existing legacy restore tests still pass.
- Isolated store record/replay/reopen retains the bound use idempotently. No real user
  catalog or installed plugin is mutated by tests. Duplicate/mismatched cache bindings
  remain rejected. No native failed-instantiation control is claimed.
- UTC-midnight tests in Los Angeles and another explicit timezone prove consistent
  Core/model/presentation dates for Cubase/Logic, later-instant wins on the same day
  even against evidence-ID order, and Live/PT civil days/order remain unchanged.
- User sees October 3 for the captured restore in their local preview and truthful
  completed-project/partial coverage copy. Other four-host acceptance remains pending.

## Exact verification and recovery

Use .workflow/toolchain.json argv: swift build; swift test; CLI integration;
catalog-state; template/adapter integrity; swift build -c release; app-package.
Register cubase-native-restore-runtime as argv ["env", "PRISM_CUBASE_NATIVE_RESTORE_RUNTIME=1",
"swift", "test", "--filter", "nativeCubaseRestoreRuntime"]. It reads only ignored
captures/current VST3 cache/bundle; absent fixtures fail when explicitly enabled, while
generic tests skip the private test. No new GUI harness; user supplies the final UI check.
Run scripts/workflow_gate.py check-complete against the scoped task, not the open parent.

Fail closed on missing/unsupported logs and retain prior ledger evidence. Rollback
the native path/helper changes if validation fails; no migrated data needs reversal.
Bounded synthetic performance is not a million-file or universal-host claim.
Resume: implemented; 233 tests and captured native cache/catalog replay passed.
Independent code review passed after malformed-report and compatibility repairs.
The user supplies the packaged-preview check; consult scoped evidence for its status.

Out-of-scope finding: one full-suite attempt hit the pre-existing randomized Live
binding test's 256-hash search miss; an unchanged rerun passed. That test was not
modified. No universal four-host or manual-insertion completion is claimed.
