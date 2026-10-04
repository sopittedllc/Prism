# Simplify: full codebase, product and competitive audit

Date: 2026-09-25 (local). Product revision: `893196c`; content fingerprint `aa522a91eae75aef541556649d75c9b2afed433c6c571eae5025711156160522`.
Acting client: Codex. Independent read-only reviewers: metadata/discovery, persistence/security, UX/visual; coordinator: architecture, research, benchmarks and synthesis. No product fixes were made.

## Judgment

**Simplify is a credible inventory prototype, but it does not yet deliver its complete product promise.** Its strongest work is conservative discovery, persistent inventory, explicit uncertainty, hierarchical browsing, and reviewed plugin-bundle Trash. Its weakest areas are editable metadata, evidence-backed cleanup, recently added content, scale, and recovery. Passing the current suite does not establish those missing workflows.

The next iteration should begin with correctness and catalog semantics, then metadata and search, rather than another surface-polish pass. Usage feasibility for the four mandatory DAWs should run as a separate critical path: it can invalidate the cleanup promise and must not wait until the end.

No arbitrary deletion or permanent-deletion fallback was established. One narrow removal revalidation defect was reproduced. Full accessibility, real host compatibility, and release readiness are **not certified** by this audit.

## The three user jobs

| User job | Current result | What prevents completion |
| --- | --- | --- |
| Find large content unused for a long time and reclaim space | Not delivered end to end | No validated usage for the required hosts/library instruments; no measured library footprint or reclaimable estimate; no sample/library removal; plugin usage remains Unknown. |
| Find the library installed recently | Not delivered in UI | First-seen observations exist but no Recently added view/date filters; baseline semantics have a defect; installation time is not established. |
| Find an accordion already owned | Partially delivered | Identified patch names/tags and sample names/paths can match with context. No user correction, aliases, metadata facets or global cross-category result list; limited adapters/inference mean missing results cannot mean absent instruments. |

“Not delivered” denotes a planned capability gap, not a regression introduced by the hierarchy increment. PROJECT.md and the redesign plan promise substantially more than the implemented release preview.

## Verified implementation findings

Priorities: P1 = address before wider user testing or relying on the affected claim; P2 = material correctness/recovery/usability problem; P3 = maintenance or lower-impact friction. Grades: E1 source inspection; E2 automated synthetic reproduction or screenshot matrix; E3 packaged native interaction; E4 measured performance. Severity is not a claim of exploitability.

### F01 — P1: “Last used” sorts a different kind of evidence

**Evidence:** E1, `Sources/SimplifyCatalog/CatalogModel.swift:7,276–278`; active comparator `Sources/SimplifyCatalog/CatalogOutline.swift:178–179`; `Sources/SimplifyCatalog/CatalogWindow.swift:176,182–184`.

Choose Individual Samples and select Last used. The comparator uses the latest referencing project's modification date. The adjacent column correctly says Project recency. Saving a project today can make an old sample sort as recent without a new load or playback. This violates an explicit product constraint and could influence cleanup decisions.

**Fix:** one evidence-aware vocabulary for sort, column and inspector; expose sort direction. **Regression:** saved-but-not-played reference fixture; assert all visible terminology and oldest/newest ordering, keeping unknown separate.

### F02 — P1: main-actor tree/search work exceeds an interactive budget

**Evidence:** E4 release-module benchmark, `outline-benchmark.swift` / `outline-benchmark.jsonl`; `CatalogOutline.swift:45–199`, `CatalogModel.swift:73–89`, `CatalogWindow.swift:139–152`. All source paths in this paragraph are under `Sources/SimplifyCatalog/`.

| Synthetic samples | Tree construction | Per-filter range across five repetitions |
| --- | --- | --- |
| 1,000 | 28.5 ms | 1.57–1.66 ms |
| 10,000 | 157.7 ms | 15.58–15.70 ms |
| 100,000 | 1.613 s | 160.21–167.98 ms |

