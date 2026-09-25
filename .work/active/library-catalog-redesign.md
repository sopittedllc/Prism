# Simplify: library catalog and collection workflows

Status: implementation started, 2026-09-25. Library ownership foundation delivered
as the first increment; remaining phases are outstanding. The full redesign and major-DAW compatibility remain outstanding. Acting client: Codex. Plan critique:
independent Codex reviewer; alternate client unavailable in this session.

## Product outcome

Simplify answers two questions:
1. What large content have I not been using, and what can I remove to reclaim storage?
2. What did I recently add, and do I already own the instrument/sound I need?

Usage means inclusion in a saved project, whether muted, disabled, or never played.
Observed loading is useful additional evidence, but is not the same as saved inclusion.
Storage means disk space, not runtime RAM consumption.

The current screen fails because it promotes arbitrary folders such as 01_Low_Winds
into libraries. Existing tests proved discovery/search mechanics, not correct product
identity. Stop extending that flat-folder model. No app code changed in this planning pass.

## Information architecture and display contract

Keep Plugins, Libraries, Individual Samples. Add three compact view presets within
these collections: All, Recently added, and Cleanup. They are filters/sorts over the
same catalog, not separate copies of data or new full-screen dashboards.

Libraries use an expandable virtual tree, independent of where files live:

    Orchestral Tools
      Metropolis Ark 2
        Low Strings
          Legato
          Sustains
          Pizzicato
      Metropolis Ark 3
        ...
    8Dio
      CAGE Winds
        Low Winds
        High Winds

Default: makers expanded to show library rows, instruments collapsed. Expanding a
library shows its instruments; articulation/preset children appear only when supported
by vendor data. Where a Kontakt NKI is itself a multi-articulation instrument, retain
that NKI identity rather than inventing articulation files. Series (Ark) is an inherited
tag/filter, not a mandatory extra tree level. Aliases Ark II/Ark 2 resolve to the same
product; Ark III/Ark 3 is a different product. Exact vendor titles stay in details.

Library row columns: Name | Player/format | Installed size | Last used.
Recently added replaces default sort with added-date sorting and reveals Added column.
Library size is the installed footprint of the selected library, including its sample
payloads, patches and installed microphones. It is not the small NKI file size or the
manufacturer's advertised full-download size. Partial installations say so.
Instrument rows show name and format, with size shown as “Shared with library” unless
an adapter can establish exclusive files. Selecting Low Strings keeps a compact
parent-library summary visible, e.g. “Metropolis Ark 2 · installed size …”. Do not copy
the full Ark size onto every patch row. No invented numbers in production UI.

Details prioritize: breadcrumb, description, editable tag chips, usage evidence, then
locations in a disclosure. Move verbose adapter diagnostics to Scan details. Show
understandable “Needs identification” only for unresolved content; never mix guessed
01 Main or Samples folders into the verified library list. A separate review queue
allows Assign maker/library, Merge group, or Split incorrect group, without disk moves.

Global search returns matching libraries, patches and loose samples with a breadcrumb
and result kind. Searching Accordion retains parent context and highlights the matching
instrument/tag; it does not expand hundreds of unrelated folders. A library-only tag
match is labeled as such, not represented as an identified installed accordion patch.
Switching or clearing search restores the previous expansion/selection.

Individual Samples mirrors real selected roots and directories. Show a friendly root
name plus volume in details to distinguish identical names on two drives. Folder rows
expand; audio-file rows have format, size, and tags (duration/BPM/key optional columns).
A flat search-results presentation is available without losing the file's breadcrumb.
Neither hierarchy renames nor reorganizes the user's files.

Plugins retain one product row, Name and Last used by default. Cleanup can reveal
aggregate installed size. Details contain AU/VST2/VST3/AAX/etc instances and existing
selective/all-format removal. One plugin format is not a whole product, and Kontakt
being used never establishes which Kontakt library was used.

## Durable catalog and identity

