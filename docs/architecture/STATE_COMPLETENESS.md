# Stateful Feature Completeness

Every user-visible setting or persistent state field is defined once in an authoritative
runtime registry. Presets, settings UI, defaults, reset, project persistence,
automation, accessibility metadata, migration, and tests consume that registry or
prove exact ID coverage against it. No subsystem maintains an independent handwritten
field list.

## The rule

A new state field cannot ship until it declares a decision for every concern in
`.workflow/cross-cutting-policy.json`:

```text
preset                    included | excluded(reason) | not_applicable(reason)
project persistence       included | excluded(reason) | not_applicable(reason)
default/reset             included | excluded(reason) | not_applicable(reason)
migration                 included | excluded(reason) | not_applicable(reason)
undo                      included | excluded(reason) | not_applicable(reason)
automation                included | excluded(reason) | not_applicable(reason)
copy/paste, sync, accessibility, privacy, analytics, export/import ...
```

Silence is forbidden. Automatic inclusion in presets is correct only for state whose
scope is a preset; global, account, device, session, and hardware-specific settings
must be deliberately excluded. The important automation is that omission fails—not
that every setting is blindly serialized.

## Stable registry contract

Each setting has a stable ID, value type, default, introduced schema version, optional
deprecation version, constraints/units in the native registry, and explicit policies.
Renaming a UI label never changes the stable ID. Changing meaning under an existing ID
is forbidden; introduce a new ID and migrate.

Preset encoding iterates registry entries whose preset policy is `included`. Loading:

1. reads schema version;
2. validates types/ranges;
3. migrates known older forms in ordered pure steps;
4. applies defaults for settings introduced later;
5. follows the declared unknown-field policy;
6. applies the result atomically or leaves current state untouched;
7. reports actionable recovery for corrupt/incompatible data.

## Required executable invariants

- Runtime setting IDs exactly equal feature-registry IDs.
- Preset serializer IDs exactly equal registry IDs marked preset-included.
- Default/reset produces the declared default for every included setting.
- Randomized/non-default values survive encode → reset → decode.
- Old fixtures migrate to the current schema and remain audibly/behaviorally equivalent.
- Missing, unknown, corrupt, extreme, and wrong-type values follow documented policy.
- Saving/loading with UI closed works; reopening UI reflects restored state.
- Undo, automation, project save, sync, export, accessibility, and privacy tests cover
  every setting whose corresponding policy is included.

These comparisons use stable IDs, not counts alone. A build fails on a missing,
unexpected, or duplicate ID.

## Change sequence

When adding a feature:

1. Add its definitions to the native authoritative registry.
2. Add matching entries and every cross-cutting decision to
   `docs/architecture/feature-registry.json`.
3. Increment preset schema only when encoded meaning/shape requires it.
4. Add migration and a frozen released-version fixture when required.
5. Run registry coverage, round-trip, migration, and UI/processor integration tests.
6. Update user documentation and preset compatibility notes.

The acting agent must repair a failed completeness gate before declaring the feature complete;
the user should never have to remember which subsystems need updating.

## Plugin removal operation state (2026-09-25)
Product groups, candidate associations and filesystem identities are derived from
the current scan. Checkbox choices, reviewed identities, busy flags and per-item
results belong to a discardable operation, not settings. Preset, project persistence,
migration, automation, sync, analytics and structured export/import: excluded for
this local operation. Defaults/reset: Keep all, discard on close/reset. Undo: Finder
Trash restoration followed by rescan. Copy/paste: selectable path text only.
Accessibility: named native checkboxes/actions and result text. Privacy: local
paths only, no telemetry. Existing roots registry remains the sole persisted
configuration; multiple locations round-trip without a schema change.


Library identity and instrument tags are derived session-only scan data. They reset on
rescan/reset and are excluded from settings persistence, presets, migration, undo,
automation, sync, and telemetry. Explicit probe JSON includes this metadata and local
paths; no network transmission is performed. Search consumes these fields without a
second persisted taxonomy. Editable user tags and web enrichment are not implemented.