The projection and filtering run on the main actor. Rebuilding indexes invalidates the tree, so streamed inventories and sort changes can cause this work during interaction. Native refresh additionally reloads/collapses/restores outline rows. The benchmark excludes that AppKit work, SQLite, filesystem reads, and JSON fixture construction. It is five repeated queries on one synthetic shape, **not p95, an end-to-end latency claim, or a million-file benchmark**. Nevertheless, the measured main-actor work alone is sufficient to establish a responsiveness problem at 100k samples.

**Fix:** build/query immutable snapshots off the UI actor, index searchable fields, coalesce superseded updates and apply bounded UI diffs. **Regression:** named 100k-instrument/1m-sample fixtures, end-to-end query p95 and worst UI stall, peak memory, cancellation, and audio-session interference. Current scanner caps prevent even reaching the million-sample target in one ordinary scan.

### F03 — P2: unrelated setup changes hide offline inventory

**Evidence:** E2 direct compiled-core probe: initial sample scope = 1 asset; same scope with root offline = 1 stale asset; add an empty Projects root = 0 assets. `Sources/SimplifyCore/CatalogStore.swift:9–16,69,98,140–147`; `Sources/SimplifyCatalog/CatalogModel.swift:211–243`.

All root categories contribute to one exact scope key. A change to project locations makes the retained offline sample/library membership inaccessible in the active scope, even though its asset root remains configured. Previous database data and audio still exist; this is inventory disappearance, not physical deletion.

**Fix:** carry forward observations for retained asset roots while separately scoping project evidence and ownership. **Regression:** disconnect an indexed drive, add/remove only a project root, rescan/reopen, and retain stale, removal-ineligible content.

### F04 — P2: baseline can remain open indefinitely

**Evidence:** E1 source chain plus E2 missing-root scan. `Sources/SimplifyCore/CatalogStore.swift:69–70,107`; `Scanner.swift:139–144,161–162`; `Models.swift:88–94` (latter two in SimplifyCore).

A scope becomes complete only when the whole report has no issues. Missing optional standard plugin directories and unsupported project formats produce issues. A machine with a permanently absent optional folder can therefore keep marking later arrivals as baseline. This already corrupts the meaning of stored observations, although the recent-additions UI is still future work.

**Fix:** track inventory completeness by root/capability; distinguish expected absence, unavailable configured roots, and project-reader coverage. **Regression:** inventory with an unsupported project or absent optional plugin root can establish its appropriate baseline; a later asset is nonbaseline. Do not weaken unavailable-drive handling to achieve this.

### F05 — P2: a plugin changed internally can pass removal revalidation

**Evidence:** E2 unchanged removal implementation with a synthetic bundle and injected non-destructive callback. `Sources/SimplifyCore/PluginRemoval.swift:12–17,43–45,64`; `Sources/SimplifyCatalog/CatalogModel.swift:312–313`.

After capturing a bundle identity, modifying its nested Info.plist left the root identity equal, validation returned no error, and the injected Trash operation ran. Root directory device/inode/mtime/ctime do not prove unchanged descendants. A vendor updater can modify the reviewed installation in place.

**Fix:** revalidate bounded bundle metadata and executable identity/version immediately before removal and accurately describe residual race guarantees. **Regression:** nested plist and executable overwrite as well as root replacement. This finding does **not** imply arbitrary-path deletion or traversal into descendant symlink targets. Confirmation, explicit paths, and Trash still constrain the operation.

### F06 — P2: mixed-player directories split into duplicate libraries

**Evidence:** E2 CLI fixture, `Sources/SimplifyCore/LibraryDiscovery.swift:105–111`. A folder with Accordion.nki, Banjo.dspreset and Cello.dspreset produced three libraries: one Kontakt and two same-named Decent Sampler groups, each with one instrument; zero issues.