Introduce a local SQLite catalog before building the replacement tree. Entities:
Maker; Product/Library; LibraryInstallation; Instrument/Preset; PluginProduct;
PluginInstallation; Sample; PhysicalFile; Root/Volume; Membership/Dependency;
TagAssertion; UserOverride; Observation; ProjectReference; ScanCheckpoint.

Vendor IDs identify logical products/instruments. Installation and physical identities
also include volume identity and filesystem identity; paths are mutable locators.
Distinguish library editions, upgrades, separate Kontakt/SINE installs, duplicates,
shared containers and partial downloads. Keep installations separate beneath one
logical product when proven equivalent; never merge by a shortened display name.
Membership permits one physical container to serve several patches/libraries.

Unidentified content has stable local identity and explicit proposed parent; manual
assignments survive rescans. Moves on the same volume preserve identity where proven;
cross-volume moves use reconciliation suggestions and bounded hashes on demand, not
unconditional hashing of terabytes. Ambiguous duplicates remain separate.

Migrate existing configured roots and onboarding settings. Existing in-memory inferred
rows are not trusted product records. Initial persistent inventory establishes baseline;
no invented install history is carried over. Versioned migrations, transactional writes,
backup/export and interrupted-migration recovery must precede adoption.

## Identification adapters

Prefer installed vendor manifests/catalogs, then documented structures, then explicitly
labeled inference. Keep raw names and evidence separate from display aliases.

- SINE: join collection/instrument/articulation/mic identities from local player catalog;
  include only installed files inside configured scope, verify metadata + sample archives,
  group all installed mic positions under one library/instrument, retain partial status.
- Kontakt: NICNT/library registration metadata identifies the product and maker; discover
  NKI/NKM/NKSN under that product without promoting subfolders. For non-Player/legacy
  libraries, walk upward to a validated library boundary using instrument directories,
  manifests and sample containers. Filename/folder fallback proposes a library assignment
  for review; it never claims a vendor-confirmed identity.
- Soundpaint: library → programs/parts; vendor part tags and file mappings; don't count
  the same part payload once per program. Binary manifests need a verified adapter.
- Decent Sampler: DSPRESET mappings identify samples; bundle/archive membership is explicit.
- VSL: Synchron volumes, patches/presets and install registry require validated mappings.
- Spitfire player, EastWest OPUS/PLAY, UVI/Falcon, Spectrasonics STEAM/SAGE: verify vendor
  catalog and container relationships with fixtures before claiming instrument coverage.
  Kontakt-based libraries from these makers use the Kontakt adapter when appropriate.

Adapters share identity, inventory, metadata provenance, dependencies and coverage
contracts. A supported player name alone is never a compatibility claim for all versions.
Initial acceptance requires correct real SINE and Kontakt hierarchy, then Soundpaint;
other players remain visible in an explicit capability matrix, not random folder rows.

## Tags: inference, inheritance and user authority

Use a small controlled vocabulary plus unrestricted custom tags. Facets: maker, product,
series, instrument family, instrument, articulation/technique, character, genre, loop vs
one-shot, BPM and musical key. Player/format remain structured fields, also searchable.
NKS-style brand/type/character and Splice-style instrument/BPM/key are useful patterns;
there is no established universal filename schema to assume all vendors follow.

Low Strings inherits Orchestral Tools, Metropolis Ark 2, Ark and Strings; patch metadata
can add Low register, Ensemble and Legato. A child inherits maker/product/series, not
all sibling instruments: an Ark piano must not inherit Strings from an aggregate library
search index. Parent searchable instrument summaries are separate from inherited tags.

Source order for conflicting values: explicit user override, trusted vendor metadata,
embedded file metadata, contextual filename/folder inference, unaccepted web suggestion.
Tokenize separators/camel-case; normalize plural and known abbreviations using scoped
rules. Folder context must stop at the configured root/library boundary. Do not infer
BPM=120 from any bare 120, key=C from CAGE, or instrument=Bass from Bassoon. Distinguish
bass register, bass instrument and bass drum. Weak/conflicting deductions remain suggestions.