Library ownership foundation adds optional derived evidence, vendor IDs and known
content-member paths to scan metadata. Missing fields decode as nil for older reports;
no settings schema or persistence change. Context-tag inheritance excludes aggregate
sibling tags. Product ID is nil where no vendor ID is available; installationRoot
is a proposed locator, never deletion authorization. These follow the existing
session-only metadata policies above; no new mutable user state is introduced.

Session selection uses Asset.selectionKey (vendor product ID where available,
otherwise path). The existing selection registry/default/reset/persistence policy is
unchanged. Finder operations still use the physical path. Scanner/catalog fixtures
prove two products sharing one physical file retain separate selection.

## Persistent inventory catalog (schema 1)

This supersedes the session-only lifetime of derived inventory above. Setup keeps its
existing JSON registry. CatalogPersistenceRegistry is the runtime authority for catalog
logical field groups, mirrored under catalog_fields in feature-registry.json and checked
by catalog_state_check.py:

| Field group | Stored state |
| --- | --- |
| catalog.inventory | Physical-observation UUIDs, physical/vendor keys, scoped asset headers, instruments, content memberships |
| catalog.observations | Global first/last seen, per-scope baseline, generation-derived stale flags |
| catalog.scopes | Exact selected roots, last final evidence snapshot, saved date, complete-baseline state |
| catalog.removal_intents | Explicit plugin paths excluded before reviewed Trash starts |
| catalog.date_evidence | Immutable source-qualified dates and access outcomes |
| catalog.date_subjects | Exact asset and library-scoped instrument evidence subjects |
| catalog.plugin_products | Verified plugin identity and installation lineage |
| catalog.discovery_journal | Disposable work file for resumable local discovery |
| catalog.decoded_facts | Disposable, source-stamped decoded metadata cache |

All are local app data, excluded from audio presets, DAW project persistence, external
automation, structured clipboard, sync and telemetry. Empty database defaults; Reset
clears the session view but retains history. No metadata-edit undo yet; derived data is
refreshed by scans. Backup API exports a consistent local database, without import/merge
UI. Native status, inspector and disabled removal controls expose cached/stale state.

Initialization creates schema 1 atomically only in an empty database; application ID
and user_version reject unrelated/newer schemas without overwrite. Frozen v1 SQL fixture
lives under tests/fixtures. No earlier released SQLite version exists to migrate. Future
version upgrades require a backup plus transactional ordered migrations before adoption.
SQLite rollback restores the preceding snapshot after write failure/interruption.

Physical identity uses volume UUID, inode and birthtime when available. Hardlinked files
or unavailable identity use explicit path fallback; cross-volume equivalence is not
inferred. Logical product key is separate from installation-observation UUID. The current
SINE observation is anchored to its representative metadata file; anchor replacement
without physical continuity can leave a stale observation, pending reconciliation.
Scopes isolate payloads and baseline classifications; snapshots do not leak instrument
memberships from another selection of roots. First seen is indexing history, not install
or usage time. Missing nodes, patches and members remain marked stale, never removal-safe.

Only final scans persist. Background restore has scan/configuration/reset guards. Save
failure retains live results and displays a notice. Cached plugin removal identities are
never restored. Durable removal intent is written before filesystem action; if that write
fails, nothing is moved. A failed removal may remain hidden in saved inventory until a
fresh scan reobserves it; live results still show failed items. User audio is never changed
by the catalog store. Private files default to directory 0700/database 0600.

## Hierarchical navigation (session-only)
CatalogStateRegistry adds outline_state, an object with empty default. CatalogOutlineState
owns per-category browse expansion/collapse and selection, plus one temporary search
context per category. Clearing search restores browse context; switching collections does
not overwrite another collection's navigation. Reset clears every context. Selection IDs
are presentation identities, not file paths or removal authority. On first persistence,
an exact kind/path/product locator reconciles IDs with assigned catalog observation IDs.
Verified catalog IDs survive later same-volume moves; unproven instrument moves do not.

