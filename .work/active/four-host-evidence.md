# Four-host usage evidence: research, admission, implementation

Status: FIRST DESCRIPTOR INCREMENT APPROVED by independent Codex evidence_critic; macro usage remains research. Driver and sole writer: Codex.
Risk: 2 (compatibility, privacy, persistent evidence). Parent: cleanup-essentials.

## User outcome
Reliable usage of plugins, individual samples and exact library instruments in Logic,
Live, Cubase and Pro Tools. The user supplied one positive saved session per host with
Pro-Q 4, Kontakt 8, Diva, a WAV and an expected wineglass NKI. Research across the
whole workflow precedes parser implementation. All-four support remains mandatory.

## Current evidence
The existing executable extracts sample candidates from ALS and Logic metadata;
PTX/CPR return unsupported. Live 12.4.5 fixture has Vst3PluginInfo/Name and nested
Vst3Preset/Uid, missed by the old VST2-only name reader. Binary strings in other
hosts are exploratory evidence only. Exact Kontakt patch attribution is unproved.
Private fixture paths, raw audio, state blobs and session names stay outside Git.

## Architecture and admission
1. Host acquisition: bounded, read-only snapshots with host/schema/version, digest,
   source locator and coverage. Saved projects, official exports and runtime logs are
   separate routes. No hidden host automation or changes to logging preferences.
2. Evidence extraction: distinguish saved descriptor, exact saved reference,
   successful observed load, failed attempt, validation and unresolved candidate.
   Never upgrade raw string matches to current-track membership. Opaque plugin
   state is a separate player adapter, never decoded by guessing filenames.
3. Identity resolution: format-specific IDs mapped to installed catalog nodes with
   collision/ambiguity outcomes; paths and aliases do not establish equivalence of
   copied audio. Player identity never propagates to every installed library.
4. Persistence: source revisions and historical events have different lifetimes.
   Rescan/restart must not create new usage; project removal clears current
   membership but cannot erase proven historical events. Failed parsing preserves
   prior evidence as stale. No persistent event ledger before timestamp and identity
   contracts pass review. Existing report evidence may retain candidate descriptors.
5. Projection: Last used only from admitted timestamped evidence. Project updated
   is a proxy and stays separate. Unknown coverage never means unused. No deletion
   recommendation based on missing evidence.

## Ordered implementation
- Inventory and fingerprint the four fixtures read-only; run current readers.
- Research official host and player APIs, supported exports, parser authors and
  license restrictions. Compare saved-project, host-export and prospective tracking
  routes. Document what each can and cannot establish.
- Obtain independent specification critique before code changes.
- Repair demonstrable descriptor omissions only within observed structural paths,
  keeping candidate status and existing Unknown usage. Add adversarial fixtures for
  decoys, stale/history state, wrong nesting, malformed/version/size/depth inputs.
- Run actual supplied sessions through the resulting readers, record aggregate
  results and unchanged fingerprints. Do not ship proprietary fixture data.
- Establish exact next controlled host experiments (remove/save, missing plugin,
  copied WAV, same-name NKI, logging clocks) before admitting usage adapters.

## First implementation admission contract
Only add Live 12 VST3 descriptor candidates in this increment. Require the observed
Ableton/LiveSet/Tracks/{AudioTrack,MidiTrack,ReturnTrack}/DeviceChain/DeviceChain/Devices/
PluginDevice/PluginDesc/Vst3PluginInfo/Name path. Require MajorVersion=5 and a
MinorVersion=12.0_12402 and Creator beginning Ableton Live 12.; other schema versions keep existing sample
behavior but yield no new VST3 candidates. No UID-to-installation mapping, arbitrary
XML Name extraction, opaque state parsing or changed last-used projection. The
UID contract and nested rack/master routing need separate positive/negative proof.
Candidates persist through existing ProjectReference Codable storage unchanged.
Tests must cover wrong ancestor, nested preset/browser/history decoys, wrong version,
duplicate descriptors (instances remain separate), missing/empty names, DTD/depth
and existing gzip failures. This is descriptor coverage, not adapter admission for
actual last-used.

## Interfaces / scope
ProjectReader.swift, Models.swift only if additive evidence metadata justified;
DiscoveryTests.swift, CatalogStoreTests.swift, research documents, local audit
harness if needed. No UI redesign, background agent, proprietary SDK installation,
plugin execution by Prism, or release. Existing application work preserved.

## Acceptance
- All four hosts and player attribution have sourced route/coverage decisions.
- Positive fixture checks are reproducible and negative controls are enumerated.
- Any shipped extraction has structural bounds and candidate semantics; false
  names in unrelated XML or opaque state do not create plugin references.
- Existing catalog persistence preserves new candidate references across reopen.
- No exact last-used or four-host-complete claim without admitted identity/events.
- User sessions unchanged; synthetic fixtures only in source control.

## State completeness / compatibility
Existing catalog.inventory/project evidence carries extraction results. No presets,
undo, automation, sync or analytics participation: observations are read-only local
inventory. Default absent evidence unknown; old reports remain readable. CLI JSON
is explicit export with local paths; raw private audit artifacts in ignored build/.
No new user setting or UI control. A future ledger requires its own registry,
migration and complete state matrix before implementation.

## Verification
Configured build-debug, unit-tests, integration-tests, catalog-state,
template-integrity, adapter-integrity, build-release, app-package and catalog-runtime
via scripts/run_check.py; source review separate from implementation. Local fixture
probe uses built simplify-probe --inspect-project for each supplied file; compare
SHA-256 before/after. No binary mutation or DAW save to originals.
Native hooks unavailable; deterministic commands provide enforcement. Claude Code
reported loggedIn but its actual read-only review failed because OAuth expired and
could not refresh. Independent Codex evidence_critic reviewed the first increment.
No private sessions transmitted for review. Research and route decisions:
[Four-host checkpoint](../../docs/research/four-host-evidence-2026-09-26.md).

## Risks / recovery
Undocumented formats change; reject unsupported structures. Negative examples are
needed to exclude undo/history/unused pools. Stable IDs are not necessarily install
paths. Project mtime may be changed by copying. Read budgets cannot be relaxed just
to accept one large CPR. Roll back only new source edits on regression; originals
and persisted prior evidence are retained. Parent remains incomplete until four-host
usage, sizes and removal acceptance pass.

## Resume
Research recorded; first descriptor increment passed specification review. Strict schema gate tightened to the actually observed minor version. Implementing candidate extraction and failure-boundary tests; all-four usage remains open.