Once a directory belongs to one player, each alternate-player patch becomes its own fallback group. **Fix:** unresolved group identity = proposed boundary + player, retaining distinct products where stronger evidence exists. **Regression:** exactly two groups with correct membership, independent of filename ordering and overlapping roots.

### F07 — P2: malformed Soundpaint parts silently vanish

**Evidence:** E2 CLI fixture, `Sources/SimplifyCore/LibraryDiscovery.swift:112–113`; `LibraryMetadata.swift:80–85`. Recognized Soundpaint structure plus malformed Parts/Broken/info.json yielded zero instruments, an empty issues array and successful exit.

Nil conflates malformed, unavailable, oversized, unsupported and unrelated metadata. **Fix:** return a scoped adapter result with reasons and coverage; retain valid siblings and prior stale content. **Regression:** invalid JSON, excessive size, missing required fields, unreadable file and mixed-validity libraries must report incomplete coverage.

### F08 — P2: Scan details can remain permanently stale

**Evidence:** E1, `Sources/SimplifyCatalog/CatalogWindow.swift:365–369`; `CatalogModel.swift:388–394`. Open Scan details while scanning: its text is assigned once and is not rebound when scanning finishes. It can continue claiming coverage is pending.

**Fix:** live diagnostics model or explicit timestamped snapshot with refresh. **Regression:** open during discovery, finish with a known issue, and see final coverage without reopening. The existing screenshot matrix does not exercise this window's transition.

### F09 — P2: refreshing overrides user column widths

**Evidence:** E1, `Sources/SimplifyCatalog/CatalogWindow.swift:178–180`. Every refresh reapplies size/format widths, including search and streamed inventory updates.

**Fix:** separate category defaults from user-adjusted presentation state. **Regression:** resize a column, type a query, receive scan updates, switch category and return; preserve the declared width policy.

### F10 — P2: compact layout truncates the identity needed to judge matches

**Evidence:** E2 screenshot matrix: `sample-search-breadcrumbs.png` abbreviates the distinguishing root; `library-metadata-search.png` abbreviates Library metadata match. `CatalogWindow.swift:58–60,91–99,178–180`; `CatalogTheme.swift:84,99` under SimplifyCatalog.

Fixed side regions and mandatory mostly-unknown columns constrain the meaningful name/context column. Full inspector text and tooltips mitigate the issue but require selecting/inspecting each result.

**Fix:** prioritize responsive identification columns, allow inspector resizing/collapse, and use concise persistent root/match indicators. **Regression:** same-name items differing only in the middle of their root path, metadata-only matches, minimum width, both appearances. Do not mistake honest Unknown values for useful default columns.

### F11 — P2 recovery gap: scans cannot be canceled

**Evidence:** E1, `Sources/SimplifyCatalog/CatalogModel.swift:198–264`; `CatalogWindow.swift:185`; `Sources/SimplifyCore/Scanner.swift:14–188`. A retained scan task exists but no cancellation interface or cooperative scanner checks exist. The ten-second transition changes presentation only.

Accidentally choosing a broad/cloud/network root leaves the user unable to stop the work or change locations without quitting. **Fix:** cooperative cancellation, phase boundaries and clear retained-results policy. **Regression:** cancellation during discovery, bounded reads, matching and pre-commit; keep prior good catalog and reenable controls. Incremental checkpoints/resume are a separate unfinished capability.

### F12 — P2 recovery gap: preserved corrupt catalog has no user recovery route

**Evidence:** E1 plus native corrupt-catalog fixture, `Sources/SimplifyCore/CatalogStore.swift:34–41,125–134,232–240`; `Sources/SimplifyCatalog/CatalogModel.swift:138–144,194,257,316–318`; `catalog-save-error.png`.

Rejecting and preserving unreadable data is correct. But repeated scans retry the same DB, reset only clears session state, backup is API-only, and failed removal-intent persistence prevents plugin removal. The UI gives a notice without a quarantine/rebuild/export route.