Preset, project persistence, migration, undo, automation, structured clipboard, sync,
analytics and export/import are explicitly excluded as navigation-only state. Local
privacy and native accessibility are included. Existing setup and catalog schemas do
not change. Derived outline nodes/indexes are recomputable caches, invalidated by report
or ordering changes; search projects a filtered tree without filesystem reads.

## Composer discovery (catalog schema 2)

Schema 2 supersedes the exact-scope baseline policy above. Per-category/root baselines
isolate inventory completeness from unrelated project failures and unavailable locations.
Scope membership, instruments and physical members store their own observation timestamp;
reconciliation uses those timestamps instead of an offline scope's later save date. Newly
selected scopes retain matching observations, while removed roots are excluded. Transferred
records stay stale until observed. A SQLite backup precedes transactional v1 migration;
unsupported/corrupt catalogs remain unchanged. Initial/incomplete baseline entries stay
baseline; scan timestamps never become installation/purchase/use dates.

Registry groups catalog.root_baselines and catalog.musical_metadata are local catalog
state. Empty defaults; reset retains durable history. Metadata uses observation ID plus
instrument vendor ID or exact path, never fuzzy names; plugin edits are per installation.
Missing facet override uses suggestions, empty override suppresses them; explicit reset
restores suggestions. Raw scan payloads remain separate. Local persistence, migration,
accessibility, privacy and consistent backup are included. Session Undo applies to user
metadata only; scan-derived baselines are not undoable. Audio presets, DAW project state,
automation, structured clipboard, sync, telemetry and merge-import are excluded. Native
text fields support ordinary text copy/paste. Unresolved instrument moves leave old edits
stored without assigning them to another instrument.

Session recent_only and musical_filter share query's policies and reset to false/empty.
The filter is not saved with setup or a DAW project. Metadata input is bounded to 24 values
per field and 80 characters per value; BPM is one finite positive number at most 999.

Root baseline coverage records nested opposite-category exclusions, so changing a folder
from samples to libraries (or back) establishes indexing rather than inventing acquisitions.

Derived `LibraryInstrument.articulations` and `articulationCoverage` belong to the
existing `catalog.inventory` group and patch identity. Older payloads decode to
unknown coverage, even if they contain a legacy label list; unknown labels are not
presented as verified choices. SQLite and setup schemas do not change. Coverage
records indexed, known-empty or unknown status, adapter/version and, for supported
Kontakt files, a source stamp checked before and after parsing and at catalog commit.
The derived list stores stable source-local IDs, factual titles and source labels from
verified SINE instrument relations, reviewed exact Kontakt individual-patch mappings,
or a versioned Spitfire numbered brush relation. Rest-shell placeholders are excluded.
A cached restore preserves qualified labels, while an unobserved patch and its children
share stale status. New final scans replace the derived list from current qualified
evidence. No articulation owns a separate file,
size, date, usage, tag override or removal target. Finder and patch metadata edits
resolve through the owning instrument. This is local inventory in the existing backup
and privacy policy, excluded from presets, DAW projects, automation, sync, telemetry
and structured clipboard. Existing patch-tag Undo remains the only metadata Undo;
navigation selection/expansion is session-only and inherits `outline_state` policy.

Usage filter (`usage_filter`, default `all`) is session-only browser navigation.
It shares query policies: resettable, accessible, local; excluded from persistence,
presets, undo, automation, sync, analytics and export. Category changes and Clear
filters reset it. Only all/unknown are supported until verified host evidence exists;
no new durable usage or installation-date schema is introduced by this UI slice.

