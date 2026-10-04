# Pro Tools session-text evidence: B3

Status: IMPLEMENTED AND VERIFIED; independent Codex protools_text_critic and protools_text_review passed. Codex coordinator/sole writer; parent cleanup-essentials; risk 2.

## Outcome and non-goals
Acquire host-exported plugin listing and explicitly separate media-pool evidence for
four-host usage research. No PTX parsing, track ownership, timeline matching, installed
asset association, timestamps, Kontakt NKI identity, catalog admission or UI changes.
No manual-export requirement is added to the product.

## Research and current evidence
Installed Pro Tools 24.10.2.205; bundled Avid Reference Guide version 2024.10,
PDF pages 716–718 (printed 620–622), inspected with PDFKit. Official command exports
optional file/clip/plugin lists and audio-track EDLs; EDLs may be selected-track only,
exclude MIDI and use configurable time representations. User timestamps are timeline
positions, not wall-clock activity. File and clip lists are session pools, not proof
of timeline placement. Older public guide corroborates export structure:
https://resources.avid.com/SupportFiles/PT/Pro_Tools_Reference_Guide_12.8.2.pdf
Local Baseline.txt and Diva-removed.txt controls in ignored build/usage-controls
have three/two plugin rows, one online file, two channel clip rows, and one audio EDL.
Plugin listing includes Kontakt/Diva despite their absence from audio EDL. No plugin
UID, source project revision or host-version declaration is present in these exports.

## Interfaces / files / implementation
Add ProToolsSessionTextReader.swift (pure parse(Data), read-only inspect(URL)) and
Sendable Encodable report/row types; explicit --inspect-pro-tools-text FILE CLI;
ProToolsSessionTextTests.swift, scripts/probe_smoke.py, this and parent plan.
1. Independent specification critique, then implementation and synthetic tests.
2. Fresh independent read-only review, real baseline/removal debug/release replay.
3. Final configured checks/evidence; parent remains open.

Grammar deliberately limited to observed English UTF-8 export. Optional UTF-8 BOM;
LF/CRLF/CR normalized. Require exact ordered eight two-column session header labels:
SESSION NAME:, SAMPLE RATE:, BIT DEPTH:, SESSION START TIMECODE:, TIMECODE FORMAT:,
# OF AUDIO TRACKS:, # OF AUDIO CLIPS:, # OF AUDIO FILES:. Values nonempty, retained
only session name in report; no numeric/date inference from header values.
Then optional sections in observed strict order, no repeats:
O N L I N E  F I L E S  I N  S E S S I O N;
O F F L I N E  F I L E S  I N  S E S S I O N;
O N L I N E  C L I P S  I N  S E S S I O N;
P L U G - I N S  L I S T I N G.
Each heading followed immediately by exact trimmed tab-column heading array. Files:
Filename, Location (2 columns). Clips: CLIP NAME, Source File (heading 2 columns,
observed rows 3: clip name, source filename, raw channel token). Plugins: MANUFACTURER,
PLUG-IN NAME, VERSION, FORMAT, STEMS, NUMBER OF INSTANCES (6 columns). Trim space
padding, preserve duplicates/order. Every row cell nonblank; counts/status/channel
are raw text, not parsed semantics. Paths stay raw HFS-style strings, never resolved.
At least one supported section required. Absent section differs from present-empty:
report includedSections plus empty arrays. Missing section never means no plugins.
Blank separator lines allowed. Unknown/out-of-order/duplicate heading, incorrect
header/row width, blank fields and unsupported encoding fail whole report.
T R A C K  L I S T I N G or M A R K E R S  L I S T I N G terminates extraction:
remaining bounded text explicitly unparsed, cannot inject plugin/media rows. No global
label searches. Unsupported offline clip/other sections before terminal reject.
Output: adapterVersion=1, coverage=partial-export, inputSHA256, sessionName,
includedSections, plugins (manufacturer/name/version/format/stems/instanceSummary),
files (availability online/offline/name/location), clips (name/sourceFile/channel).
Limitations: optional unvalidated completeness, no track ownership, no stable plugin
ID, raw counts/status, media pool not timeline, unresolved paths, no NKI, no project
association or wall-clock use time, no catalog/cleanup admission. Text is not an
authenticated session; matching grammar never proves provenance or completeness.

## Bounds / risks / recovery
Synchronous local isolated parsing, no shared state/plugin execution/network. Input
32 MiB, 100,000 lines, 16 KiB per line, 1,024 UTF-8 bytes per field, 4,096 total rows
across extracted sections; fail whole report on exceeded bound. Reject NUL/controls
except TAB/CR/LF; UTF-8 only. inspect uses BoundedFile regular-file/O_NOFOLLOW and
ancestor symlink preflight (not atomic traversal). No source writes. Saved names and
paths remain private; synthetic fixtures only in tracked files. Malformed/export
variants fail closed; lack of final checksum means removed valid rows cannot be detected.
Rollback only this increment, preserving existing user work.

## Acceptance / verification / runtime
- Real baseline/removal yields plugin names 3→2, same 1 file/2 clip rows, full field
  equality and hashes/mtimes unchanged; debug and release.
- Missing vs empty section distinguished; table order/duplicates/decoys/row bounds,
  bad encoding, truncation within header/row and file symlinks rejected. Track-tail
  plugin-like decoys never parsed; duplicate names retained; mixed raw status retained.
- CLI 0 parsed partial report, 2 rejection stderr/no JSON, 64 invalid args, 1 output
  failure. Ordinary ProjectReader .txt remains unsupported/no references.
- Independent critic and fresh reviewer pass; all configured checks pass.
Exact runner: python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package
python3 scripts/workflow_gate.py check-complete reports parent honestly, not waived.

## State / gates / resume
No state IDs/persistence: presets/default/reset/migration/undo/automation/copy-paste/
sync/accessibility/analytics/import not applicable; explicit local JSON export only.
No UI gate claimed. Native hooks unavailable; deterministic scripts used. Prior
cross-client Claude OAuth failure remains; independent Codex role fallback recorded.
Source/test/doc changes invalidate fingerprints; rerun downstream affected gates.
Implementation, independent source review and all eight configured checks passed; final evidence records current content fingerprint. Other-host acquisition,
exact asset identity and timestamp ledger remain in macro plan, not silently admitted.

## B3 resume and evidence
Five new tests bring the suite to 116 passing tests. Initial test compilation caught
an extra parenthesis in one new fixture assertion; corrected and unit tests rerun.
Independent reviewer reproduced every native export field, section-presence marker
and digest. Coordinator debug/release replay matches 3→2 plugins, one file and two
clips each; all input text/session bytes and modification times remain unchanged.
CLI integration verifies invalid arguments, rejected input and ordinary-reader
non-admission. No GUI or catalog behavior change is claimed.
Next work: validate timeline-to-clip-to-file ownership separately from media pools,
then establish source revision association and format-specific installed plugin IDs.
Logic structural acquisition and exact Kontakt NKI identity remain unproved. A host
export is still an oracle for acquisition research, not an automatic usage solution.
The parent Last used gate is intentionally open.
