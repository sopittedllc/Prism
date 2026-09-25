# Collection and setup design

The earlier screen stacked navigation, actions, status and details vertically. The replacement gives the collection most space: a compact branded sidebar, list and contextual inspector. Setup performs the actual folder choices in four steps, then an explicit scan. Samples alone show project recency; plugin/library reference availability remains in the inspector.

Research: [Apple onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding?changes=_7), [Finder views](https://support.apple.com/en-kg/guide/mac-help/mchldaafb302/mac), [XO sample folders](https://support.xlnaudio.com/hc/en-us/articles/16920660349085-Adding-your-own-samples), [DaisyDisk scan scope](https://daisydiskapp.com/guide/1/en/DisksOverview/). The recurring patterns are brief interactive setup, explicit scan scope, a persistent collection hierarchy, and contextual details. Applying these together is a Simplify design inference, not proof of usability. Official source details and alternatives are in the task research evidence.

Setup: Welcome (standard plugins) → Your sounds (samples/libraries) → Your projects (optional) → Review/Scan. Back retains the draft; Cancel/Set up later discards it. Manage locations reopens the flow. Save setup & Scan stores only chosen roots, the plugin toggle and completion flag in local Application Support/Simplify/setup.json. Filters, selection and scan results reset each launch. Use for this session & Scan offers recovery when setup cannot be saved. No automatic or recurring scan is implied.

Local schema version 1 uses native registry-selected IDs. Missing keys default; unknown keys ignored; malformed/wrong-type/relative root/unsupported-version data rejected without replacement. Reads reject nonregular files and are bounded at 1 MiB. Saves are atomic. No older persisted release exists; unsupported version handling is tested rather than invented migrations. Transient wizard stage and draft are discarded controller state. No presets, telemetry, sync or export of setup.

The provided PNG is used with its RGB and alpha intact. Packaging scales it onto a white rounded Dock tile and creates a smaller sidebar resource. Runtime sets applicationIconImage explicitly. A previous implementation incorrectly discarded alpha and exposed hidden RGB pixels, producing a different shape; that conversion is removed. Compare the rendered original with the packaged mark, not RGB bytes alone. Actual Dock visibility is part of runtime validation.

Tests use synthetic data and isolated settings. Light/dark, minimum/typical window, setup transitions, search, keyboard focus, selection and async scanning are exercised. This is a new intentional visual baseline; VoiceOver human testing and older macOS/Intel remain open.


Scans now have a persistent live banner. Discovery reports entries checked and current location without inventing a denominator. Reading files and matching references each show a percentage of their own known work, labeled stage 2/3 and 3/3. Elapsed time updates once per second; the scanner emits throttled events separately from collection reloads. A 100% stage or finished scan does not mean reference coverage is complete; scan issues remain available. No ETA is shown because directory discovery and external/cloud storage have variable cost.

## Audit refinements (2026-09-25)
Table cells share 8pt horizontal inset and vertical centering. Navigation retains
full-row hit targets with 10pt content inset. Folder lists anchor to the top of a
flipped document; cards follow parent width. Folder edits restore focus to that
category chooser. Inspector headings are capped at three lines with full tooltip,
and both selected/empty body text reset explicit typography.

Basic assets stream at most once per second (first item and inventory boundary
are immediate). Project traversal and detailed reads follow the asset boundary.
The browser remains usable; reference history says checking until final analysis.
After 10 seconds even stalled discovery uses background status, without claiming
files were found or inventing a percentage. No hard I/O timeout is imposed.
The determinate bar renders the exact numeric percentage without interpolation.

## Product-level plugins and explicit removal
Plugin rows represent compatible name/bundle-ID groups, preserving all installed
formats in the inspector. Unknown/conflicting identities remain separate. Manage
formats opens a740pt sheet with default Keep choices, selected/all review actions,
full selectable paths in confirmation, and per-installation failure recovery.
Only reviewed unchanged plugin bundle directories move to macOS Trash. No automatic
auxiliary cleanup or sample/library removal. Candidate REAPER name evidence and
unsupported DAW coverage stay distinct from verified dependencies.
Folder setup uses Add folders, current folder counts, repeated multi-select and
explicit more-specific-root precedence. Empty states disclose saved/unscanned roots
and partial scan issues; entry limits are per category to avoid starving projects.