Product tags use the bundled local catalog, user edits, and compatible historical caches.
The retired `online_tags` setup key is ignored when older settings are read and is
omitted on the next save. No product lookup or tag network request runs in the app.
`catalog.product_tags` and the former shared catalog sidecar remain decodable so
previously fetched suggestions can still work offline. Invalid cache data is rejected
without replacing the last good file. Manual overrides, including intentionally empty
fields, take precedence over all derived facts. Product facts do not propagate to
individual patches without qualified articulation metadata.

`sort_reversed` is session navigation with default false; each column has a useful initial
direction. Reset clears it, header indicators expose it accessibly, and no persisted
schema changes. Its full policy mirrors sort in the feature registry. Tag popover visibility is transient presentation; there is no tag-network preference.

Tag-pill add drafts and popover visibility are disposable presentation state, reset on
close; they do not participate in persistence, migration, presets, automation, sync,
clipboard, export or telemetry. Category is named accessibly, local values use existing
metadata privacy/persistence policies. Product tag actions save existing per-subject
overrides in one transaction; batch Undo remains session-only and publishes only after
durable success. No schema or registry ID changes. Setup recovery visibility is derived
from a failed save, and stored standard-folder preferences keep their existing policy.

## Appearance preference
`appearance` is a local application preference: light (default/reset), dark, system.
Registry-selected setup-v1 persistence includes it; the policy's historical
project_persistence name denotes that local settings store, not a DAW project.
Missing older fields default Light; invalid enum/type rejects and preserves the file.
Settings previews globally, Cancel restores accepted mode, Save persists atomically
with folders without scanning. Failure retains draft and offers session-only use.
Appearance-only changes do not invalidate inventory. No presets, DAW automation,
structured clipboard, sync, analytics or export/import. Native popup exposes its name
and selected value; privacy is local-only. No document Undo; Cancel supplies rollback.
AppKit nil appearance follows system changes; explicit aqua/darkAqua override.

## Section scans
Execution masks and outstanding changed categories are transient, not additional user
settings: excluded from presets/persistence/undo/automation/clipboard/sync/analytics/
export. Scan captures section at click; projects belong to Samples execution. Full root
scope remains the catalog key and ownership authority. Unscanned fresh generations and
stale states carry forward without advancing observations, including compatible section
transfer across unrelated root changes. Optional ScanIssue.kind is backward compatible;
legacy unowned issues remain until full scan. No SQLite schema change. Current-session
plugin file identities survive unrelated scans; disk restore still strips them.
Production automatically enables standard plugin roots even if old settings stored false;
explicit synthetic profiles retain isolation. Existing standard_plugins ID remains for
compatibility/test profiles but has no user control. Online-tag preference remains opt-in
in Settings, applied atomically on Save; Cancel preserves it. Per-item editor stays in
context menu; pills remain the normal editing route.

## Qualified date evidence (catalog schema 3)

`catalog.date_evidence` is local immutable source history keyed by source/event IDs
and exact registered asset or instrument subject IDs. Schema 6 adds `catalog.date_subjects`; asset IDs remain node IDs, while instrument IDs are deterministic and scoped to their owning library plus exact vendor ID or path. It is empty by default and on v1/v2 migration;
first discovery is never promoted into installation or use. Session reset and offline
scans retain the ledger. Native SQLite tests cover migration with pre-change backup,
reopen, verified moves, replacement isolation, local backup, corruption and atomic
rollback. Future/foreign schemas are preserved.

The authoritative registry and feature-registry declare every concern. Presets, DAW
project state, undo, external automation, clipboard, sync and telemetry are excluded.
Privacy and local backup are included; import/merge and UI presentation are absent.
Instrument identity, cross-format product lineage and host qualification remain
separate work. The storage API cannot itself establish successful usage.