**Fix:** explicit recoverable storage state with safe backup/quarantine and user-reviewed rebuild; preserve the original. **Regression:** corruption, read-only storage, disk full, restart and successful recovery. This is not evidence corruption is frequent.

### F13 — P2: completion checks do not validate report integrity

**Evidence:** E2 `evidence-integrity-probe.json`; `scripts/workflow_gate.py:104–142`. A copied otherwise-valid completed task still returned no completion errors after its code-review evidence was changed to reference a nonexistent report and invalid hash. The active task and original evidence were not changed.

The checker validates the evidence envelope's task/gate/status/revision but not the backing report's existence/hash, check outcomes, or full evidence schema. `record_gate.py` writes a hash, yet completion never verifies it. This does not prove previous reviewers were wrong; it weakens the enforcement supporting their results.

**Fix:** validate schema, check results and referenced artifacts/hashes at completion and commit; compare revision in commit checks too. **Regression:** missing/tampered report, failed nested check, malformed schema, and stale revision must fail. Keep human review quality separate from these mechanical checks.

### F14 — P3: durable product status is stale

**Evidence:** `PROJECT.md:15–20,78–86` and the resume block in `.work/active/library-catalog-redesign.md` still describe implemented hierarchy/persistence boundaries as proposed or outstanding. The per-increment evidence is more current.

**Fix:** one capability matrix with Implemented / Synthetic-verified / Real-host-verified / Planned states; update the umbrella resume. **Regression:** release/readiness review must trace each claim to present evidence. Documentation consistency matters when recovering interrupted development.

## Metadata: architectural audit and required contract

Current data is a useful discovery projection, not yet a metadata management system. LibraryMetadata contains player/maker/summary, aggregate tags, a source string, identity evidence and instruments. Instrument tags are plain strings. Sample Asset records have name/path/format/basic size/classification; no corresponding editable sample metadata. `LibraryMetadata.swift:31–46,60–63,138–155`; `Models.swift:6–24`.

The positive boundary is real: maker/product context is inherited separately from sibling instrument tags; an Ark piano does not acquire every string tag in the parent search summary. Manifest/vendor-backed identity differs from proposed ownership. SQLite identities, instruments, physical memberships and observations are a useful foundation. Neither automatically establishes complete dependencies or editability.

Current weaknesses:

- A source paragraph cannot express per-field provenance, confidence, conflict or rejection. Tags cannot distinguish user authority from vendor or filename inference.
- Filename inference uses a small whitelist and token/plural matching. Camel-case, abbreviations, vocabulary aliases, articulation, loop/one-shot, BPM/key and embedded audio metadata are not a robust resolver. SINE keyword richness is reduced to that whitelist; Soundpaint tags follow a different path.
- There is no durable user override/suppression model, bulk edit/undo, reconciliation UI, portable metadata export/import or tag vocabulary management.
- Search is a case-insensitive substring, not facet intersection, multi-token ranking or semantic retrieval. Samples search full absolute paths, so unrelated ancestor directory names can create broad matches. Libraries match patch names/tags independently from product metadata and correctly label metadata-only results; retain that distinction.
- Needs identification has no correction action. An explicitly proposed library can remain permanently unresolved from the user's perspective.

Recommended next contract, before drawing an editor:

| Concern | Required representation/behavior |
| --- | --- |
| Identity | Logical product/instrument IDs separate from installation and physical member IDs; retain raw names and mutable locators. |
| Evidence | Field/tag assertion stores entity, normalized value, raw value, source kind/reference, adapter version, observation time, and confidence/status where meaningful. |
| User authority | Explicit override/suppression wins over derived evidence. Rescanning never silently resurrects a rejected tag or replaces a manual name. |
| Inheritance | Apply only declared parent context; never copy aggregate sibling instrument tags to a child. Explain inherited values in editor/search. |
| Vocabulary | Structured maker/player/type/articulation/tempo/key facets plus free custom tags and scoped synonyms; distinguish instrument bass from register and bass drum. |
| Search | Index effective metadata; combine terms/facets predictably, rank exact instrument matches, preserve breadcrumb and match reason. |
| Editing | Single and bulk edits show mixed/inherited values, preview changes, undo, and survive restart/rescan/relocation. Store locally; no source audio/NKI rewriting by default. |
| Portability | Versioned export/import with stable identity and explicit unresolved/conflict handling. Backup/recovery precedes reliance on irreplaceable user edits. |

