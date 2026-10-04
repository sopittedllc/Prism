# Plan: reliable four-host usage evidence

**Status:** A and scoped B1/B2/B3 IMPLEMENTED; remaining qualification open — remaining B–E research-gated; parent open
**Owner:** Codex coordinator and sole writer
**Last updated:** 2026-09-26
**Task ID:** cleanup-essentials (scoped implementation milestones; parent remains open)
**Risk tier:** 2
**Domains:** host compatibility, evidence integrity, local persistence
**Base fingerprint:** content:1da02999e5ab48da5f98b640d6262d3f313bb75bb2fdfe56ab789dacbdb1be5b

## User outcome
Reliable Last used for plugins, individual samples and individual library instruments
across Live, Cubase, Logic and Pro Tools, supporting informed storage cleanup.
Saved inclusion counts without playback. Unknown must never become unused.
This is the execution plan following four-host-evidence.md, not a claim of completion.

## Research and resources
- Existing synthesis: docs/research/four-host-evidence-2026-09-26.md.
- Controlled host results: .workflow/evidence/cleanup-essentials/CONTROLLED-HOST-CHECKPOINT.md.
- Clean Cubase controls: .workflow/evidence/cleanup-essentials/CLEAN-CUBASE-CHECKPOINT.md.
- Author CPR reader and MIT license pinned to c324cdc82548cc05e9453cd12a30ccae7551768f:
  https://github.com/fgimian/cubase-project-plugins/blob/c324cdc82548cc05e9453cd12a30ccae7551768f/src/reader.rs
  This validates length-token layout, not active ownership. Retain attribution/license.
- Steinberg format change: https://helpcenter.steinberg.de/hc/en-us/articles/31885407408018-Cubase-Nuendo-Invalid-project-after-saving
  Format changed in 13.0.30; a CPR signature alone is not a compatibility claim.
- VST3 persistence: https://steinbergmedia.github.io/vst3_dev_portal/pages/FAQ/Persistence.html
  Opaque processor state has no universal dependency manifest.
- Kontakt API: https://docs.native-instruments.com/ni-tech-manuals/kontakt-api-reference-manual/en/instrument
  Mutable display names do not identify an NKI. No verified source-path getter found.
- Official Pro Tools Session Info exports already generated: plugin removal control
  works; Avid export is a stronger next ingestion route than guessing PTX structures.

## Current-state evidence
Live direct VST3 candidates implemented, 98 tests previously passed; exact usage
remains Unknown. Logic metadata provides sample candidates. CPR/PTX unsupported.
Clean Cubase 15.0.30 files give 10/123/100 typed records; baseline has three expected
third-party plugins, removed has two. Four Diva labels survive removal. Old template
contains many additional descriptors, so global matching does not prove ownership.
Kontakt loaded/empty compressed-state research distinguishes a program display name
but FilenameTable v3 and exact source identity remain unsupported. Pro Tools official
exports distinguish the three baseline plugins from the two after removal.

## Product decisions / non-goals
Intent is clear; no further permission needed for local implementation and read-only
fixtures. No release, uploads, real content deletion, SDK installation, or hidden host
automation. No timestamp guessed from project mtime, file access or inventory scans.
Do not expand this increment to UI redesign or a persistent event ledger.

## Implementation sequence and exit criteria
1. **A — Cubase diagnostic reader (implement now).** Promote private one-off probe
   to a tested Swift diagnostic API and explicit CLI command. Never connect global
   descriptor results to ProjectReport, catalog matching, Last used or cleanup.
   This is reusable extraction infrastructure, not production Cubase usage support.
2. **B — Ownership and four-host acquisition.** On isolated host copies validate
   Cubase renamed track, bypass, multiple instances, removal, rack/instrument tracks,
   alternate/retained state and embedded descriptor decoys. Admit current membership
   only after a sourced structural owner can be followed. If unavailable, use host
   interpreted export with explicit coverage, not global byte matches. Implement
   Pro Tools official text-export ingestion with baseline/removal and media-pool
   distinctions; establish Logic active alternative and AU container boundaries;
   extend Live racks/master only with positive and negative controls.