Receipt binding adds optional typed provenance to the same `catalog.date_evidence`
group without SQL schema changes. Legacy payloads decode with nil provenance. The
reserved `macos.pkgutil.receipt.v1` source requires a dated installation record with
package ID/version, bundle path/identifier and ordered declared versions. These local
paths and identifiers remain private and participate in existing SQLite backups.
Evidence equality is byte exact; repeat source observations preserve first ingestion.
Only opaque live reader observations can enter the source-specific binder. It checks
current strong physical identity, latest agreeing catalog headers, removal intent,
and bundle stamps before and after the transaction write. It does not renew inventory
freshness, populate original Date added/Last used, or propagate an AU record to other
formats. Generic evidence append remains an internal trust boundary for qualified
adapters; typed provenance alone is not proof of acquisition. UI projection is pending.

Automatic receipt collection runs after successful fresh plugin inventory persistence,
on cancellable utility work separate from inventory. It populates the same evidence
ledger; `receiptCollection` is a transient operational summary in that feature group,
not a persisted setting. Reset, new scans, accepted location changes and reviewed
removal cancel work; generation checks prevent late summary publication. Actor-entry
and pre-commit cancellation checks protect queued attachment writes. Reset clears the
summary but retains committed history. Neither restore nor sample/library-only scans
initiate receipt queries. The summary records bounded-pass coverage, never original
installation history; no new date label/control is exposed. Backups include evidence
only, not operational summaries. Existing preset/project/undo/automation/clipboard/
sync/analytics exclusions and local privacy policy apply unchanged.

Installer date presentation derives an exact-node byte-keyed cache from typed receipt
history. Loading/error state, read generation and grouped coverage are transient parts
of catalog.date_evidence; no new persisted fields/preferences/schema. The single read
transaction fails closed on corrupt/missing/over-budget history. Collection failure
retains valid historical records; projection read failure clears untrusted display state.
Reset clears cache and cancels late publication while retaining history. Samples,
libraries and individual instruments do not inherit plugin receipt dates. Accessibility
now includes visible source/date/coverage/status and sortable native headers. Other
preset/project/undo/automation/clipboard/sync/analytics exclusions and private backup
participation remain unchanged. There is no editable date or original-addition inference.

### Addition bounds (schema4)
Existing catalog.date_evidence owns node_addition_bounds and scan_coverage. Coverage
retains kind/root/exclusions, policy, physicalrootidentity and start/finish. Only final
compatible complete scans establish an arrival/return interval. Prior absence remains
valid through no-scan settings roundtrips; loaded/scanned omitted scopes conservatively
clear it. Legacy first_seen yields presentBy, not exact acquisition. Session reset
retains history, backup/migration include it, no presets/undo/sync/automation/network.
Derived grouped bounds weaken for unknown siblings; instrument dates stay independent.

### Live class-use projection
Optional hostUsage provenance belongs to catalog.date_evidence, not a new preference.
Records contain strict source-local Gregorian components, source/run/record identity,
VST3 classID and plugin/host versions. eventDate remains nil: no offset is invented.
The node association is verified current class membership; historical physical-byte
continuity is explicitly not claimed. Source event equality excludes mutable cache
snapshots and growing-file hashes. Replay preserves first ingestion; moves preserve
node history; newly verified replacements may associate the same class history.
Read corruption returns unavailable with no partial projection. Collector source
failures retain prior valid history and show incomplete coverage. Reset/scope/removal
cancel collection; read/scan generations reject stale publication and stale task starts.
Polling is 60 seconds only while the app runs, bounded and changed-source gated. No host
is launched or automated by production collection. No presets, undo, DAW automation,
clipboard, telemetry, sync or external export changes; consistent backups include it.

### Library discovery journal

`catalog.discovery_journal` is a separate, disposable SQLite work file under the
private catalog directory. The native registry and feature registry declare every
cross-cutting policy. It stores completed directory records, derived patch identities,
and the remaining frontier in bounded transactions. A cancelled scan keeps committed
work; no partial directory becomes catalog coverage. An exact scope, scan policy,
root identity, SINE catalog identity, and every completed directory/candidate stamp
must still agree before replay. A mismatch discards the journal and restarts discovery.
Transient source errors disable further checkpoints for that pass while discovery
continues; they cannot establish a complete baseline. Session Reset deletes journals;
completed catalog history remains. The journal is local only, excluded from presets,
projects, undo, automation, clipboard, sync, telemetry and backup/export.