Example: Percussion/Shakers/ACME_Shaker_Loop_120BPM_Am.wav can yield Percussion, Shaker,
Loop, 120 BPM, A minor, with source and confidence; maker requires a verified ACME
mapping rather than an arbitrary filename prefix.

Users can add/remove/rename tags, accept/reject suggestions, edit in bulk and undo.
Deleting an inherited/inferred tag creates a suppression override at that item; a rescan
must not resurrect it. A global rename updates the user's tag vocabulary with preview,
not vendor source data. Context tags can be hidden/overridden without destroying the
underlying maker/product relationship. Offer Restore suggested tags explicitly.

Store edits in Simplify's catalog, never rewrite NKI/audio files by default. Export/import
portable metadata with stable IDs and conflict handling. Search indexes effective tags,
aliases, description, product and instrument names; weights prioritize exact instrument
matches over generic descriptions. Optional web enrichment queries maker/product names,
never private paths/project titles, caches source URL/retrieved date, and presents editable
suggestions. No automatic claiming that a website's full library instrument list is installed.

## Usage and recency: feasibility gate first

Do not build cleanup recommendations around fabricated “never used” values. Store
separate evidence: saved project inclusion, observed successful/attempted load,
browser preview, filesystem access, last project modification proxy and coverage window.
Only qualifying evidence contributes to usage; previews and validation scans do not.

Main Last used may display a date with a visible small evidence label (“Observed” or
“Project updated”), with exact meaning in details. If there is only a project-modification
proxy, never silently present it as exact use time. Unknown sorts into its own group.
Library usage aggregates qualifying child observations, never marks sibling patches used.
A player load cannot roll up to every library. “Not observed since monitoring began”
is the honest alternative to “Never used.” Low frequency means distinct observed
sessions/projects in a defined window, not repeated file opens or scan counts.

Required primary hosts: Logic Pro, Ableton Live, Cubase, Pro Tools. Establish a controlled
fixture matrix before promising support. For each host test AU/VST3/AAX where relevant,
loose audio + sampler-contained audio, Kontakt/SINE instruments, muted/unplayed inclusion,
failed restoration, plugin validation, preview, load then remove before save, collected
sample copies, frozen tracks, alternative versions, moves/offline drives, log rotation.

Investigate host-saved state + retained DAW/player logs first. Existing findings: Ableton
chronological restore events (some fail); Pro Tools host instantiation events; optional
Cubase usage logging; Logic plugin history still unresolved. Verify timestamp anchoring,
version-specific fields, successful versus attempted events and library instrument IDs.
Where logs cannot identify instruments, test player state and future host-aware observation.
Evaluate lightweight observation first; any privileged/system-extension monitor is a
separate privacy/distribution decision and cannot recover historical usage. No plugin
execution, injections or silent logging-setting changes in a scanner.

Deliver a per-host/per-asset matrix with supported evidence and false-positive cases,
not a single “supports Logic” checkbox. If a host cannot provide reliable history, keep
its gap explicit and defer “unused” recommendations for that scope. Do not substitute
REAPER validation for any of the four required hosts.

## Added date and routine changes

Persist firstSeenAt, initialBaseline flag, installedAt evidence where available,
lastSeenAt, content/version changes, observed additions and volume availability.
First scan means “Already present when Simplify started”; it does not mark every library
new today. Future additions enter Recently added, grouped by library. New microphone
content or patch update becomes “Library updated”, not “New library”. Newly selected
roots and reconnected drives are “Newly indexed” unless installation timing is known.
Preserve original first-seen identity across moves/reconnects/rescans. Show evidence in
date tooltip, and allow manual correction without rewriting file dates.

## Storage and removal

Compute logical and allocated-on-disk bytes over unique physical files belonging to
library installations. Deduplicate hard links and memberships; account for sparse/cloud
placeholders, offline volumes, shared archives, APFS clone uncertainty and permissions.
Use “Installed size” with measured/partial/calculating status. Estimated reclaimable space
excludes known shared files and is not identical to a sum of library row sizes.
Moving to Trash is recoverable but does not free disk space until Trash is emptied;
never claim immediate reclaimed bytes or empty Trash automatically.

