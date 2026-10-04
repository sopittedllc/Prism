# Simple browsing — Codex coordinator / implementer

Outcome: one names-and-tags search; native column-header sorting toggles direction;
concise Your Sound inspector with Location beside Show in Finder.
Non-goals: usage adapters, measured library/plugin sizes, removal redesign, new metadata providers.
Parent cleanup-essentials remains pending independently.

Current evidence: CatalogWindow contains six toolbar rows, fixed-direction sort popup,
facet/recent/usage popups, and duplicate inspector prose plus a Technical details sheet.

Design: remove those browsing controls and recent badges. Keep online tag fetching in
an explicit Tag settings popover (existing preference, cancellation and retry semantics).
Columns Name, Format, Size, Installed, Last used (samples: Project recency, explicitly a
project-modification proxy). Native sort descriptors toggle alphabetical ascending first,
numeric/date descending first. Stable name/id ties; unknowns last both ways. Sort only
siblings, keep groups ahead of items. Plugin format sort uses displayed product formats;
instruments have no independent known storage. Installed remains Unknown; do not use
first-found as installed. At compact sizes Format moves to the inspector unless actively sorted; dates and size
remain visible. Horizontal scrolling is retained for user-expanded columns. Selection/expansion survive sorting. Search includes names, maker names,
and effective tags, excludes paths/classification/player prose.

Inspector: format once in subtitle; all effective tags without provenance repetition;
Last used / Installed / Size concise facts; useful library context/index coverage;
Location row plus Finder, short parent-folder label with full path tooltip. Edit tags and
conditional Undo/Manage formats. Source provenance stays accessible in tag settings for
selected products; no Technical details sheet. Offline state remains visible.

State: sort_reversed is session-only false by default (each sort uses its useful default
unless reversed). Registry covers reset, accessibility/privacy and explicit exclusions
for persistence/migration/presets/undo/automation/sync/export/analytics/copy-paste, matching
sort policy. Popover is transient presentation, no serialization. Legacy model facet and
recent APIs remain for internal tests, with no UI entry; normal UI starts and clears them.

Order: independent spec critique; shared sort/search model; controls/inspector; update
native smoke and behavioral tests; source/visual review; rebuild and launch isolated demo.
Affected: CatalogModel, CatalogOutline, CatalogWindow, main native smoke, catalog tests,
state registry/design docs; no core persistence schema changes.
Risks: unknown ordering, sibling false matches, selection loss, compact clipping, stale
popover state. Verify sizes/categories/light/dark, header click twice, search and clearing,
selection after sort, edit/undo/search, tag fetch settings and failure behavior.

Commands (toolchain): python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package
Runtime: python3 scripts/run_check.py --task cleanup-essentials --gate runtime_tests catalog-runtime
Use existing parent runner without claiming parent completion. Fresh read-only review of
source and actual captures required. Rebuild synthetic demo; real audio untouched.
Resume: implementation not started. Cross-client CLI unavailable in this session;
independent Codex critic/reviewer fallback, native enforcement replaced by exact gates.

Specification: independent Codex simplify_spec PASS with the criteria above.