`catalog.decoded_facts` is a separate private
SQLite file beside the journal. It holds bounded decoded metadata only, with policy
and dependency stamps including observed absent sidecars. The scan rechecks current
physical content, ownership and source stamps; cached facts cannot establish removal
or availability. Cancellation, unstable reads and cache damage fail to a fresh read
or incomplete coverage. Reset deletes the file and policy changes invalidate entries.

### Four-step onboarding and complete coverage

First-run navigation now has Sample Libraries, optional Individual Sounds, optional
Projects, and Review & Scan. The step, draft and focus are session-only; final Review
still accepts the existing `roots`, `standard_plugins` and `onboarding_completed` IDs.
Standard plugin discovery is automatic in production. Previously saved custom plugin
roots remain visible and removable, but there is no new add control. Setup saves reject
payloads above the existing 1 MiB read bound, leaving the prior file unchanged. Scanning
reads local content only; it does not edit, upload or share user files.

Normal file discovery ignores diagnostic entry/depth limits for sample, project and
plugin roots, including retained legacy plugin roots. `completeFileScan` and the
existing project/library diagnostic modes are transient request policy, excluded from
presets, DAW projects, persistence, undo, automation, clipboard, sync, analytics and
export. Reachable supported files are measured by metadata; failed measurement has a
source issue. A measured candidate or shared-content basis never claims a complete
product footprint, and unavailable/unsupported roots never authorize removal.

New full-scan `catalog.scopes` evidence may set optional `sampleInclusionsDerived` and
omit inclusion rows only after exact equality with rows derived from the incoming
sample assets and bound project references. Restore reconstructs those rows from fresh
current-generation sample members only; retained stale members acquire no new reference
conclusion. Older evidence without the marker keeps its explicit rows, including
unusual externally supplied rows. The marker changes no SQLite schema or registry ID;
the 32 MiB per-cell and 128 MiB query bounds remain. Cancellation and source checks
still guard the transaction. Backups include this local catalog representation; there
is no preset, DAW, automation, clipboard, sync, analytics or network export.

Unassociated SINE `.otmeta`/`.otarc` pairs are durable physical inventory in
`catalog.inventory`, with literal paths, complete pair logical bytes and unresolved
product identity. Their local stat fingerprint is checked at catalog commit and a
changed pair starts a new physical observation without inheriting product history.
They contain no invented instrument or articulation. Missing or
linked mates and a missing local SINE database leave catalog coverage incomplete.
An exact, unique later catalog pair binding replaces the unassociated scope row;
physical observation alone never assigns a vendor product ID or transfers unrelated
product history.

### Exact item usage subjects (schema 6)

The v5-to-v6 migration takes a verified pre-migration backup and transactionally creates
`date_subjects`. Existing asset subject IDs and `date_evidence` source IDs, event IDs,
subject IDs and payload text are copied unchanged. Existing instruments are seeded from
the saved catalog payloads; IDs combine the owning library node with the exact vendor ID
or exact instrument path, so equal vendor IDs in separate libraries remain isolated.
New library instruments are registered in the same transaction as catalog ingest.

Typed item access can represent opened, loaded, attempted and failed attempts with a
separately qualified event time and ingestion time. Only explicitly recognized music-app
bundle IDs are eligible; old untyped attempt records remain readable but do not count as
Last Used. The app has no real general sample/patch observer yet: the ledger and UI path
are testable, but source acquisition stays gated on controlled native host records and
negative Quick Look, Preview and Splice sample-preview controls. No synthetic collector
is installed. Last Used for a library can roll up a qualifying exact instrument event;
that event never appears on siblings.