Cleanup defaults to library/product level: largest first with last activity and coverage.
Filters: over size threshold, no observed use in a chosen interval, unknown history,
recently added, protected/favorite. Unknown is never silently included in unused.
Before removal show exact owned locations, selected formats/library, shared dependencies,
known referencing projects, offline/partial coverage and expected reclaimable estimate.
Do not remove an Ark parent tree when the target is a shared low-string patch. Patch
removal is enabled only when an adapter establishes independent ownership; otherwise
explain shared content and offer whole-library or vendor-managed removal. Preserve
existing reviewed plugin Trash boundary and per-path failures. No privileged helper or
permanent fallback. Record recoverable removal receipt; reconcile external restore.

## Performance and architecture

Persistent catalog is immediately browsable on launch. Background scan has durable
checkpoints and incremental per-root scheduling: discover identity first; index patches
and tags; calculate storage; analyze project/history evidence independently. Rescans
process changed fingerprints; cache successful project parses by identity/mtime/size +
parser version. Dedupe project revisions for usage counts. Support pause/cancel/resume,
per-drive concurrency limits, offline states and stale-value labels. UI refresh bounded
and throttled; do not re-sort all rows for every file. File-change watchers detect changes,
not usage; periodic reconciliation repairs missed events. An incomplete scan cannot delete
catalog entries or rewrite user tags. Partial limits become resumable continuation,
not a permanently truncated “complete” scan.

Targets to validate on named fixtures: cached browse <=2 s; new-root first useful results
<=10 s on local SSD; catalog interaction available throughout and never gated behind a
scanning screen for >60 s; indexed search p95 <=100 ms at 100k instruments/1m samples.
These are acceptance targets, not promises about an offline/stalled external disk. Test
10k projects and large network/external roots with error/timeout isolation. Record time,
peak memory and UI responsiveness; move expensive full hashes off the critical path.

Implementation boundaries: split Scanner into library/sample/plugin inventory adapters,
metadata resolver, storage calculator and usage readers. Replace flat Asset library
identity with catalog nodes/relationships in SimplifyCore; add persistent catalog store
and migrations. CatalogModel queries indexed node snapshots; native NSOutlineView
renders tree/breadcrumb/search, a shared tag editor handles all tabs. Setup configures
roots, primary DAWs/coverage and optional observation; scan progress is secondary.

All persistent state requires registry policies for defaults/migration/persistence,
undo, export/import, automation, accessibility, privacy and analytics (none by default).
Catalog/history remains local; no sync in first release. Persist user content/tag
identity and checkpoints; expansion/filter state is presentation state. Automated refresh
must not change an active removal review or its captured file identities.

## Ordered delivery and exit criteria

1. Identity specification + usage feasibility spike. Produce golden SINE/Kontakt trees
   from installed evidence and the four-host coverage matrix. Freeze truthful date labels.
   No “unused cleanup” release claim before this gate.
2. Persistent graph/catalog + migrations + incremental indexing. Relocate/rescan/reconnect
   fixtures preserve identity, overrides and first seen; crash recovery cannot lose tags.
3. Hierarchical Libraries and Samples UI. CAGE Winds owns Low Winds; Ark is one library
   row; patch selection shows parent footprint; sample folder tree mirrors disk. Native
   keyboard navigation, accessible disclosure rows, selection and search context verified.
4. Editable metadata and search. Accordion/Banjo matches have explainable evidence;
   inherited tags suppress correctly, bulk edit/undo/rescan/export roundtrip pass. Add
   optional web enrichment only after local provenance and user override behavior works.
5. Size/recent-addition workflows. Validate unique physical byte totals and shared-content
   estimates; baseline is not new, adding one patch is a library update, offline is not
   removal. Cache and continue size work without blocking browsing.