3. **C — Exact asset identity.** Match format identifiers without executing plugins;
   distinguish ambiguous/missing IDs. Kontakt: rename, replace, two instruments,
   removal, same-name different files and browser-only controls. Validate supported
   filename-table framing; unsupported versions remain unresolved. Sample relocation
   and collected copies require explicit identity policy; filenames are insufficient.
4. **D — Timestamp and persistence contract.** Measure each host's observable event
   clocks using load, failed load, validation, save-only and rescan controls. Separate
   saved inclusion from timestamped observed events. Specify source revision/identity,
   deduplication, stale/offline behavior and scan concurrency before creating a ledger.
   Register state and migration tests. Removing current membership preserves proven
   historical events; scanning/reopening the catalog never creates usage.
5. **E — Product integration and end-to-end qualification.** Show reliable usage and
   its coverage, independently test all 4 hosts × plugin/sample/library instrument,
   rescan/restart/offline/removal controls. No release until the whole matrix passes.

Later stages require their own detailed admission critique when research resolves
interfaces; this plan is not permission to guess undocumented formats.

## A: detailed interface and admission contract
New Sources/SimplifyCore/CubaseDiagnostics.swift exports immutable Sendable/Encodable
report and descriptor values. CubaseDiagnostics.inspect(URL) reads synchronously,
read-only through BoundedFile; all ancestors reject symlinks. parse(Data) is pure.
No shared mutable state, callbacks or background work. Explicit CLI
`--inspect-cubase-descriptors FILE` produces only a diagnostic report, not a scan.

Budgets: 32 MiB input (existing policy, unchanged), 4,096 descriptor records, tokens
at most 255 bytes from author's layout. Linear marker search; bounded output.
Only observed RIFF/RIF2 with exactly one PAppVersion token sequence declaring Cubase
Version 15.0.30 is admitted; other app/version/header rejects. Metadata gating is
itself exploratory and not proof of owner or global format validity. Name/UID tokens
must be valid UTF-8, nonempty after whitespace check; UID exactly 32 hex characters.
Original Plugin Name takes precedence when present. Bounds, malformed tokens and
record limit fail the whole diagnostic: no silently salvaged successful subset.
Preserve record byte offsets and repeated descriptors, with no dedup or instance count
claim. Include input digest, adapter version, observed host version, diagnostic-only
coverage and explicit ownership/usage/timestamp limitations. No event or asset ID.

Plain Diva labels do not become descriptors. A complete typed descriptor embedded
in unrelated state **will** be a diagnostic candidate; test this limitation explicitly
and verify normal ProjectReader CPR reports remain unsupported with no references.
Do not claim this heuristic distinguishes opaque payload from active records.

CLI: success 0 only means diagnostic extraction; parse/read errors 2 and stderr,
no report; malformed command 64. Explicit help text. All local paths remain private.
No personal session bytes or machine paths in committed tests/docs. Synthetic fixtures
model researched token framing, not a purported full valid CPR schema.

## Interfaces and files affected in A
Sources/SimplifyCore/CubaseDiagnostics.swift; Sources/SimplifyProbe/main.swift;
tests/SimplifyCoreTests/CubaseDiagnosticsTests.swift; scripts/probe_smoke.py;
scripts/build_app.py (include attribution in local app resources);
docs/research/four-host-evidence-2026-09-26.md; third-party attribution notice;
this plan and .workflow/active-task.json. No changes to ProjectReader admission,
CatalogModel, saved catalog schema, UI or installed assets.

## Risks and recovery
Untrusted binary lengths/version changes: bounded reads, strict tokens and rejection.
False ownership: diagnostic output isolated by type/API and CLI, tested scanner
non-admission. Large old template is over budget: reject; streaming budget design
belongs to B, not an ad hoc limit increase. Memory bounded by input plus output and
one byte-buffer copy. No parser execution on audio threads. Preflight ancestor symlink checks (not race-resistant traversal), final-component
O_NOFOLLOW and regular-file bounded I/O; no source mutation. Remove only this increment if needed;
retain existing uncommitted work. macOS 13 target; real runtime here Apple Silicon.

