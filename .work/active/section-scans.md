# Section scans and simpler plugin browsing
Codex implementer; tier 2 within cleanup-essentials. Independent spec critic passed.
Outcome: no separate Tag settings, automatic standard plugin roots, extras configurable,
Scan refreshes captured active section, one Soundtoys product row with formats under name.
Non-goals: usage adapter/size calculation/removal redesign. Preserve metadata and files.
Evidence: local read-only Soundtoys plist shows com.soundtoys.<format>.DevilLoc[Deluxe].
Do not merge by name alone; verified namespace+product distinctions remain required.

Architecture: full configured scope retained; explicit scannedKinds execution mask gates
scanner traversal and library discovery. Projects scan with Samples only. Store ingests
only observed kinds, advances generation for previously fresh unscanned memberships,
children and members without advancing observation dates, preserves stale states and
project evidence. Baselines only update scanned kinds. Optional ScanIssue.kind owns new
diagnostics; old unowned diagnostics conservatively remain until a full scan. No DB
schema change. Progress/final merging retains untouched sections; failures retain live
results. Dirty category tracking clears only completed targets. Capture category at click.

UI: remove Tag settings popover/sidebar. Online fetch opt-in lives in Settings preserving
privacy; editing available via selected item context menu, pills remain primary.
Production startup migrates standard_plugins false to true; isolated demos/tests retain
explicit overrides. Setup no checkbox. Plugin format column hidden, summary under name.

State policies: execution kinds/dirty categories are transient session state; no preset,
persistence, migration, undo, automation, clipboard, sync, telemetry or export. Existing
roots, online_tags remain registry-owned. ScanIssue optional owner defaults nil for old
catalog/report JSON; no invented ownership. Catalog freshness policies preserved.

Files: Scanner/Models/CatalogStore/PluginProduct, CatalogModel/Window/SetupWindow,
app runtime, tests, state/UI docs. Risks: false stale/fresh updates, sample/library overlap,
wrong cross-vendor merges, lost project evidence, forgotten unscanned folder changes.
Acceptance: targeted scans preserve other sections in memory and restart; nested roots
retain exclusions; stale inactive objects remain stale and fresh remain fresh without
new lastSeen; offline target retained stale; target captured during tab switch; save
failure preserves untouched data; Soundtoys formats collapse with Deluxe/vendor separation.

Verification: scripts/run_check.py --task cleanup-essentials --gate automated_tests
build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity
build-release app-package; runtime_tests catalog-runtime. Independent source/visual review,
read-only installed Soundtoys identity probe. Native hooks/alternate client unavailable;
deterministic commands and independent Codex roles used. Parent release work remains open.
Resume: implementation next; root sole writer.