6. Validated usage adapters and cleanup. Integrate successful spike results for all four
   required hosts; test read-only historical extraction and opt-in future observation.
   Representative project inclusion controls must pass. Review removals on synthetic
   files only, verify shared-content protection and Trash recovery; incomplete coverage
   remains visible. Full-history support is not assumed for any player.

Deliver each as a coherent tested increment. Do not repeat a cycle of small UI patches
that leave the entity model wrong. No time estimate for proprietary session decoding
until the feasibility spike demonstrates a usable signal.

## Objective end-to-end acceptance

- Orchestral Tools > Metropolis Ark 2 > Low Strings resolves to installed content and
  tags Orchestral Tools / Ark / Strings; Ark 3 stays separate.
- Screenshot regression: CAGE Winds appears once; 01_Low_Winds is a child, not a library.
- Selecting an instrument shows parent library format/installed size, no duplicate totals.
- “Accordion” finds identified installed instruments and audio samples with breadcrumbs;
  broad library descriptions cannot fabricate installed instrument matches.
- Renamed/deleted/custom tags survive rescan, restart, root relocation and metadata refresh;
  rejected suggestions stay rejected; bulk edits have undo and predictable inheritance.
- “Recently added” separates initial baseline, newly indexed roots, new libraries, updates
  and reconnects. A known product retains its added date across a version update.
- Storage accounting passes hard-link/shared-container/partial/offline fixtures; reviewed
  Trash never deletes a sibling library and never claims immediate space recovery.
- Each mandatory DAW has recorded version, supported asset types, positive and negative
  fixtures, evidence timestamp semantics and coverage gaps. No broad release claim from
  unit fixtures or an unsupported format merely appearing in the scan list.
- Cached browsing and incremental performance targets measured; long scans remain usable,
  cancelable and resumable with old results intact.

Verification per implementation increment: swift test; swift build -c release;
python3 scripts/build_app.py; native --ui-smoke captures/catalog; configured CLI,
template, adapter and catalog-state checks; fresh source/UX/accessibility review;
workflow_gate.py check-complete. Add targeted migration/storage/host fixtures as above.
No real user files deleted, no vendor metadata modified, and no raw projects/logs committed.

## Research basis and comparable systems

- Kontakt: product/instrument separation, brand/type/character facets and user tag editing.
  https://docs.native-instruments.com/ni-tech-manuals/kontakt-manual/en/browser-and-presets
- SINE/Ark: collection → instrument → articulation/mic content, and partial instrument installs.
  https://orchestraltools.helpscoutdocs.com/article/372-metropolis-ark-2-notes
  https://www.orchestraltools.com/products/collections/metropolis-ark
- Splice: file/keyword/instrument/genre search plus loop/one-shot/BPM/key filtering.
  https://support.splice.com/en/articles/8652594-finding-sounds
- Plugin Station: storage, installed-format management and installation changes documented;
  last-used tracking for plugins/libraries was NOT verified in public docs/release notes.
  https://www.pluginstation.app/ and https://www.pluginstation.app/faq
  https://github.com/julianworden/PluginStation
- Apple Spotlight last-used is updated for LaunchServices opens, not a documented universal
  signal for a DAW loading plugins or sampler content.
  https://developer.apple.com/documentation/coreservices/kmditemlastuseddate
- Apple allocated size API provides on-disk file allocation, distinct from logical bytes.
  https://developer.apple.com/documentation/foundation/urlresourcekey/totalfileallocatedsizekey
- Host evidence sources and player structures: docs/research/daw-activity-history.md and
  docs/research/library-identification.md. Those documents explicitly separate research
  routes from validated adapters. This plan supersedes their flat inferred-library UI.

Resume: continue with SQLite graph/state and migration design before replacing the
flat table with a native outline. See library-ownership.md for the first increment:
Kontakt proposed product boundaries, SINE logical IDs and all microphone memberships,
scanner/model selection identity propagation, golden fixtures and four-host matrix.
Persistent metadata, editable tags, hierarchy UI, storage accounting, recent additions
and validated usage adapters remain outstanding. No unused-cleanup claim is enabled.