## Compatibility and cross-cutting state coverage
No persistent state ID introduced. Presets/default/reset/migration/undo/automation/
copy-paste/sync: not applicable (explicit ephemeral diagnostic only). Project/catalog
persistence excluded by design. Accessibility not applicable to CLI JSON. Privacy:
local explicit input/output only, no analytics/network. Export included via diagnostic
JSON; import not supported. Later ledger must satisfy STATE_COMPLETENESS.md separately.

## A: acceptance and verification
- [x] Native parser reproduces all 233 records (UID/name/offset) from private clean
  fixtures and unchanged before/after hashes; records host version and content digest.
- [x] Synthetic controls: no-name false positives; original-name override; duplicates;
  embedded-descriptor limitation; bad/unknown/conflicting metadata; empty/invalid UID
  and names; truncated tokens; malformed matching record; input and count bounds.
- [x] File boundary: missing, directory, symlink and symlink ancestor rejection.
- [x] CLI success/error/invalid arguments and input immutability verified; normal CPR
  scanning and inspect-project remain unsupported, so Last used cannot change.
- [x] Independent specification critique and fresh code review pass.
- [x] Configured build-debug, unit-tests, integration-tests, catalog-state,
  template-integrity, adapter-integrity, build-release, app-package gates pass.

Exact configured checks through runner:
`python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package`
Runtime: native CLI built above against private controls (JSON retained in ignored
build/usage-controls); compare every record and source hash to reviewed probe output.
No UI change; existing failed catalog-runtime remains a separate parent gate. Native
hooks unavailable: use deterministic scripts. `python3 scripts/workflow_gate.py
check-complete` must report parent truthfully; do not mark C3 or parent complete.

## Gate dependencies / out-of-scope findings
A source/test/doc edit invalidates the content fingerprint and downstream checks.
Review after implementation; rerun changed checks after repairs. Parent criteria on
size/removal/UI and macro usage remain open. No unrelated defects repaired here.
Cross-client attempt previously failed expired Claude OAuth; independent Codex critic
and fresh reviewer are the available fallback, with provenance recorded.

## Resume notes
A implemented after passing independent usage_plan_critic review. Fresh independent
cubase_diagnostic_review found no blockers and replayed all 233 real descriptor
records with unchanged hashes. Six new tests bring the suite to 104; CLI integration
passes. Test fixture corrected to use workspace scratch because macOS temporary URLs
can traverse /var. An earlier ignored Kontakt research console log mislabeled JSON
was preserved inside a valid JSON wrapper to satisfy repository-wide JSON checks.
All eight configured checks passed; native debug and release replay matched all 233
records each, preserved hashes/mtimes, and rejected the oversized old template.
Evidence is recorded under the parent task. A has no GUI or
catalog behavior change. Next action is B's ownership experiment specification and
host-interpreted export comparison; C–E remain research-gated. Parent stays open.


### B1 follow-up
The [Cubase track-archive increment](cubase-track-archive.md) now extracts plugin
references with explicit exported-track owners. Baseline/removal/renamed-duplicate
controls yield 3/2/4 references. Original Plugin Name and UID preserve identity when
the display Plugin Name changes with a track rename. This is partial export evidence,
separate from native CPR diagnostics and the catalog. Independent review and 109 tests
pass; full Last used qualification remains open.

### B2 follow-up
Cubase group-insert extraction is implemented with the exact host-observed owner
signature. Native bypass/disabled controls retain references; group add/remove changes
five to four references. A critical coverage control shows output-channel inserts
are omitted from the selected-track export even when selected. The report explicitly
states that limitation; neither export absence nor native global diagnostic records
establish non-use. Final B2 evidence is recorded separately under the parent task.
The macro Last used deliverable remains open; next admission must address acquisition
and source association, with Pro Tools text-export evidence available for a scoped
adapter. No further UI polish replaces this work.

