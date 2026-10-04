# Cubase exported-track ownership: B1

Status: B1 IMPLEMENTED AND VERIFIED; independent Codex archive_spec_critic and archive_source_review passed. Codex sole writer.
Parent cleanup-essentials; risk 2; follow-up to usage-evidence-delivery.md.

## Outcome and scope
Extract plugin references with explicit owning exported tracks, preserving duplicates
and rename identity. This is the first structural Cubase acquisition route. It does
not parse CPR ownership, match installed products, measure Last used, or automate
exports in Prism. Keep the new report separate from ProjectReport/catalog persistence
until source association and timestamp contracts are admitted. No UI or state change.

## Research and runtime evidence
Official Cubase 15 archive documentation says XML includes selected tracks' channel
settings, parts/events and automation. It is partial selected-track coverage, not a
whole-session declaration:
https://www.steinberg.help/r/cubase-pro/15.0/en/cubase_nuendo/topics/track_handling/track_handling_exporting_tracks_as_track_archives_t.html
https://www.steinberg.help/r/cubase-pro/15.0/en/cubase_nuendo/topics/track_handling/track_handling_exporting_tracks_as_track_archive_c.html
Independent researcher rejected CubaseTools b525d6c0e6d01a6ec13c3c4d3401c7c7ac25155d:
closest-preceding-track byte assignment, unused context filter, name-based merging
are heuristics, not ownership grammar. Do not adopt them.

Root exported private copies in Cubase 15.0.30, Reference Media Files, compatibility
Cubase 13/Nuendo 13 or Newer. Baseline and removed exports retain three track nodes;
plugin references change 3→2 while the empty Diva-named track remains. A fourth
renamed duplicate track retains Diva's UID and Original Plugin Name while Plugin Name
becomes the arbitrary track label. This establishes why Original Plugin Name wins.
Files and screenshots remain in ignored build/usage-controls/cubase-ownership.
No original sessions saved; variant saved to isolated ownership-controls.cpr.

## Implementation contract
CubaseTrackArchiveReader.parse(Data) -> CubaseTrackArchiveReport, and inspect(URL).
CLI --inspect-cubase-archive FILE emits private JSON; exits 0 parsed partial export,
2 invalid/read failure with stderr and no JSON, 64 bad arguments. No automatic XML
extension scanning, no ProjectReport conversion, no current-project identity claim.

Use Foundation XMLParser without external entities; UTF-8 only, reject any DTD,
32 MiB input, depth 64, 100,000 elements, 4,096 tracks and 4,096 references. Abort
whole report on malformed/duplicate supported fields or bounds violations. Local
synchronous pure parsing; bounded arrays; no plugin execution or network. File entry
uses regular-file bounded read with final O_NOFOLLOW and preflight ancestor checks
(not race-resistant traversal). Exclude text/binary state from extraction.

Root tracklist2, one direct list name=track type=obj. Supported direct child classes
MAudioTrackEvent and MInstrumentTrackEvent. Track name only direct obj class=MListNode
name=Node / string name=Name. Track ordinal identifies its location within this
export; no dedup by name/UID, no use of pointer-like IDs as persistent identity.
Unsupported direct track objects count as unsupported coverage and never supply refs.

Only matching direct Track Device object classes MAudioTrack/MInstrumentTrack,
then member DeviceAttributes:
- member InsertFolder / list Slot type=list / item / member Plugin
- for instrument tracks only: member Synth Slot / member Plugin
At each admitted Plugin member require one direct string Plugin Name and one direct
member Plugin UID / string GUID (32 hex). Optional single direct Original Plugin Name
wins. Names nonblank, <=1,024 UTF-8 bytes. Duplicate identity/owner fields fail closed.
Slots may be absent/empty; do not infer unused. Ignore nested state names and refs;
never infer context from byte distance. Preserve owner track ordinal/name and role
insert or instrument per reference. No bypass/Active interpretation in this scope.
Archive XML has no verified host-version field; explicitly report observed layout,
not a version-derived guarantee. Other roots/namespaces reject.

Report contains adapter version, input SHA256, partial-export coverage, tracks and
per-track reference arrays, unsupported-track count and limitations. No timestamps,
resolved asset IDs, instance-count claims or absent-project-plugin declarations.
Unsupported substructures and tracks remain outside coverage. Ordinary CPR/XML scans
must remain unsupported and no catalog input route is added.

## Files / state / recovery
Sources/SimplifyCore/CubaseTrackArchiveReader.swift, Sources/SimplifyProbe/main.swift,
tests/SimplifyCoreTests/CubaseTrackArchiveTests.swift, scripts/probe_smoke.py,
this plan and research/evidence documents. No third-party code dependency added.
No persisted state: presets, undo, automation, migration, sync, copy/paste and defaults
not applicable; explicit local JSON export only, no import, analytics or upload.
Existing changes preserved; rollback this increment only. Native hooks unavailable;
deterministic gates used. Parent work remains open.

## Acceptance / verification
- Baseline 3 refs, removed 2, renamed duplicate 4 (two separate Diva refs); UID/name
  and explicit owner paths verified against original XML; source hashes unchanged.
- Synthetic decoys in Node/Browser/history/opaque state/nested wrappers do not create
  references; track-name collisions and renamed duplicates preserve distinct owners.
- XML bad root, namespace, duplicate supported fields, missing GUID/name, DTD,
  truncation, depth/node/input/track/reference budgets reject without partial output.
- File symlink/missing/directory, CLI arguments and failure outputs tested; normal
  project reader remains unsupported for these XML files and all CPR files.
