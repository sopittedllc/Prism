# Pro Tools track-event evidence: B4

Status: IMPLEMENTED AND VERIFIED; independent Codex group_source_review specification critique and container_review source review PASS; Codex sole writer; risk 2; parent cleanup-essentials open.

## Outcome / research
Separate actual exported audio-track events from pool-only media. B3 already parses
optional plugin/file/clip lists but ignores track tails. Installed Avid 2024.10 Guide,
PDF pages717–718 (printed621–622), defines audio EDLs, selected/all-track options,
no MIDI EDL, and user timestamps as timeline positions. Installed host24.10.2.205.
Controls in ignored build/usage-controls/protools-timeline: opened a separate copy of
Baseline.ptx, selected audio track's whole clip, used Mute Clips, exported Muted.txt;
then Clear on that edit selection, saved PoolOnly.ptx and exported Pool-only-control.txt.
Muted retains two stereo events with State=Muted; pool-only retains 1 file/2 clips and
an empty audio-track event table. All-track export, timecode, no user timestamp/subframe.
Muted.ptx preserves muted state. Baseline originals remain unchanged. One initially
exported temporary file was overwritten by a case-insensitive AX dump filename clash;
that file is excluded and native export repeated to the distinct control filename.
No media file removed; no external drive required; no playback or recording invoked.

## Scope / non-goals / interfaces
Extend ProToolsSessionTextReader report adapterVersion=2 with tracks and events. No
PTX parser, wall-clock time, source-session identity, installed asset/path matching,
Kontakt identity, plugin ownership from track labels, UI or catalog admission.
Events describe the optional exported audio EDL only, not complete project membership.
No inferred unused assets. No manual export requirement added to app.
Files: existing reader/tests, CLI smoke, plans/evidence. Types Sendable/Encodable:
track ordinal(document-local), name, comments, userDelay, state, pluginSummary(raw), events;
event channel(raw), eventNumber(raw), clipName, start/end/duration(raw), state(raw),
clipPoolOrdinal?, filePoolOrdinal?, bindingStatus. Indices refer to this report only.

## Grammar / binding contract
Retain B3 input/encoding/header/table guards. Recognize optional TRACK LISTING after
pool/plugin sections, at most once; allow tracks-only exports with those tables absent.
For each track require contiguous observed ordered metadata:
TRACK NAME:\tvalue; COMMENTS:\tvalue (empty allowed); USER DELAY:\tvalue;
STATE: space-padded raw value (may be empty, no tab in observed line);
PLUG-INS: space-padded label \t raw summary (empty allowed).
Then exact seven tab-separated headings CHANNEL,EVENT,CLIP NAME,START TIME,END TIME,
DURATION,STATE. Values trimmed of ASCII space padding, bounded1,024bytes. Other
metadata and table layouts (timestamps, extra columns, wrapped comments) reject.
Blank separator lines allowed between tracks/events; no blank lines inside metadata.
Track names may repeat: preserve ordinal. Event rows exactly7 nonempty fields;
channel/event numbers must be positive decimal digit tokens (preserve raw, no Int
conversion), other fields uninterpreted nonempty strings. Muted/inactive-looking
state never suppresses a row. No timecode math or date parsing. Empty track event
tables valid; missing header rejects. EOF after full metadata/header valid; row-width
truncation rejects. Track listing present-empty (no tracks) distinguished from absent.
Markers terminate parsing; remainder remains bounded but unparsed. Headings inside
cells cannot become structure; pool/plugin sections after tracks reject.

Binding is an explicit within-export name join, not an asset match: build name maps
with count and first ordinal. For each event, exact case-sensitive clipName must occur
once in the online clip list; duplicate rows count as ambiguous even if identical.
If unique, record clipPoolOrdinal; exact sourceFile must then occur once in combined
online/offline file pool to record filePoolOrdinal. Never concatenate/resolve raw HFS
locations. Status: clip-list-omitted / missing-clip-name / ambiguous-clip-name /
file-list-omitted / missing-file-name / ambiguous-file-name / unique-export-row.
File-list-omitted only when both online/offline sections absent. Retain events with
missing/ambiguous joins; no first-match fallback or inference from track channel.
Linear maps + linear joins, no quadratic expansion. Omitted/partial tables and unauthenticated
text mean even a unique row link does not prove source-file identity or completeness.

## Bounds / state / risk
Existing32MiB/100k lines/16KiB line/1,024field bytes apply to full text incl marker tail.
Existing4,096 pool rows now shared with events globally; separate1,024track maximum.
All-or-nothing rejection; no partial successful report after malformed matching section.
Synchronous call-owned state; no network/plugin execution/writes. Existing bounded
regular-file and symlink checks unchanged. No persistent state ID, defaults, migration,
presets, undo, automation, sync, analytics, import; explicit local JSON export only.
Privacy same as B3. Rollback this increment only, preserving existing work.

## Acceptance / steps / verification
1. Independent spec critique before code. Implement parser + binding + truthful limitations.
2. Tests: exact owner fields, duplicate names, muted rows retained, pool-only vs timeline,
   absent/empty sections, all binding failure statuses, identical duplicate ambiguity,
   unsupported/truncated/duplicate/reordered headers, cell decoys, shared budgets and
   whole-input guards. Update B3 tests that intentionally used invalid unparsed tracks:
   such inputs now must reject. Marker decoys remain ignored.
3. Real controls baseline and plugin-removed each2events, muted2, pool-only0 with same
   1file/2clips; full field equality and input hashes/mtimes debug/release. Ordinary
   ProjectReader remains unsupported. Fresh read-only source review.
4. Exact runner: python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package
   python3 scripts/workflow_gate.py check-complete (parent expected open).
Native hooks unavailable: deterministic scripts. Prior Claude OAuth failure documented;
independent Codex critic/reviewer fallback. Source/test/doc edits invalidate evidence.
No GUI change; host controls do not satisfy parent Prism UI gates.
Resume: all eight configured checks, 124 tests and debug/release native replay passed. Independent critique/review passed. Final fingerprinted evidence recorded under parent; parent Last used remains open. Last used/identity/source association
and full four-host qualification remain outstanding.

## Implementation results
Adapter version 2 preserves raw audio-track metadata and events; per-report pool
ordinals exist only for unique exact-name matches. Duplicate identical rows remain
ambiguous; successful clip links survive failed file joins. No track plugin-summary
parsing or catalog link introduced. Track and pooled rows share the global budget.
Independent fresh source reviewer replayed debug output against all four native exports;
coordinator also replayed release. Exact owner/event fields, raw states, row links,
hashes/mtimes agree; event counts 2/2/2/0, file/clip pools 1/2 for each. Original 14 user
fixture hashes verified unchanged. Five new tests bring total to 124; CLI integration
includes a muted event with omitted clip list and rejected malformed input.
Next admission remains source-project revision association and exact installed asset
identity; raw HFS paths and names alone cannot supply either. Logic/Kontakt and other
four-host gaps remain explicit. Native GUI controls did not access disconnected drives.