### B3 follow-up
[Pro Tools session-text evidence](pro-tools-text-evidence.md) now reads optional
plugin/file/clip lists with explicit section-presence coverage. Native controls show
three→two listed plugins after removal, unchanged one-file/two-clip media pools.
The installed Avid 2024.10 guide distinguishes audio EDLs from these pools and defines
user timestamps as timeline positions, so neither pools nor those timestamps become
Last used. Raw HFS-style locations, plugin labels and instance summaries remain
unresolved. Independent critique/review passed; 116 tests and exact debug/release
native replay cover this increment. Macro acquisition, exact asset identity, source
association, timing and catalog integration remain open.

### B4 follow-up
[Pro Tools audio-track events](pro-tools-track-evidence.md) now distinguish timeline
placement from media-pool membership. Native mute/clear controls retain two events
when muted, zero when removed from track, while file and clip pools remain present.
Within-export unique-name links retain ambiguity and never resolve installed assets.
Independent source review, 124 tests and debug/release native replay passed. No exact
use time or project association is inferred; ordinary catalog admission remains off.

### Priority correction and activity research — 2026-09-26
Acting client: Codex, researcher/coordinator. Last used and Date added are coequal
release priorities, per explicit user direction. The next increment investigates
qualified host events and installation evidence before adding more project parsers.
No production timestamp provider has been admitted by this research.

- In a controlled Pro Tools session switch, the removed instrument's executable
  remains mapped in the same host process. Polling mapped binaries cannot refresh
  Last used or establish current session membership.
- The corresponding local log distinguishes startup scanning, track-associated
  InstantiatePlugIn, and FreePlugIn records. The removed instrument has a FreePlugIn
  record and no new instantiation in the removal control, while the retained two
  products have new instantiation records. This is promising event evidence, not yet
  proof of successful use: completion semantics, asset identity, wall-clock anchoring,
  rotation, duplicate ingestion, and failures remain admission requirements.
- Read-only pkgutil receipt queries found installation timestamps and file lists
  matching three installed test products. Receipts can describe updates/reinstalls;
  they do not establish original acquisition. Direct file-info lookup returned no
  ownership for the tested bundles. Validate receipt ownership and installed version;
  nested helper bundle plists must not become independent plugin installations.
- A synthetic local URL-resource experiment preserved creation and directory-added
  dates through same-directory rename and modification. This does not establish
  installation semantics or behavior on other filesystems. Existing catalog firstSeen
  remains discovery evidence only, with its initial-inventory baseline preserved.