- Independent critic, fresh review; tests, debug/release builds and real CLI replay.

Exact configured checks:
python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package
Native CLI replay of the three host-generated XML exports, hashes checked before/after.
python3 scripts/workflow_gate.py check-complete (parent expected open, not waived).
All source/doc edits invalidate fingerprints. Later B work includes bypass, rack,
outputs/groups, track versions and source association before production admission.

## Resume
B1 implemented after critique. Independent fresh review found no blocking issues and
replayed all real exports against a separate XML-tree implementation: 3/2/4 refs,
correct names/UIDs/roles and owners, unchanged input digests. 109 tests, CLI integration
and all eight configured checks passed. Original user files and isolated input CPRs
retain their initial hashes; new ownership-controls.cpr preserves the duplicate/rename
experiment. Cubase generated an additional audio copy in the isolated project during
host loading; it is research data only, not an inferred new sample identity.

Next B admission: extend controlled coverage to bypass, rack instruments, group/output
inserts and track versions, then establish how an export is associated with a saved
source revision. No manual export requirement has been added to the app. Offline CPR
ownership remains unproved; use exports as an independent oracle while researching
it. Continue other host acquisition and player identity work in the parent plan.
Last used, catalog integration, samples and exact Kontakt instruments remain open.

## B2 admission addendum — group inserts and inactive-reference controls

Status: B2 IMPLEMENTED AND VERIFIED. Independent Codex group_spec_critic and group_source_review passed; Codex sole writer, risk 2, same parent and boundaries as B1.
User authorized continued work. Private Cubase 15.0.30 controls now establish:
- Audio InsertFolder Bypass toggled 0→1; Pro-Q 4 reference retained.
- Renamed Diva track disabled through host context menu; its reference retained.
- Added Group track with Pro-Q 4, then removed Group track: expected export refs
  5→4 while existing bypassed and disabled dependencies remain present.
- Added Pro-Q 4 to Stereo Out and selected it with all other tracks. The saved CPR
  has three typed Pro-Q 4 records, but export has two and no Stereo Out track.
  This is a demonstrated export omission, not a parser bug or proof of non-use.

Official route/resources:
https://www.steinberg.help/r/cubase-pro/15.0/en/cubase_nuendo/topics/audio_effects/audio_effects_insert_effects_adding_to_group_channels_t.html
https://www.steinberg.help/r/cubase-pro/15.0/en/cubase_nuendo/topics/audio_effects/audio_effects_insert_effects_deactivating_t.html
Existing B1 track-export docs remain applicable. New XMLs and screenshots in ignored
build/usage-controls/cubase-ownership; original user sessions never saved or modified.

Scope: extend B1 to the observed group signature only: direct MDeviceTrackEvent /
obj name=Track Device class=MTrack / member DeviceAttributes, direct int Type=2 and
string IDString=GroupChannel, both exactly once. These observed values are not a
claim about all Cubase channel enum values. Use the existing direct InsertFolder
path only; no Synth Slot on this owner. Defer group admission until owner end so
field order does not matter. Unknown/missing signatures count as unsupported track
and emit no owner/refs. Duplicate supported signature fields fail closed. Provisional
parsing remains bounded and may reject malformed matching fields even in a device
track later found unsupported. Do not infer group identity from its display name.

Retain references irrespective of Active, Bypass or track-disabled flags; do not add
playback/load-status labels. Increment archive adapterVersion to 2. Explicitly state
in JSON that output-channel inserts were omitted by the tested host export, even
when selected. Source association, timestamps, rack/FX/folder/alternate paths and
catalog admission remain excluded. No new persistent state or schema migration.

Files: existing archive reader/tests, CLI integration tests if needed, this plan,
main delivery resume and fingerprinted evidence. Existing B1 budgets/guards unchanged.
Acceptance: before/after group controls 5/4, bypass/disabled each4, previous3/2/4
unchanged; group owner/name/UID correct; decoys/unknown group markers excluded;
duplicate signatures fail; Synth Slot on device owner excluded; field order robust.
Synthetic flags retain references. All original/session export hashes immutable.
Same eight configured checks and native debug/release replay as B1; independent
spec critic and fresh review required. Parent Last used gate remains open.

### B2 resume
Implemented adapter version 2 with exact direct group signature and deferred admission.
Five real exports reproduce 4/4/5/5/4 references in debug and release; full independent
XML-tree comparison checks every owner ordinal/name and plugin name/UID/role, not just
counts. Previous three exports still reproduce 3/2/4. Input bytes/mtimes and original
session hashes remain unchanged. Ordinary project inspection rejects every export.
The disabled-track differential includes an additional scalar named `tion`; its
meaning is not inferred. Tests preserve the observed shape without interpreting it.
Output omission is now explicit in the diagnostic report. Saved output-insert CPR
contains three typed Pro-Q records while its export contains two; this prevents
using the export as a complete dependency inventory. No Last used/catalog admission.
Next macro work remains acquisition coverage and source association across all hosts,
including a scoped Pro Tools official text-export adapter; exact Kontakt instrument
identity and timestamp qualification are still required before product integration.

B2 closure: all eight configured checks passed, including 111 unit tests and native
debug/release replay of eight real exports. Fresh read-only group_source_review
independently reproduced full owner/reference fields and found no blockers. Native
hooks were unavailable; deterministic gates supplied enforcement. Cross-client Claude
OAuth remains unavailable; independent Codex role separation is the recorded fallback.
Parent check-complete remains failed for outstanding usage/product acceptance gates;
this scoped diagnostic increment does not complete the parent task.
