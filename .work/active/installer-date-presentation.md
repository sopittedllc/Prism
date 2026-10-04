# Plan: visible, sortable installer evidence

**Status:** APPROVED — independent Codex critic group_source_review
**Owner:** Codex coordinator/implementer (sole writer)
**Task ID:** cleanup-essentials
**Last updated:** 2026-09-26
**Risk tier:** 2; user intent explicit
**Domains:** ui-ux, stateful-feature, persistence projection

## Outcome and non-goals
Show retained installer evidence consistently in plugin table, inspector and format
sheet. Header clicks sort actual receipt dates. Date added and Last used remain
independent/unknown; no new source qualification, original-acquisition badges, settings,
raw-path emphasis or new navigation. Samples/libraries/instruments do not inherit
plugin/player evidence. No user-catalog changes during verification.

## Research and semantic inventory
Independent Codex ux-architect usage_feasibility researched Apple HIG Lists and tables
(https://developer.apple.com/design/human-interface-guidelines/lists-and-tables), Finder
sorting (https://support.apple.com/en-my/guide/mac-help/-mchlp1745/mac), System Information
installation history (https://support.apple.com/en-ca/101591), and App Store purchase
history (https://support.apple.com/en-ie/118212). Three comparable workflows consistently
name different date meanings separately. HIG supports meaningful headings/reversible
native sorting; System Information includes updates. Separate acquisition from installer
history is a project inference, not a user-study result. No copying brand styling.

Consumers: CatalogWindow column title/cells/AX sort help/widths/inspector; CatalogModel
sortDates/caches/status/first-found copy; PluginFormatsWindow per-installation rows;
CatalogOutline ordering; source ledger and collector completion; synthetic app smoke
assertions/captures; model/store tests; COLLECTION_AND_SETUP/design-system/visual matrix.
Existing table Installed/inspector dates are hardcoded Unknown; sortDates is empty.
Receipt evidence is durable and collected after plugin saves but no projection exists.

## Contract and implementation
1. CatalogStore.latestInstallerRecords(for nodeIDs, asOf) reads one transaction/connection,
   validates every requested node/history, and returns latest typed package-receipt
   installationRecord per byte-exact node (Data keys). <=2,048 requested IDs, <=100,000
   records total; existing per-node/payload bounds remain. Missing node/corrupt history/
   exceeded bounds throws, never partial valid-looking output. Stable source/event UTF8
   tie-break for equal event times. Deduplicate input and coverage by exact node bytes; group ties use node/source/event byte order. Old generic evidence has no receipt provenance and
   does not become this macOS-specific projection. No SQL schema change or I/O in cells.
2. Model asynchronously reloads the projection after restore, successful scan persistence
   and collection completion. Read generation plus receipt/scope generation prevent late
   results after reset/new scan/settings/removal. Cache keys are exact node bytes. Clear
   cache on reset; prune on valid new result. Read failure clears untrusted projection
   and exposes Unavailable, distinct from source collection incomplete (which preserves
   historical evidence). Loading retains already read historical dates; absent values say
   Checking. During plugin inventory itself suppress dates until current node IDs settle,
   because streaming rows temporarily reuse previous IDs. Cache changes invalidate both
   flat/outline ordering while preserving selected identities and expansion state.
3. Shared presentation derives latest date across actual product installations, known/
   total installation counts, per-installation provenance and status. Do not require all
   formats to have evidence before displaying a qualified historical record. Never
   propagate one format's record into siblings. Stale/offline records remain historical,
   with current installation explicitly unverified. Known history survives failed source
   collection; unknown rows state incomplete coverage instead of never installed.
4. Plugin header **Installer record**; samples/libraries **Date added** remain Unknown.
   Same existing column ID/sort enum keeps interactions stable. Plugin dates use localized
   numeric date style using the user’s locale ordering, first click newest then oldest, unknown/checking/error
   after dates in either direction. Stable name/identity ties. Group rows blank.
   Header width must show title/sort indicator; adjust shared compact widths rather than
   hide Last used/size. Native minimum1040 and default1220 layouts runtime checked.
5. Inspector: Last used / Date added / Size facts; plugins additionally Latest installer
   record, source format and Records for X of Y installations. One concise explanation:
   “May record an install or update; not original Date added.” Per-format rows show their
   own date + package version; package IDs/full timestamps in accessible selectable
   inspector text or format-row help, not only hover. No new Technical details sheet.
   First-found detail must stop blanket-claiming installation records unknown.
6. Native table cell accessibility help states full date, evidence meaning and installation
   coverage; visible inspector supplies partial coverage without relying on tooltip/color.
   Checking/incomplete/read-error states are text. Existing Scan retries. Announce source
   completion once via existing refresh/status, not per row; preserve focus/selection.

## State coverage and recovery
Existing catalog.date_evidence group includes derived cache/loading/read-error and
coverage. No persistence/default-schema changes. Reset clears transient presentation,
keeps immutable ledger. Preset/project/undo/automation/clipboard/sync/telemetry excluded;
private local paths/provenance only; backup includes ledger, not caches. Accessibility
now included for visible source/date/status. Registry and docs updated. No mutation of
source history on presentation errors. No underlying usage claim or removal authority.

## Verification and acceptance
- Specification critic before implementation; independent fresh source/state and UI review.
- Store tests: latest/ties/byte identity, unknown, corruption, batch bounds and reopen.
- Model tests: mixed formats/date sorting both ways/unknown-last, exact source coverage,
  no sample/instrument leakage, reload on restore and collection completion; reset and
  late reads cannot reintroduce stale dates; error/partial/offline behavior.
- Native smoke uses synthetic ledger records and actual header clicks, checks retained
  selection and full inspector/format-source text; light/dark1040/1220 captures and AX
  labels/help. Existing neighboring setup/tag/removal/state flows remain verified.
- Existing automatic native source+model test verifies real receipt date is projected.
- Commands from toolchain:
`python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package`
`python3 scripts/run_check.py --task cleanup-essentials --gate installer_date_runtime catalog-runtime automatic-receipt-runtime`
Capture/inspect relevant light/dark states and obtain independent review. Final content
edits precede fingerprint-bound checks. Parent check-complete remains open for full
Last used/Date added/source coverage; scoped evidence cannot close those gates.

## Resume
Implementation and source/state review passed; final native and full verification are
recorded in installer_date_runtime/automated_tests evidence. Open format sheets preserve
shared status and resolve current-node freshness; regression covers captured old assets.
Next product increment: qualify actual-use sources across the four primary DAWs.
Alternate Claude OAuth previously unavailable; independent read-only Codex
fallback roles. macOS current native target; older OS/Intel and human VoiceOver remain
unverified, not claimed by this change. No unresolved product decision or approval needed.