- User reports Pro Tools detects a new plugin without restarting. Avid's
  [Audio Plug-Ins Guide](https://resources.avid.com/SupportFiles/PT/Audio_Plug-Ins_Guide_2023.3.pdf)
  documents restart-free availability for activated Marketplace installations.
  General third-party installation and the reported prompt still require a controlled
  test on the installed version; no claim that this is exclusive to Pro Tools is made.
  Detection may contribute addition evidence but must never advance Last used.

Private raw evidence is retained under ignored build/date-evidence; no private paths,
track names, or raw logs belong in tracked fixtures. An administrative capability
check was rejected by the repository hook; no installation or elevated observation
ran. The local eslogger manual requires root and Full Disk Access and explicitly
describes it as diagnostic rather than an application API. Shipping feasibility is
unresolved; unprivileged host logs remain available for controlled research.

Next admission: specify a bounded Pro Tools event experiment covering successful
insertion, removal/reinsertion in one process, scanning without insertion, failed
loads, and log clock/rotation behavior. In parallel scope (not concurrent writers),
define Date added evidence with stable identity and preservation across updates,
moves and offline reconnects. Independent specification critique is required before
production implementation. Parent release gates remain open.

### Shared date policy increment
[Asset date evidence](asset-date-evidence.md) now provides a pure, bounded domain
reducer with separate confirmed-use, confirmed-addition, recorded-installation,
discovery and project-reference dates. It does not promote scan/mapping/attempt/failure
evidence or unknown times, and rejects contradictory source-scoped replay records.
Exact byte identities prevent implicit player/instrument and Unicode-normalization
merges. Independent specification and source reviews passed; ten new tests exercise
the policy. No catalog integration, persistence or newly qualified host provider is
claimed. The next work is source admission and durable retention, not further UI polish.

### Durable date evidence increment
[Catalog date storage](asset-date-storage.md) now retains evidence for exact existing
catalog nodes with atomic replay/conflict handling and validated reads. Schema 3
migrates v1/v2 with a verified, lock-bound backup and transactional changes; frozen
fixtures verify preservation. Native tests cover reopen, verified moves, offline scans,
backup, corrupt input and rollback. Replacement nodes deliberately do not inherit dates.
Independent specification/source/state reviews passed. Adapter qualification,
instrument-level storage identity, cross-format lineage and date UI integration remain
open; the ledger itself must not be presented as delivered Last used coverage.

### Installer record source increment
[Package receipt evidence](package-receipt-evidence.md) now provides a bounded
read-only source reader and explicit diagnostic CLI. It checks exact receipt paths,
current bundle versions, typed receipt timestamps, resource limits and stability
across acquisition. Native debug controls corroborated FabFilter/Kontakt AU records
and rejected Diva's incomparable version scheme. No catalog attachment or date UI
change is claimed: receipts may describe skipped installs, updates or historical
content, so they cannot establish original Date added or Last used.


### Installer record catalog binding increment
[Receipt catalog binding](receipt-catalog-binding.md) now attaches live verified
observations to exact existing plugin nodes in one transaction, with strong physical
identity, consistent latest headers and pre/post-write bundle validation. Historical
package/version/path provenance survives reopen and local backup; repeated observations
retain the first ingestion and do not add duplicate events. Independent specification
and source/state reviews passed. Native isolated tests bind/replay FabFilter and Kontakt
AU evidence and reject Diva's version mismatch without modifying installed bundles or
the user's catalog. Generic source dates remain independent: no original-addition or
actual-use date is inferred. Automatic source enumeration, honest UI projection, library
and sample coverage, and successful-use qualification remain open release work.


### Automatic installer collection increment
[Automatic receipt collection](automatic-receipt-collection.md) now runs after successful
plugin inventory persistence, independently of inventory responsiveness. Public receipt
metadata is batched, then exact location/version candidates receive bounded file-list
checks and fresh qualified observation/binding. No vendor-name guessing or private
receipt layout is used. Cancellation propagates across model generations, commands and
queued catalog writes. Errors/resource limits retain unknown coverage and earlier
evidence. Native automatic discovery of the three AU controls succeeded without user
catalog mutation; UI date projection and the broader Last used/Date added gates remain
open. The source does not establish original acquisition or actual use.

### Installer date presentation increment
[Installer date presentation](installer-date-presentation.md) projects exact retained
receipt evidence into plugin sorting, inspector coverage and individual format rows.
Samples and libraries do not inherit player dates. Read errors, ongoing collection and
unverified saved installations remain explicit. Original Date added and Last used
remain unknown until separately qualified; this increment does not close those release
gates. Source/state review passed after repairing open-sheet freshness/status handling.
Native visual and automatic-source checks are recorded in scoped workflow evidence.

### Active continuation: user requires both priority features end to end
Do not stop at bounded increments. Addition bounds now distinguish original unknown
presence (By), arrival/return interval (During/range), and qualified exact dates; receipt
history remains separate. Full 192 tests and eight configured build/state/integration
checks passed before subsequent native-harness scheduling repair. Native UI originally
found library selectionKey lookup defect; fixed with regression. Final UI rerun pending.
Live supported-version VST3 document restore history is now collected, persisted,
projected/sorted/filtered and polled every60seconds while open, with explicit DAW-local
clock and product-class scope. Native core:3 controls,14 events,0 association failures,
1 crashed document rejected, replay stable. Source/model independent review passes.

Next host research is concrete: Cubase15.0.30 Usage Logging reports Plugin Instance Info:
VST - Add/Remove, project_added/activated, and Project Status: Load kErrorNone. Baseline
4 instances across3products, Diva-removed3instances across2products, empty0instances;
normal plug-in rescan creates no instance Add events. Local logging temporarily enabled
for controls then restored disabled (AX verified). Cache descriptor/CID association
research available privately. Failure/missing-plugin control and timestamp qualification
remain before production admission. Then Kontakt program-owned source paths and
Logic/Pro Tools source qualification. All four and individual assets remain required.

### Cubase completed-load increment (active continuation)

Cubase 15 Usage Logger is now parsed behind a strict completion fence: `project_added`,
plugin Add candidates, `project_activated`, and `Project Status: Load` with
`kErrorNone`. Normal rescans, activation without success, failed loads, and incomplete
records produce no positives. The missing-Diva native control is rejected because its
descriptor has the wrong vendor and empty version. `CubasePluginCache` reads the local
VST3 cache with bounded XML parsing, retains duplicate classes, and requires one exact
Audio Module Class tuple. `CubaseUsageCollector` reads existing local logs only and
binds current paths; production collection persists exact class/path history and
projects it as Cubase-local Last used. It never enables Cubase Usage Logging.

The increment has parser, cache, collector, catalog projection, synthetic-control,
real-cache and 200-test coverage; automated build, release, package and runtime gates
pass at the current content fingerprint. A fresh cross-client plan critic was
unavailable due to its usage limit, so the Cubase plan remains marked draft pending
that independent review. Native Cubase end-to-end persistence still needs a controlled
runtime pass before this host is counted as release-complete.

### 2026-10-03 recovery — Codex implementer

User clarification: use means actual instantiation in a DAW, even briefly and
without playback; boot/discovery checks do not count. A generic saved descriptor
and project modification time do not establish that event or its timestamp.
Reversed the previous blanket promotion of project references and name-only library
matching, which had also left the build broken. Sample reference recency remains
labeled separately pending a qualified media-load source.

Repaired three production integration defects: the shared model passed only VST3
assets to every host and projected only their IDs; polling skipped every host when
Ableton's source signature was unchanged; Pro Tools selected `aax` although discovery
stores `aaxplugin`. All plugin formats now reach their respective adapters and the
shared history projection. Each host is polled independently of Ableton changes.
Adapters retain their own filtering. Pro Tools log reads now use bounded regular-file
I/O. Cubase, Pro Tools and Logic event replay preserves first ingestion instead of
rejecting the next polling cycle as conflicting evidence.

Verification: `swift test` passed 205 tests. New integration coverage exercises
Pro Tools log-to-AAX binding, AU/AAX persistence, replay, reopened catalog and model
projection. Cubase replay and a 2,050-sample inventory with all three plugin formats
are covered. These are synthetic integration checks, not native host validation.
The packaged app predates these repairs; no release-complete claim is made.

Next required work: qualify brief manual instantiation as well as completed restore;
finish exact Kontakt instrument identity (private controlled probe locates active
programs but rejects filename table v3); bind individual sample loads to exact media;
validate positive and boot-check negative controls in all four hosts. Existing native
Logic observation can return no names and is not evidence of complete coverage.

### Kontakt filename-table v3 extraction — 2026-10-03

Codex research/implementation. The pinned ni-file author's filename-table reader
supports v2 only:
https://raw.githubusercontent.com/Ma5onic/ni-file/1b7a518243125857fddec8217167b47a35cb58fa/src/kontakt/objects/filename_table.rs
The existing controlled Kontakt 8 states instead contain v3. Read-only inspection
of structurally located 0x4B payloads establishes this observed framing: u16 version,
u32 entry count, then each entry has eight opaque header bytes, u32 segment count,
typed filename segments and twenty opaque trailer bytes. Both positive and empty
tables consume exactly to EOF. Header/trailer meanings remain unqualified and are
not interpreted as dates, file categories or active-program ownership.

Added a bounded, isolated `KontaktFilenameTable` reader; it is not connected to
the usage ledger. Absolute macOS paths require an empty root segment followed by
ordinary components. Relative, parent-directory and library-container references
remain unresolved. Unknown versions/types, truncation, invalid UTF-16, trailing bytes
and excessive lengths reject the table. No raw byte search or filename-only matching.

Explicit native-fixture test passed alongside two synthetic boundary tests:
`env PRISM_KONTAKT_TABLE_RUNTIME=1 swift test --filter 'kontaktFilenameTable|nativeKontaktFilenameTables'`.
The loaded control yields 15 entries including one exact expected NKI path; the
empty control yields one entry and no NKI. Original fixture SHA-256 checks are
unchanged. Extracted tables remain private under ignored build/usage-controls.

Remaining admission: prove the program-owned index into this table with changed,
removed and multiple-instrument controls, then correlate the exact host state with
a successful load event. Merely finding the NKI in this table must not create use.

### Kontakt NIS public metadata extraction — 2026-10-03

Codex implementer completed a bounded `KontaktStateReader` for the observed `hsin`
state envelope. It extracts only structured public `DSIN` library IDs and counts
protected/compressed payloads as opaque. The loaded Accordion control returned the
saved-state candidate `P44` with one opaque payload; the empty Kontakt control returned
no library candidates and one opaque payload. The source library's `SNPID P44`
corroborates the public ID. This does not establish current use, instrument identity,
or a timestamp, and the opaque state was not decoded. Parsing is capped at 16 MiB,
24 levels, 4,096 nodes, and 64 MiB of cumulative parser work; unknown payload encodings
reject. The reader remains isolated from UI and Last used projection.

Verification passed: `env PRISM_KONTAKT_TABLE_RUNTIME=1 swift test --filter
'kontaktPublicMetadata|nativeKontaktAccordion|nativeKontaktEmptyState'` (4 tests) and
`swift test` (212 tests). Native evidence used the private, ignored loaded Accordion
state and empty Ableton Kontakt state fixtures; no original project or library was
changed. Remaining risk: only these observed NIS envelope shapes and metadata version
are covered; this is not universal Kontakt parsing or instrument-level usage evidence.

Coordination preference recorded for continuation: Astra coordinates architecture,
planning, and final review; lower-cost agents handle bounded code/tests; keep a single
writer while read-only planning/review may run concurrently.

### Kontakt SNPID to installed-manifest binding — 2026-10-03

Codex implementer added exact SNPID extraction and an isolated resolver. ProductHints
XML is sliced from the bounded NICNT prefix before strict UTF-8 parsing, because real
NICNT files contain binary bytes around the XML. Exactly one Product and at most one
direct SNPID field are accepted; SNPIDs must be 1–64 ASCII alphanumeric bytes and are
case-sensitive. The resolver only considers current, non-stale Kontakt manifest assets,
returns their existing catalog ID and selection key/path unchanged, and adds no stored
identity. Candidate (256), asset (1,024), and manifest-prefix read (16 MiB total) caps
apply before/through I/O. Any eligible path, parse, read, or stability failure returns
an incomplete result with no bindings; duplicate SNPIDs stay ambiguous. File snapshots
compare device, inode, size and modification time around each read. No UI, persistence,
instrument usage, or date projection is connected.

Verification passed: `env PRISM_KONTAKT_TABLE_RUNTIME=1 swift test --filter
'kontaktManifest|kontaktLibraryBinding|nativeKontaktAccordionSNPID'` (6 tests) and
`env PRISM_KONTAKT_TABLE_RUNTIME=1 swift test --filter 'manifest|Library|library|kontakt'`
(34 tests). The native Accordion state candidate `P44` matched the installed Accordion
NICNT SNPID `P44`; output retained the supplied catalog ID and selection key. Synthetic
controls reject duplicate manifests/fields, case mismatch, malformed or missing files,
stale/proposed assets, and budget overflow. Remaining scope: this identifies a saved
library candidate only; it does not establish a loaded instrument, use event, or time.

### Ableton Live manual VST3 creation candidate — 2026-10-03

Codex implementer added a second, disjoint Live evidence sequence for manual VST3
creation. Only supported Live 12.4.5/12.4.6 records with an exact Going-to-create,
successful processor-loaded name/CID/version, and matching Created record qualify;
the Created record supplies source-local time, source hash and offset. Pending restore,
overlap, mismatch, error/warning, run/document boundary, clock rollback, timeout and
partial tails reset the candidate. A narrow allowlist covers the three observed benign
view/controller chatter messages. Startup Splice processor-load/Created chatter without
Going-to-create remains excluded. Events retain the existing restore source and ID
scheme; manual events carry a distinct per-event source derived from their qualification,
without a required Codable field or history migration. No UI or current-use/date promotion
was added.

Read-only native Live 12.4.5 log validation passed: three completed sequences (Pro-Q 4,
Kontakt 8 and Diva) qualified at each Created line. The 12.4.6 control's startup Splice
sequence did not qualify. Native validation command: `env PRISM_LIVE_USAGE_RUNTIME=1
swift test --filter 'nativeLiveManualCreateRuntime'` (1 test; captured output
`/tmp/live-manual-create-native.log`). Parser/ordering, projection
and the previously failing header test passed in the bounded suite:
`swift test --filter 'live|usageCivilProjection|headerOrderingUnknownsAndPlainSearch'`
(15 tests). CatalogStore mixed restore/manual record, replay, reopen and cross-host
same-day ordering regression passed in isolation (1 test). `swift test` passed all 219
tests; captured output is `/tmp/live-manual-create-full-suite.log`. An earlier full-suite
attempt had CatalogModel waitIdle failures and a header sort assertion, but the header
case and one reported waitIdle case passed in isolation and this final full run passed.
The earlier command output was not retained separately.

Same-day ordering uses full canonical Live local time within Live records. When host
clock domains are incomparable, a documented stable host-family tie-break and evidence
ID make the total order deterministic; no cross-host timestamp chronology is claimed.
Remaining scope: candidate evidence does not establish that a plugin produced audio or
was actually used, and Live 12.4.5/12.4.6 are the only admitted versions.

#### Native 12.4.6 create/remove regression and package — 2026-10-03

Codex test update reads the private captured after-create Live log snapshot and its JSON
summary. The exact record qualified as manual Pro-Q 4 creation at local time
`2026-10-03T13:17:19.036237`, class ID
`ED57BD72-5C60-467E-A64D-D2F400758B6F`, version `4.1.2.0`. The test checks the
snapshot SHA-256 from the summary, asserts the same event is present in the current
Live 12.4.6 log, and parses the startup Splice load/Created subsequence by itself; that
sequence has no Going-to-create and emits no event. The captured Pro-Q event was then
bound through the current Live plugin cache to the installed VST3 and recorded/reopened
in an isolated catalog. No user catalog was opened or mutated.

Runtime operator evidence: Live 12.4.6 created Pro-Q 4 on a disposable Audio track,
then removed that track before saving. AX/screenshots show the temporary track absent;
Live emitted no deletion record. Existing tracks remained present. Both candidate
`Empty.als` files retained their before-run hashes: top-level
`c59ada7db438a4a1550babe911740421630f07a630c57f8df97c972d22b25525`, nested
`8ea0acb4569836570108fcbbcbb915c4ace4b67b16c9d36e4d52a26c2978e1a4`. Log bytes and
source deletion delta are recorded in `build/date-evidence/manual-live/summary.json`.
Under the user's instantiation-based definition, no audio playback was needed. This
qualifies a successful plugin instance creation, not its audible output.

Verification: `env PRISM_LIVE_USAGE_RUNTIME=1 swift test --filter
'nativeLiveManualCreateRuntime'` (1 test), affected Live/projection suite (16 tests),
and `swift test` (220 tests) passed. Captured logs:
`/tmp/live-manual-native-regression.log`, `/tmp/live-manual-native-affected.log`,
and `/tmp/live-manual-final-full-suite.log`. `swift build -c release` passed and
`python3 scripts/build_app.py` packaged and signature-verified the local preview at
`build/Prism.app`; it was not launched. Build/package outputs:
`/tmp/live-manual-release-build.log`, `/tmp/live-manual-app-package.log`.

Parser fence note: a manual create after a successfully loaded document marker is
admitted only in phase 2 with no pending restore and no completed restore candidates.
The create has its own monotonic 30-second clock, independent of how long the document
has been open. Synthetic tests cover empty-document admission, suppression with pending
restore candidates, and recovery by a subsequent completed restore exchange.