This is a bounded domain extension, not a reason to build an arbitrary schema engine. Add only the entities needed to implement and test the first editing workflow. Optional web enrichment comes after local overrides/provenance, and should produce reviewable suggestions rather than silent metadata changes.

## Competitive comparison

“Plug Station” is interpreted as **Plugin Station** (the product already referenced in this repository). Sources were checked during this audit. These are documented capabilities and public interface patterns, **not hands-on competitor test results**. No competitor is presumed to solve universal historical DAW/library usage.

| Product / role | Documented capability relevant here | Lesson for Simplify |
| --- | --- | --- |
| [Plugin Station](https://www.pluginstation.app/) — plugin management | Installed-plugin management, storage views, system profiles, update awareness, archival and restore workflows. [Official release notes](https://github.com/julianworden/PluginStation) also describe format-aware uninstall selection, bulk operations and installed-plugin filters. | Provide an actionable storage/format management flow rather than only inventory. Preserve our distinction between bundle removal and complete vendor uninstallation. Avoid copying license/shop/support breadth outside the product's intent. |
| [Sononym tagging](https://www.sononym.net/docs/manual/tags/) — metadata authority | Separates manual/automatic/custom tags, supports aliases and bulk assignment, distinguishes mixed selections, and preserves removal of an automatic tag across refresh. | Closest reference for durable user overrides, suppression, understandable inheritance and bulk editing. A flat string list is insufficient. |
| [Kontakt browser](https://docs.native-instruments.com/ni-tech-manuals/kontakt-manual/en/browser-and-presets) — library/preset navigation | Product and preset separation; Brand, Sound Type and Character filters; favorites, auditioning, and user-preset tag editing including bulk editing. | Keep the new hierarchy, add facets and useful metadata editing. Kontakt writes user-preset tags to preset files; Simplify should retain its local-catalog policy rather than copy that storage behavior. |
| [Splice search](https://support.splice.com/en/articles/8652594-finding-sounds) — sample retrieval | Keyword/filename/tag search with instrument, genre, loop/one-shot, BPM and key filters and selectable ordering. | Make common musical questions expressible without guessing filenames. Local Splice downloads are files; downloading them does not establish access to Splice's online metadata. |
| [XO](https://www.xlnaudio.com/products/xo) — fast sample audition | Similarity-organized one-shot browsing, filtering, auditioning and drag-out workflow. | Preview is a strong next step for sample identification; its beat-making engine is outside Simplify's core promise. |
| [Atlas](https://algonaut.audio/manuals/atlas/2_0_2/map.html) — collection exploration | Sample maps group sounds by sonic characteristics; samples can be previewed on click/hover, navigated by keyboard, and marked favorite. | Useful reference for fast evaluation and keyboard browsing; a spatial map is optional, not a prerequisite for trustworthy inventory. |

Plugin Station's public homepage/release notes do not establish reliable historical last-use tracking for arbitrary library instruments. Do not frame Simplify as merely needing to copy such a feature. ADSR Sample Manager's official page could not be retrieved (403), so it was excluded from verified feature claims. The Plugin Station FAQ exposed only partial answers in the retrieved page; no offline/account limitations are inferred from missing text.

**Positioning recommendation:** a local, trustworthy inventory across plugins, samples and composer libraries, with explainable metadata and conservative cleanup evidence. Plugin Station sets a management benchmark; Sononym/Kontakt/Splice set metadata/retrieval benchmarks. The opportunity is joining these jobs coherently, not duplicating every competitor feature.

## UI and workflow assessment

The current shell is coherent; category separation, native disclosure, explicit stale labels and search context are understandable. The English light/dark/minimum/typical screenshot matrix showed no blocked destructive confirmation. Cancel is the Return default in the removal confirmation; exact selected locations, bundle-only scope and Trash recovery guidance are good.

The visible hierarchy overstates workflow maturity: most usage/storage columns cannot yet differentiate results, tags are read-only paragraphs, and the next action after identifying a sample or library is usually Finder. The inspector spends substantial space on wrapped absolute paths and repeated caveats while project dependencies can fall below them. Prefer identity and useful metadata first, evidence second, expandable physical details third. Keep uncertainty concise and inspectable.

Manage locations reopens step zero of onboarding (`CatalogWindow.swift:355–358`, `SetupWindow.swift:6,41–45,77`), including first-scan copy. A dedicated recurring location-management surface should share the same validated setup model without replaying the tutorial. Favorites/protection and a batch review queue would aid return visits and cleanup; neither is implemented. Sample preview is a competitive opportunity, not a required DAW-hosting feature.

Accessibility evidence is limited to native roles/labels, Command-F, disclosure keys, some setup focus checks and non-color status text. Full keyboard-only flows, native folder picker, VoiceOver traversal/announcements, focus restoration across every sheet, measured contrast, text scaling, reduced motion/transparency and RTL remain unverified. Duplicate-root Remove controls currently use only the last path component in their accessible name (`SetupWindow.swift:107`), warranting a concrete screen-reader fixture. The UX reviewer had source access and is **not** an artifact-only accessibility certification session.

## Architecture, reliability and privacy

Sound boundaries: Swift package separates Core, Catalog UI, app and CLI; no third-party package downloads; system SQLite/zlib. SQLite access has one actor owner, parameter binding, transactional inventory writes/read snapshots, schema/application-ID validation and bounded rows/bytes. Corrupt/newer data is preserved. New catalog storage uses private filesystem permissions. Scanning does not load plugins, modify vendor metadata or send inventory to a service. Parsers bound regular-file reads, XML entities, gzip expansion and nesting; symlink/FIFO defenses are meaningful.

Pressure points: CatalogModel combines scan orchestration, persistence restoration, projection caches, reference association and removal coordination. Scanner combines traversal, discovery and reference matching. This remains manageable in a small prototype, but incremental indexing and editable metadata need explicit result/state contracts rather than more callbacks and string statuses. Main-actor full snapshots are already measurable debt (F02).

Storage totals are not yet unique physical/logical/allocated/reclaimable measurements. Shared archives, hard links, partial downloads, offline files and APFS clone uncertainty must be handled before presenting space savings. Moving to Trash does not itself free that space; preserve that distinction. Bundle-only removal must never masquerade as uninstalling support content, licenses or vendor managers.

The local package is ad-hoc signed preview software. The deployment floor is macOS 13, but this audit ran macOS 26.7 arm64. Older OS, Intel, distribution signing/notarization, updates and a distribution privacy/permission experience are not verified. No new network feature or personal-data export was exercised; raw local inventory paths should remain private. Charity association/donation details remain unresolved product scope, not a blocker to local technical testing.

## Test evidence and coverage limits

The separate read-only installed-discovery probe also passed: 3,065 plugin-format candidates, five factory Ableton projects, 466 reference candidates and two expected absent standard roots in 18.448 seconds. These are format installations/candidates, not unique products or validated project dependencies; only aggregate results are retained in the audit report.

The documented debug build, **69 Swift tests**, CLI integration, template controls, adapter consistency and catalog state checks passed. Release build, packaging and native synthetic smoke passed on the audit baseline. The native fixture covers 3,000 samples and 32 screenshots, setup/search/hierarchy/offline/error states and generated-plugin Trash. It is not a representative vendor-content or four-host compatibility test. Native hooks were not available; direct deterministic commands were run.

| Area | Reviewed/executed evidence | Important limit |
| --- | --- | --- |
| Core discovery/metadata/parsers | All Core modules; related fixtures; new synthetic probes | No new controlled host-generated save/load matrix. |
| Catalog/identity/removal | Store/model/setup/removal sources and tests; two new safety probes | No force-quit/power-loss series, real updater race or privileged Trash scenario. |
| UI | All Catalog/App UI sources; 32 images; freshly passing native smoke | No full manual/assistive traversal or arbitrary interaction automation. |
| Performance | Release outline/filter probe at 1k/10k/100k | No full-app p95, million files, peak memory or audio-session interference measurement. |
| Build/tooling | Package, packaging, CLI checks, CI declarations, state/evidence scripts | Local results do not prove hosted CI or notarized distribution. |
| Competitors | Official pages/manuals/release notes | No installed trials or feature parity certification. |

Mandatory DAW status: REAPER resolves matchable sample references; Ableton and Logic expose partial unresolved candidates; Cubase and Pro Tools do not have implemented project readers. No library-instrument usage matcher establishes the user's required coverage. See `docs/research/usage-validation-matrix.md`. No host is promoted from “synthetic parser fixture passes” to “validated unused-content detection.”

The existing suite mainly proves delivered increments. New findings show missing cross-feature tests: changing source configuration while offline, persistent optional-root warnings, nested bundle changes, mixed-player fallback grouping, rejected adapter diagnostics, long-running diagnostics windows and large UI datasets. The evidence checker itself also needs adversarial tests (F13).

A case-different REAPER-path mismatch was investigated and **disconfirmed** on this machine; it is not included as a defect. No precise contrast failure, arbitrary deletion, universal vendor compatibility or competitor last-used capability is asserted without evidence.

## Recommended remediation order and exit criteria

1. **Correctness and trust:** F01, F03–F07, F13; actionable scan/storage recovery F11–F12. Exit with reproductions converted into regression tests, accurate evidence labels, offline scope continuity and complete adapter diagnostics. Preserve the existing safe Trash boundary.
2. **Catalog responsiveness:** F02 plus cancellation/update coalescing; fix F08–F10 through shared state/layout policy. Exit with measured end-to-end latency and peak memory on named large fixtures, responsive search/resize during scans, and persistent user presentation choices.
3. **Metadata and retrieval:** implement the local assertion/override/suppression contract, shared editor, facets and ranking. Exit with single/bulk edit, undo, rescan/restart/relocation and export/import tests; accordion queries explain both matches and known coverage gaps.
4. **Recent additions and storage:** expose first-observed versus baseline/newly indexed/installed evidence; calculate unique physical and reclaimable storage with progress and limits. Exit with reconnected-drive, root-change, version-update, shared-container/hard-link and partial-download fixtures.
5. **Cleanup delivery:** use validated per-host/per-asset evidence, protected items, a review queue, dependency display and only ownership-proven removal. Exit with all four required hosts separately validated where promised, explicit unsupported states and synthetic recovery tests. Run usage feasibility in parallel with earlier steps rather than deferring discovery of impossible assumptions.
6. **Broader release gate:** artifact-only keyboard/VoiceOver and accessibility matrix, oldest supported OS/Intel policy, installer/notarization/update testing and truthful capability documentation. Optional audition improves discovery after metadata correctness; shops, license management and a beat sequencer are outside the near-term scope.

Audit completion means this assessment and its evidence are delivered. It does not mean the listed defects are fixed or the application is ready for public release.

## Composer-focused extension requested during the audit

The confirmed target is film/TV/game composers using Spitfire, Orchestral Tools and Cinematic Strings. The researched metadata priorities, evidence limitations, query examples and New to explore / Try next proposal are in [COMPOSER-DISCOVERY.md](COMPOSER-DISCOVERY.md), with [vendor research](metadata-research.md) and [interaction/state specification](acquisitions-design.md). These are proposed product work, not audited existing features.
