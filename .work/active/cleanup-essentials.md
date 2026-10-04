# Cleanup essentials: reliable usage first, then size and removal

Status: DRAFT; driver Codex; risk 2; domains ui-ux, stateful-feature. User has authorized implementation: paths are secondary, installed formats/size/last-used and quick deletion are core. All four hosts (Logic Pro, Pro Tools, Ableton Live, Cubase) are required for usage; no single-host substitute.

## Outcome
User priority, reaffirmed 2026-09-25: reliable last-used is the single most important capability and a release gate across all four hosts. Prove the usage routes before further UI polish. This applies to plugins, individual samples and specific library instruments; player activity alone is insufficient.

The collection supports storage decisions: names, installed formats, measured size, actual usage evidence and direct reviewed removal. Existing search/metadata remain available, without dominating plugin details. Actual last-used coverage must not be fabricated from scan, installation, access or modification timestamps.

## Ordered work
1. Validate host-generated positive and negative usage signals in Logic Pro, Pro Tools, Ableton Live and Cubase. Document exact identity, event outcome, timestamp and coverage. Research observations are recorded in `docs/research/usage-feasibility-2026-09-25.md`.
2. Obtain independent specification critique of the concrete adapter contract before product implementation. Build bounded adapters and a persistent evidence ledger only for demonstrated semantics; synthetic tests alone do not admit a host.
3. Verify exact sample and library-instrument attribution separately from plugin identity. Expose unavailable history and coverage gaps without treating them as inactivity.
4. Deliver measured size, visible formats and direct reviewed removal using the contracts below, then refresh the isolated demo and run the full verification/review sequence.

The numbering of the implementation contracts below groups requirements, not priority. Usage proof is first. No claim of feature completion is permitted while required host/asset coverage remains unverified.

## Evidence and interfaces
Current scanner sets directory sizes nil. Plugin view hides size and format columns; inspector prints paths. Plugin formats panel requires another confirmation. Libraries have candidate roots and SINE content memberships, not universal ownership. Existing PROJECT and host research distinguish saved-project proxies, attempted restores and confirmed observed loads. Applicable code: Models, Scanner, LibraryDiscovery/Metadata, PluginProduct/Removal, CatalogModel/Outline/Window/PluginFormatsWindow; new footprint/evidence helpers; native smoke/demo and fixture tests; registries/design docs.

## Implementation contracts
1. Read-only bounded size measurement on scan worker: allocated file bytes and logical file bytes, deduplicated by device/inode inside a measurement; symlink targets never followed; no audio payload reads, cloud downloads or plugin execution. Plugin bundle measurement; sample file measurement; library candidate-root measurement labeled folder size (not ownership/reclaim promise), or known explicit SINE content paths labeled partial known-content size. File/entry/time budgets bound each traversal; inaccessible/changed/limited roots yield partial or unavailable, not zero/complete. Shared hardlinks/clones do not promise equal reclaimable space. Do not sum overlapping library sizes into a collection reclaim estimate. Existing per-asset optional Codable observation fields allow older payloads to decode; persisted under catalog.inventory.
2. All collection views show size; plugins show grouped AU/VST2/VST3/AAX/CLAP, total of measured format sizes with partial state if any unknown. Enable size sorting for plugin and library parent rows. Instrument size remains Shared, with parent folder size in details. Cached/offline size says last measured. Keep paths and raw identification in an explicit Details action; basic inspector leads with formats, size and usage. Source evidence remains inspectable. Compact layout hides lower-priority technical columns, not size.
3. Add direct Remove… action for plugin product and per-format controls in the existing panel. One confirmation identifying product, formats, number of installations and measured size; Cancel default; no filesystem paths required for ordinary confirmation, explicit Details available. Reuse one confirmation/execution path and current durable removal-intent/identity checks. Never remove real audio during testing. No sample/library deletion expansion without verified ownership. Strengthen plugin review identity against nested bundle changes before streamlining removal; bounded metadata-only subtree signature, no content execution/hash reads, fail closed if identity cannot be established.
4. Usage research/implementation track: inspect official and redacted local evidence for all four hosts. Implement only validated positive-event adapters with timestamp/host/source/outcome/identity and coverage. Reject scan/validation/failed restores and ambiguous names. Persist evidence separately from derived scan timestamps, surface coverage and latest proven event; saved-project modification remains Project recency. Missing historical data stays unknown with source-specific reason. Prospective collection, when feasible, is explicitly Last observed loading with tracking start; not retroactive history. No blanket claim of all-four coverage without real-target validation.
5. Refresh isolated fake-data demo using same product UI; sizes must be measured synthetic payload sizes. Any synthetic usage examples visibly Demo evidence, never injected into real catalog or represented as real history. Leave demo open for user review after checks.

## Acceptance and verification
- Sizes include nested plugin files, deduplicate hardlinks, reject symlink traversal, retain partial/unavailable states, survive catalog reopen; library size never implies deletion ownership.
- Product formats and size visible at compact/typical widths; file paths appear only through secondary details or Finder.
- Direct removal has one explicit confirmation, Cancel default, exact same reviewed installations; nested changes fail closed; failure leaves item and retry explanation; cached/offline entries cannot remove.
- All four host routes documented with primary sources and positive/negative fixtures where implemented. Actual usage completion requires controlled host validation (loading vs validation/failure; timestamp anchoring; plugin/instrument identity). Missing host/install/fixtures are concrete open work, not a passed usage gate.
- Exact toolchain checks via .workflow/toolchain.json: build-debug, unit-tests, integration-tests, catalog-state, template-integrity, adapter-integrity, build-release, app-package, catalog-runtime. Native controls/captures and independent source/UX review required; current Mac scope stated. Deterministic scripts replace unavailable native hooks.

## State, compatibility and recovery
Footprint and usage observations belong to catalog inventory/evidence, not presets/DAW state. Optional fields default unknown; old catalog retains readability. Root configuration, metadata edits and existing scope-baseline semantics unchanged. All new persistent fields require runtime/documented registry coverage; metadata edits retain Undo. Derived observations are non-undoable; removal uses Finder Trash restoration and rescan. No sync, telemetry, uploads or privileged background installation; errors preserve prior catalog and live UI. SQLite writes remain transactional; existing schema backups and future-version rejection retained. No distribution release.

## Risks / non-goals / resume
APFS sharing prevents exact reclaim promises; disconnected drives prevent new measurements. DAW evidence is fragmented and may not exist before tracking; no inferred never-used status. Reject speculative universal last-used claims. Existing unrelated audit debt and v2 exploration queue remain out of scope. Plan critique next; independent researcher investigating all-four usage feasibility. Prior v1 implementation/evidence and current demo preserved.


## User-directed UI increment
Subsequent testing feedback explicitly requests tag-first presentation, visible Installed
and Last used fields, and a usage filter now. `.work/active/asset-priority-ui.md`
defines this increment while actual host validation remains pending. Its completion
must not be presented as completion of the parent usage requirement.
