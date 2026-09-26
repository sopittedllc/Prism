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
existing JSON registry. CatalogPersistenceRegistry is the runtime authority for four
logical field groups, mirrored under catalog_fields in feature-registry.json and checked
by catalog_state_check.py:

| Field group | Stored state |
| --- | --- |
| catalog.inventory | Physical-observation UUIDs, physical/vendor keys, scoped asset headers, instruments, content memberships |
| catalog.observations | Global first/last seen, per-scope baseline, generation-derived stale flags |
| catalog.scopes | Exact selected roots, last final evidence snapshot, saved date, complete-baseline state |
| catalog.removal_intents | Explicit plugin paths excluded before reviewed Trash starts |

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
