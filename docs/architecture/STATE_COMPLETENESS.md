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
