# Collection locations and visible paths

Acting client: Codex, implementer. Tier 2 reversible UI, within cleanup-essentials;
independent Codex spec critic PASS (alternate client unavailable in this session).

Outcome: replace the awkward four-step setup with one native configuration sheet;
show actual selectable locations in the inspector. No new persistence, tracking,
metadata semantics, removal behavior or scan behavior.

Evidence: user screenshots show repeated headings/cards and unused space. Inspector
currently substitutes a parent basename for the selected path.
Research: Apple HIG onboarding recommends fast optional setup with defaults;
macOS Login Items and Time Machine exclusions use selectable lists with add/remove;
Logic Sound Library settings present location configuration directly.
Sources: https://developer.apple.com/design/human-interface-guidelines/onboarding
https://support.apple.com/en-ge/guide/mac-help/-mh15189/mac
https://support.apple.com/en-au/guide/mac-help/-mh15622/mac
https://support.apple.com/en-gb/111094

Implementation: SetupWindow native Type/Folder table, standard-plugin checkbox,
Add menu with all four kinds, selected removal, Cancel/Scan. Bounded scrolling;
full paths distinguish names. Preserve discardable draft, atomic save, existing
session fallback and defaults. Inspector bounded selectable wrapping paths with
one matching Finder button per plugin installation. No-location groups hide it.

Interfaces: SetupWindow controls and native smoke; CatalogWindow location component;
UI design docs. No persistent state added: existing roots/toggle policies unchanged;
selection, draft, error and focus transient, no export/sync/analytics/presets.

Risks: clipping, wrong Finder target, accidental acceptance, failed save losing draft.
Acceptance: compact empty/mixed/overflow setup; all categories visible; Cancel leaves
model untouched; save error keeps draft; session fallback works; selected removal
retains focus; real paths selectable, format destinations unambiguous.

Verification exact commands through scripts/run_check.py, task cleanup-essentials:
automated_tests build-debug unit-tests integration-tests catalog-state
template-integrity adapter-integrity build-release app-package;
runtime_tests catalog-runtime. Fresh independent source/visual review required.
Native hooks unavailable; deterministic gates used. Parent usage scope stays open.

Resume: spec passed, implementing. Rebuild isolated fake-data demo after verification.
