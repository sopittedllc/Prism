# Collection and setup design

The earlier screen stacked navigation, actions, status and details vertically. The replacement gives the collection most space: a compact branded sidebar, list and contextual inspector. Setup uses a single native locations list and an explicit Scan. Samples alone show project recency; plugin/library reference availability remains in the inspector.

Research: [Apple onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding?changes=_7), [Finder views](https://support.apple.com/en-kg/guide/mac-help/mchldaafb302/mac), [XO sample folders](https://support.xlnaudio.com/hc/en-us/articles/16920660349085-Adding-your-own-samples), [DaisyDisk scan scope](https://daisydiskapp.com/guide/1/en/DisksOverview/). The recurring patterns are brief interactive setup, explicit scan scope, a persistent collection hierarchy, and contextual details. Applying these together is a Simplify design inference, not proof of usability. Official source details and alternatives are in the task research evidence.

Setup: one Collection locations sheet, standard-plugin checkbox and Type/Folder table.
Add folders chooses Samples, Libraries, optional Projects or Custom plugins; Remove
changes the selected draft row. Cancel discards the draft. Scan saves roots, toggle and
completion flag atomically before starting. Save failure retains the form and exposes
Scan without saving. Settings reopens the same form with saved values.

Local schema version 1 uses native registry-selected IDs. Missing keys default; unknown keys ignored; malformed/wrong-type/relative root/unsupported-version data rejected without replacement. Reads reject nonregular files and are bounded at 1 MiB. Saves are atomic. No older persisted release exists; unsupported version handling is tested rather than invented migrations. Transient list selection and draft are discarded controller state. No presets, telemetry, sync or export of setup.

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

### Saved collection states
On launch, browse the last final catalog for the exact configured sources. The footer
says “Saved collection · Scan to refresh”; its tooltip has the snapshot time. This is
not a current availability check. Retained unobserved rows/patches say “Not observed”
in text, never color alone. Existing native table, search, inspector and source controls
remain usable during restore and background scans. Catalog failures appear in the
footer and leave live results available. Cached/stale plugin-format checkboxes and
removal actions are disabled with a scan-to-verify explanation; viewing paths remains
available. No extra setup step or account is required. The native hierarchy uses the established collection shell and spacing system.
Setup review describes local setup and collection persistence. Format summaries separate
selected, kept, needs-scan and removed installations; unverified cached entries never
appear as zero retained entries or as proven unavailable. Native persistence cases cover
cached light/compact browsing, offline library/instrument labels, disabled stale plugin
removal and corrupt-catalog save failure with live results retained.

## Hierarchical collection browsing
The shared collection component is a native NSOutlineView. Plugins remain product leaves.
Libraries show maker → library installation → instrument; makers start expanded and
libraries collapsed. Proposed or unresolved product boundaries live in Needs identification.
Separate installations and distinct vendor products sharing a container remain distinct.
Individual Samples shows configured root → real relative directories → discovered audio
file, with only the most specific selected root owning each sample. Empty directories are
not enumerated by this presentation layer. Equal root names include a distinguishing parent suffix. Location tooltips retain the exact path.

Disclosure uses native controls and arrow keys. Rows keep the shared 38pt height and 8pt
text inset; each depth adds 16pt native indentation. Maker/folder selection describes the
group; maker groups have no Finder action. Instrument details retain maker/library
breadcrumb, inherited context tags, exact locator and Unknown usage. Library installed
size stays Not measured until measured storage accounting lands; instrument size is Shared
with library. Header ordering applies consistently to sibling rows.

Library search retains only matching instruments and their ancestors; metadata-only library
hits explicitly say Library tags match and do not invent installed patches. Query text
is emphasized in names/details. Sample search is flat with a root-relative breadcrumb line; format and details identify audio files.
sorting applies across roots. Full location remains in details/tooltips. Search has separate
navigation state, so no-match → clear and category roundtrips preserve browsing position.
View state is session-only and resets on a new launch; inventory remains durable.

## Composer discovery v1

Browsing now uses a single names-and-tags search field, without facet, usage, recent,
or sort dropdowns. Names include maker and parent library context; paths and internal
classification prose do not match. Instrument searches require an instrument-local
name/tag match to avoid promoting unrelated siblings.

Column headers toggle native sort descriptors. Names and formats start ascending;
sizes and dates start descending. Unknowns follow known values in both directions.
Groups stay ahead of children and ties use stable names/identities. Sorting preserves
selection and expansions. Installed dates remain Unknown until verified; sample Project
recency is explicitly a modification-time proxy. First observation never fills Installed.

The inspector shows one format subtitle, effective tags, compact lifecycle/size facts,
necessary library context and availability. Location sits immediately beside Show in
Finder; full selectable wrapping paths remain visible in a bounded scrolling section. Each
plugin format has its own path and matching Finder action. No Technical details sheet, duplicate Audio file prose, repeated
format section or provenance essay. Edit tags opens the existing draft sheet; Undo is
shown when available. Plugin format management remains available.

Tag settings opens a transient popover containing the existing opt-in online preference,
retry, status and selected-product provenance. No preference semantics change. Sources
remain limited to exact reviewed products; user edits override all suggestions. Popover
presentation is disposable, not persisted. Metadata editor Save/Cancel/error handling
and sample-specific fields remain unchanged.

Columns retain readable minimums; compact Format moves to the inspector unless actively
sorted, preserving date and size visibility. Native horizontal scrolling remains available. Verify
actual light/dark layouts at minimum/default sizes and ensure important date fields can
be reached. This scoped UI change does not satisfy the four-host usage release gate.


## Compact setup and direct tag editing

Setup uses a compact single sheet with a native scrollable table and add/remove controls.
No step counter, Back/Continue or redundant review page. Standard plugin folders default
on for new setups; saved choices remain intact. Full paths distinguish equal folder
names. Folder removal retains list focus. The same component handles empty, mixed,
overflow and save-failure states. Native precedents: macOS Login Items and Time Machine
exclusions; HIG onboarding favors brief optional configuration with useful defaults.

Inspector tags are category-colored pills inspired by Logic's track palette. Color is
paired with category tooltips and accessible names. Pills wrap; long sets scroll. Each
pill reserves a remove button revealed on hover or keyboard focus. A trailing + opens a
single-tag category/value draft. Add and removal persist immediately, with one Undo.
The advanced field editor lives in Tag settings for restoring suggestions.

Plugin pills show a category/value union across current formats. Each add/remove changes
only that tag in each applicable installation's own effective category. All writes and
Undo are atomic, preserve unrelated differences, and retain explicit empty arrays to
suppress suggestions. Failure leaves data and Undo unchanged. No-op formats keep their
suggestion behavior. Scope is disclosed in tooltips and the Add draft. Future formats
are not promised propagation. No files are removed by a tag action.

## Settings and appearance
Sidebar Settings… and application-menu Settings… (Command-comma) open the same sheet.
Appearance sits above Collection locations: Light (default), Dark, Match system
preference. Choice previews across the app; Cancel restores accepted mode. Save
persists without scanning; changed folders retain the Scan-to-update status. Initial
setup still offers Scan. Failed saves retain the form and offer Use for this session.
AppKit application appearance governs windows, sheets, popovers and dynamic colors.

## Prism branding
Public name is Prism. The supplied black-on-white burst artwork is preserved in
Resources/PrismLogo.jpg; packaging scales the original into sidebar and Dock resources.
Internal module names, bundle ID and legacy local storage paths remain stable for
existing settings and collections. New local app bundle is build/Prism.app.

## Focused sections and plugin products
The toolbar Scan refreshes the section selected at click; switching tabs does not retarget
it. First-run Scan initializes all configured sections. Progress names the captured
section. Saved inventory, metadata and sample reference evidence in other sections stay
available. Standard plugin locations are automatic; Settings only adds extra folders.
The standalone Tag settings entry is removed. Settings holds online-tag opt-in/Retry;
source provenance is available on the selected pills' tooltip. Right-click Edit tags
opens the full editor for that clicked item. Plugin rows have combined formats under
the name and no Format column; library/sample formats retain their existing column.
Soundtoys grouping recognizes verified com.soundtoys.<format>.<product> identities,
keeping Deluxe, version and publisher differences separate.


## Installer-record date presentation
Plugin tables label the date column **Installer record**. Samples/libraries label their
independent unknown acquisition field **Date added**. Header clicks sort actual event
times newest/oldest with unknowns last. Grouped plugins show the latest typed receipt
among exact constituent installations; the inspector states the winning format and
Records for X of Y installations. Equal dates resolve by exact node/source/event bytes.
Date added and Last used remain independent, with no receipt fallback.

The inspector explains once that a record can describe an install or update. The existing
format sheet shows each installation's receipt date, package version and selectable
source ID, and refreshes while open. Cell accessibility describes full dates and coverage;
partial coverage never depends only on hover/color. Numeric dates follow locale ordering.
At compact sizes plugin Size and Last used columns share the width adjustment needed
for the full Installer record header and its sort indicator. The standard38pt rows remain.

Atomic background projection reloads after restore, inventory save and receipt collection.
Known history remains during source checking/failure; incomplete lookup gets explicit
text in the inspector. Invalid saved evidence instead shows Unavailable with Scan to retry.
Cached/offline history says current installation not verified. Plugin inventory temporarily
shows Checking until current IDs settle; sample/library scans do not suppress plugin dates.
No sample or individual instrument inherits a player/library receipt. Sorting refreshes
without changing selected identity or expansion state.

Design evidence: Apple HIG [lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables),
[Finder ordering](https://support.apple.com/en-my/guide/mac-help/-mchlp1745/mac),
[System Information installation history](https://support.apple.com/en-ca/101591), and
[App Store purchase history](https://support.apple.com/en-ie/118212). Distinguishing these
dates is a project inference from separate shipped workflows. Native fixtures cover
partial groups, known/unknown ordering, live format details, saved history, failure,
accessibility labels and compact/light/dark layout; human VoiceOver and older systems
remain outside this scoped runtime validation.

### Date added precision (supersedes receipt table column)
Use Date added in every category. Exact evidence displays a date; observed arrival
displays During or a two-line range; known presence displays By. Initial inventories
never look newly acquired. Details explain arrival/return may be a move or restored
copy and older acquisition may be unknown. Receipt history remains secondary in the
inspector and per-format sheet. Sort upper bounds, then lower/precision, unknownlast;
help explicitly distinguishes latest possible addition from actual acquisition order.
Group bounds use conservative interval arithmetic across every installation. Unknown
instrument dates never inherit their library/player's date. Shared cells permit two
lines to keep both range endpoints and qualifiers at1040px. See addition-date-bounds plan.

### Last used with a DAW-local clock
Qualified Live VST3 completed session restores display the reported calendar date and
DAW local on two lines. Details identify the host, unknown timezone, product-class
scope, partial coverage and saved history. Never interpret this civil timestamp in the
current Mac timezone. Plugin Last used sorts reported calendar days, unknown last in
both directions; sample Project recency remains explicitly separate. Instrument and
library usage never inherit player use. Usage unknown filters only rows without
qualified positive history; it is not an inactivity or safe-removal filter.
