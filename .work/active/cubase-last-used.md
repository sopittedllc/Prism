# Plan: Cubase completed-project plugin usage

**Status:** DRAFT — awaiting independent specification critique
**Owner:** Codex root (sole writer)
**Last updated:** 2026-09-27
**Task ID:** cleanup-essentials
**Risk tier:** 2
**Domains:** host-integration, persistence, privacy, performance
**Base revision/worktree fingerprint:** content:39d0d2a01b58031052c9f748999d536d12de04625b5211a9032b2dcd866d992c

## User outcome

Prism reports Last used for Cubase VST3 plugin products when Cubase's local Usage
Logging proves that a project loaded successfully with an exact installed plugin
class. A normal plug-in rescan, failed load, missing-plugin placeholder, or mere
project activation never counts as use.

## Non-goals

- Enabling Cubase Usage Logging or changing Cubase preferences automatically.
- Inferring use from file modification time, project modification time, name-only
  matches, installed-cache presence, or an Add attempt without successful load.
- Claiming physical-installation lineage after a plugin replacement.
- Covering Kontakt programs, samples, libraries, Logic, Pro Tools, or unsaved
  insertion in this increment.

## Current-state evidence

Native controls on Cubase 15.0.30.287 recorded four Adds across FabFilter Q 4
(twice), Kontakt 8 and Diva, followed by project activation and `Project Status:
Load`/`kErrorNone`. Removing Diva removed its Add. An empty project had zero Adds.
A normal Plug-in Manager rescan generated no Add records. A fixed-width missing-Diva
control generated a placeholder Add with vendor/version mismatch; it must be rejected.
Official Steinberg documentation says logging is disabled by default, local, and
contains project plugin information: https://helpcenter.steinberg.de/hc/en-us/articles/32371744743826-Usage-Logging

The cache research in `build/date-evidence/` found VST3 class descriptors with
duplicate CIDs and duplicate descriptors. Exact `(Name, Vendor, Version, Type)`
matching plus a unique current cache class, current bundle identity, and current
catalog node is required; path or name alone is insufficient.

## Interfaces and files affected

- `Sources/SimplifyCore/HostUsageEvidence.swift`: provider-neutral usage payload and
  Cubase parser/provenance, preserving Cubase's qualified source clock.
- `Sources/SimplifyCore/LiveUsageCollector.swift` or a new
  `CubaseUsageCollector.swift`: bounded local JSONL/log and cache reader, exact
  descriptor binding, source polling signature.
- `Sources/SimplifyCore/CatalogStore.swift` and `AssetDateEvidence.swift`: accept
  the additive typed provenance without coercing clocks or weakening identity checks.
- `Sources/SimplifyCatalog/CatalogModel.swift`, `CatalogOutline.swift`, and
  `UsageDatePresentation.swift`: merge provider records, sort by reported source
  day with host qualifier, preserve unknown and partial coverage.
- `tests/SimplifyCoreTests/`, `tests/SimplifyCatalogTests/`: parser fences,
  placeholder/duplicate identity, bounds, replay, cancellation and projection.
- `docs/architecture/STATE_COMPLETENESS.md`, feature registry, research and active
  delivery plan: document state/privacy/export and coverage.

## Risks and failure modes

Malformed or unsupported logs fail closed; incomplete project windows are discarded;
overlapping instance runs and Add/Remove ordering cannot create positives. JSON
duplicate keys, external entities, oversized fields/files, cache changes during
association, duplicate CIDs, stale nodes, and missing logs produce unknown coverage.
The collector is read-only, bounded, cancellable, and never launches Cubase. Source
timestamps must be qualified against measured native output before absolute dates are
stored; until then preserve a source-local/host-clock domain.

## Product decisions

None. “Last used” means successful completed project load in this increment.

## Implementation

1. [ ] Qualify Cubase timestamp semantics from private controlled logs and record a
   conservative clock contract.
2. [ ] Add an immutable Cubase provenance type and strict bounded parser requiring
   `project_added` → exact plugin Add → `project_activated` → successful
   `Project Status: Load` (`kErrorNone`); reject placeholder descriptor mismatch.
3. [ ] Add read-only cache binding and current physical/catalog identity validation.
4. [ ] Integrate collection, polling, persistence, sorting, filtering and AX copy.
5. [ ] Add synthetic fixtures for success, rescan, activation-only, failed load,
   missing placeholder, duplicate CID, replacement, replay and large catalogs.
6. [ ] Run unit/integration/state/package gates, then native Cubase controls with
   logging restored disabled and original sessions untouched.

## Acceptance criteria

- [ ] Baseline Cubase control records exactly the three products present after a
  successful project load, with repeated Q4 instances retained as source events.
- [ ] Rescan, empty project, activation-only, failed load, removed plugin, and
  missing-placeholder controls produce no false positive.
- [ ] Exact current class/cache/bundle/catalog binding is required and duplicate or
  stale identity fails closed.
- [ ] Replaying unchanged logs is idempotent; append/rotation does not change old
  event IDs; cancellation and source failure preserve prior evidence.
- [ ] UI says Cubase project history and host-local date, never installation date or
  physical-byte lineage; samples/libraries remain unknown.

## Verification

```text
swift test
swift build
swift build -c release
python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests catalog-state template-integrity adapter-integrity app-package
```

Native evidence must include baseline, removed, empty, rescan, failed-load and
missing-placeholder JSONL snapshots plus restored preference state. No user project
or installed plugin is mutated.

## Runtime/manual checks

- [ ] Cubase 15 baseline loads and completes; Prism records Q4, Kontakt and Diva.
- [ ] Cubase Plug-in Manager rescan produces no new use records.
- [ ] Missing-class control is rejected despite `kErrorNone`.
- [ ] Usage Logging is disabled before and after controls.

## Out-of-scope findings

Instrument-level Kontakt ownership, Logic and Pro Tools source qualification, and
standalone/plugin insertion observation remain required follow-on work.

## Compatibility and migration

Additive Codable evidence remains backward compatible; unsupported Cubase source
versions are unavailable coverage. No schema bump is permitted until the existing
typed payload boundary is proven insufficient.

## Cross-cutting feature coverage

This is persisted usage evidence, not user-editable state: reset clears live
projection but retains ledger; migration is additive; undo, preset, automation,
copy/paste and sync are excluded by policy; accessibility and export must include
host, scope, source-clock qualifier and unknown status; privacy excludes logs and
project contents from telemetry.

## Rollback/recovery

On parser/cache failure retain earlier records and mark current coverage unavailable.
Remove the adapter and its source IDs without deleting unrelated evidence.

## Gate dependencies

Parser/store edits require all Swift tests and build/package checks. Model/UI edits
require catalog runtime and accessibility/visual checks. Native adapter edits require
the Cubase controls and preference restoration evidence.

## Resume notes

Cubase research and controls are complete; specification critique is next. Then
qualify timestamp semantics before implementing the parser.
