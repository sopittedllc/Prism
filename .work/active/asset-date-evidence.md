# Plan: qualify Last used and Date added evidence

**Status:** IMPLEMENTED — source review passed; configured verification recorded separately
**Owner:** Codex coordinator/implementer
**Last updated:** 2026-09-26
**Task ID:** cleanup-essentials (bounded domain increment; parent remains open)
**Risk tier:** 1
**Domains:** domain logic

## User outcome
Give both priority dates one tested evidence policy before connecting host and
installation sources. Unknown history must not become a fabricated timestamp.

## Non-goals
No new UI, persistence, background watcher, host parser, installer, or claim of
four-host support. This increment cannot make currently unknown catalog dates known.

## Current-state evidence
See usage-evidence-delivery.md priority correction. Pro Tools mappings persist after
removal, instantiation logs lack verified success semantics, and package timestamps
can reflect updates. Existing CatalogObservation.firstSeen is discovery, not install.
Current Pro Tools logs also contain FreePlugIn and local wall-clock anchors; one
~10-second scalar backstep means file order cannot define most recent evidence.
Official clock reference: https://learn-cdn.avid.com/AAX_SDK_2p1p1/Documentation/Doxygen/output/html/a00277.html
Native 24.10.2 uses declared seconds, whereas the older reference uses microseconds.
Clock conversion and successful-load admission remain separate future adapter work.

## Interfaces and files affected
- New Sources/SimplifyCore/AssetDateEvidence.swift: immutable Sendable domain values
  and pure bounded reducer, no filesystem, clock reads, global state or host calls.
- New tests/SimplifyCoreTests/AssetDateEvidenceTests.swift: synthetic regressions.
- This plan and active task metadata; parent evidence and resume notes.

## Contract and risks
Each record carries a nonempty source-scoped evidence ID, source identifier, exact
opaque subject ID, kind, optional event date, and ingestion date. Callers must supply
validated subject identity: display-name/path similarity must not merge subjects.
Subjects may be products, installations, samples, or instruments; no implicit player,
parent-library, format or sibling propagation. Source adapters own classification
and identity qualification; this reducer does not turn a claim into verified truth.

Kinds: confirmedUse, confirmedAddition, installationRecord, discovery,
projectReference, loadAttempt, failedLoad, scan, mappedInHost.
Only confirmedUse contributes Last used (maximum event date). Only
confirmedAddition contributes Date added (minimum event date). Other kinds never
promote either; installationRecord, discovery and projectReference have separately
named summary dates: latest recorded installation = maximum installationRecord
event date, first discovery = minimum discovery event date, latest project reference
proxy = maximum projectReference event date. All use event date only. Unknown event
dates stay unknown even when ingestion is known.
The pure reducer accepts the complete evidence set and an explicit finite asOf date;
it does not persist or claim history survived unless the caller retained it.

Validation is all-or-nothing: cap 10,000 records; IDs/source/subject at most 1,024 UTF-8
bytes and nonblank, reject control characters; finite dates, ingestion <= asOf,
event <= ingestion. Equal duplicate source+evidence IDs are idempotent; conflicting
duplicates throw (including differing subject/kind/event or ingestion date). Exact
opaque identifiers compare UTF-8 bytes, including the validated requested subject;
Unicode canonical equivalence must not merge different opaque identifiers.
A later correction requires
upstream reconciliation, not silently replacing a record here. Validation applies to
the whole batch before filtering by requested subject. Ignore array order; explicit
dates govern extrema. No tolerance silently admits future dates. Adapters must bound
clock uncertainty before assigning an event date.

## Implementation
1. Independent specification critique; resolve findings.
2. Implement values, explicit errors, bounded validation/dedup and date summary.
3. Test negative signals, exact identity, out-of-order/replay behavior, updates and
   rescans, invalid clocks, unknown times, conflicting IDs and resource limits.
4. Fresh independent review and configured verification. Record remaining adapter
   admission requirements without claiming this domain increment delivers the feature.

## Acceptance criteria
- Only correctly classified confirmed records contribute the two primary dates.
- Updates/rescans/reconnect observations cannot replace an existing confirmed
  addition; replay and input order do not change summaries.
- A player/other subject cannot establish usage of a patch or sibling product.
- Unknown event time never falls back to ingestion; invalid/contradictory input fails
  explicitly; source namespaces prevent unrelated event IDs colliding.
- All limits and failures above have deterministic synthetic coverage.

## Verification and runtime
Exact configured runner:
`python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package`
Core tests execute on the native target; this pure domain function has no host or UI
runtime behavior. Host controls are research evidence only and do not qualify an
adapter. Parent `python3 scripts/workflow_gate.py check-complete` must remain truthful.

## Compatibility, feature coverage and rollback
No existing serialized schema changes; values intentionally are not Codable in this
increment. No persistent state IDs. Presets, project state, reset, migration, undo,
automation, copy/paste, sync, accessibility, analytics and export/import are not
applicable to an unconnected pure function. Privacy: only synthetic fixture content
is tracked; no telemetry, raw host log, path or project name added. Single value owner,
Sendable immutable values, synchronous bounded work outside audio callbacks. Remove
the new files to revert; existing callers are unaffected.

## Gate dependencies and resume
Source changes require tests/build and fresh review; final documentation changes
require evidence on the final content fingerprint. Alternate-client authentication
was unavailable in the previous actual attempt; independent Codex critique/review is
the available fallback, with distinct reviewer roles. No product decision pending.
Independent Codex specification critic group_source_review passed after explicit
secondary-date extrema, ingestion equality and byte-exact identities were added.
Independent fresh Codex source reviewer container_review passed without blockers.
Ten new deterministic tests cover this contract; the native suite passed 134 tests.
Final configured-check outcomes live in the parent's automated_tests.json evidence.
No existing catalog caller was changed; parent date providers remain open.

Research checkpoint: reopening the isolated three-plugin control after the removal
control produced new host-instantiation events while the same process retained its
binary mappings. A Save dialog delayed the transition, so the private capture records
an observation window rather than claiming exact action time. All 14 original test
input hashes remained unchanged. The host is left on the isolated baseline control.
Current log has no verified successful-instantiation completion line; its observed
cannot-instantiate error is in startup cache validation, not a failed session restore.
Neither this positive control nor the reducer qualifies a production Last used source.

Next: qualify source admission with a failed/unavailable restore control that does
not alter real installed plugins; verify log clock anchors across sleep and rotation.
For Date added, define persistent evidence retention and stable identity migration
before connecting receipt/discovery adapters. Source and subject IDs in this domain
must come from those validated adapters, never ad hoc product-name matching.
