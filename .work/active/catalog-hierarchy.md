# Catalog hierarchy and contextual search

Status: implementation finished; final verification and review evidence tracked in .workflow/active-task.json. Acting client/implementer: Codex.
Task: catalog-hierarchy. Risk tier 2; UI-UX and stateful-feature.
Base: e913dc7. Third increment of library-catalog-redesign.md.

## User outcome
Browse Libraries as maker → library installation → instrument and Individual Samples
as selected root → real directories → audio file. Search Accordion exposes the actual
matching patch with its parent context. Clear search restores browsing position.

## Current evidence and scope
SQLite catalog and ownership foundations are committed. CatalogWindow still displays
flat Asset rows and lists up to 100 library instrument names in a text inspector.
LibraryMetadata already contains maker, product evidence and individual instruments.
Plugin product grouping/removal and the current visual shell are established contracts.

This increment implements hierarchical presentation and search over existing discovery
evidence. It does not add vendor adapters, editable tags, size measurement, install/use
dates, cleanup recommendations, automatic scans, or sample/library removal. Separate
physical installations remain separate library rows even for equal vendor IDs. No
articulation children are invented. Proposed/unresolved libraries appear under a clearly
named Needs identification group; they never impersonate verified products.

## Interfaces and semantic inventory
- New CatalogOutline.swift: immutable presentation nodes, pure deterministic projection,
  per-item search matching, breadcrumb/parent context and physical source locator.
- CatalogModel: invalidate derived hierarchy on report/category/query/sort; own session
  outline state and reset. Preserve legacy selected asset for plugin removal/sample evidence.
- CatalogWindow: NSOutlineView, native disclosure and keyboard navigation, group/library/
  instrument/folder/sample inspector, scoped selection, truthful columns and counts.
- CatalogTheme shared cells retain 38pt height, 8pt text inset and semantic colors.
- App smoke, catalog tests, state registry/check, design system, state policy and this plan.
- Semantic peers: all collection tabs, search/no-match/clear, category/sort changes,
  saved/live/partial/offline states, Finder reveal, inspector and plugin format controls.

## Design decisions
Makers and selected sample roots start expanded; libraries and nested directories start
collapsed. Library children are instruments only. Unknown installed size says Not measured;
instrument size says Shared with library. Last used stays Unknown for libraries/instruments.
No tiny metadata-file size is used as library footprint. Plugin columns remain unchanged.
Sample folders are derived only from paths of discovered files within configured roots;
empty/unscanned directories are not invented. Overlapping roots use the most specific
configured root and never duplicate a file. Equal root basenames use a distinguishing parent suffix; full
root path and volume locator are available in details.

Library search includes matching instruments and just their ancestors. A library-only
metadata match is explicitly labeled and does not manufacture matching installed patches.
Search prunes unrelated siblings. Sample search is flat, with result kind and relative
breadcrumb in row/details. Search expansion is separate from browsing expansion. Clearing
or switching away and back preserves each category's browse selection/expansion. Sorting
reorders siblings; refresh/rescan preserves stable node selections where identity exists.
No filesystem work on selection/search. Resolve known physical Finder paths only; no
fake maker/group location. Existing cached-removal checks remain authoritative.

## State and compatibility
One new registry field outline_state (object, empty default) records session presentation
selection and explicit expansion/collapse per category, with temporary search context.
It is excluded from presets, project persistence, migration, undo, automation, structured
clipboard, sync, analytics and export/import; reasons match navigation state. Reset clears
it. Native accessibility and local privacy included. Existing setup/catalog schemas unchanged.
Derived trees and indexes are recomputable caches, not additional settings. Old setup
fixtures must still load and defaults/IDs must match feature-registry exactly.

## Risks and mitigations
Identity collisions: encode structured identity components; preserve distinct installations
and duplicate patch titles/paths with vendor IDs. Search false positives: inspect individual
instrument tags, never propagate sibling aggregate tags. Live refresh: reconcile stable IDs
and physical locators when first persistence assigns IDs; avoid wiping browsing state during
search. Offline content stays stale. Tree construction/sort is cached, no disk reads on UI
refresh. Large indexed search targets belong to later indexing work; measure this increment
on 3000 samples and a synthetic multi-library/multi-instrument fixture. No real files moved.

## Implementation and acceptance
1. Critic pass; verify native outline API against official docs/installed SDK.
2. Node projection and registry-backed navigation state, focused fixtures.
3. Native outline, contextual inspector, search/selection/expansion restoration.
4. Native keyboard/disclosure and light/dark/compact state matrix; fresh independent reviews.
AC1: golden Kontakt/SINE-like metadata yields distinct makers/products/instruments; proposed
content is separate, shared-container products and equal instrument titles never merge.
AC2: Accordion matches its patch with maker/product context, excludes unrelated patches;
metadata-only match is explicit; clearing search restores prior browse selection/expansion.
AC3: sample tree mirrors configured roots and relative folders; overlapping roots dedupe;
flat search retains locator/breadcrumb; duplicate folder names on different roots stay distinct.
AC4: selection displays parent library and truthful shared/unknown size/usage; native disclosure,
arrow-key navigation, refresh/category/sort restore, cached/offline states and plugin removal
regression pass. Group selection has no false Finder target.
AC5: exact registry/default/reset and schema compatibility checks, release packaging, full
unit/integration suite, synthetic native smoke, source/UX review and completion gate pass.

## Verification and runtime
Use exact argv keys in .workflow/toolchain.json: build-debug, unit-tests, integration-tests,
template-integrity, adapter-integrity, catalog-state; then build-release, app-package,
catalog-runtime. Do not run template-integrity during native fixture creation/deletion.
Commands: python3 scripts/run_check.py --task catalog-hierarchy --gate automated_tests
build-debug unit-tests integration-tests template-integrity adapter-integrity catalog-state;
python3 scripts/run_check.py --task catalog-hierarchy --gate runtime_tests build-release
app-package catalog-runtime; python3 scripts/workflow_gate.py check-complete.
Native target: current Apple Silicon Mac; minimum and typical windows, light/dark, empty,
search, populated, cached, stale, error, keyboard expansion/collapse and selection restoration.
Capture hierarchy/search/breadcrumb evidence. Existing cached 3000-file restore <2 seconds
remains. Full VoiceOver, older OS/Intel and million-file indexed performance remain unverified.

## Recovery and gates
Presentation only; database schemas unchanged. Revert this increment to restore flat UI.
Any source change reruns affected tests and review, all final evidence binds current content.
No product decisions unresolved. No tier-3 action except a gated local checkpoint intended.
Alternate Claude client currently unauthenticated; use independent Codex critic/reviewer.
Native hooks unavailable in this session; run deterministic gates explicitly.

## Resume
Projection/state, native outline/inspector and regression fixtures are implemented.
The verification suite includes 69 Swift tests and native library/sample hierarchy,
contextual search, metadata-only matches, keyboard, restoration and removal regressions.
Consult revision-bound gate evidence for final results; next product increment is editable
metadata. No additional hierarchy features are planned within this task.
Out-of-scope: metadata editor, usage validation, measured storage and recurring discovery.
