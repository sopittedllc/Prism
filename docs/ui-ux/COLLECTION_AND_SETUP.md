# Collection and setup design

The collection uses a compact branded sidebar, list and contextual inspector. First-run setup gathers Sample Libraries, optional Individual Sounds, optional Projects, and Review & Scan before one collection scan. Project-reference recency is shown only when qualified saved-project evidence exists.

Research: [Apple onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding?changes=_7), [Finder views](https://support.apple.com/en-kg/guide/mac-help/mchldaafb302/mac), [XO sample folders](https://support.xlnaudio.com/hc/en-us/articles/16920660349085-Adding-your-own-samples), [DaisyDisk scan scope](https://daisydiskapp.com/guide/1/en/DisksOverview/). The recurring patterns are brief interactive setup, explicit scan scope, a persistent collection hierarchy, and contextual details. Applying these together is a Simplify design inference, not proof of usability. Official source details and alternatives are in the task research evidence.

First-run setup uses one native sheet with Sample Libraries, Individual Sounds, Projects,
and Review & Scan steps. Each location step lists only its kind. Individual Sounds is
optional and covers loops, one-shots, and sample packs. Standard system plugins are
automatic; no new custom-plugin folder can be added. Previously saved custom-plugin
roots remain visible and removable in Settings and Review. Projects explains that
supported saved references can qualify Last Used; incomplete or unsupported projects
leave usage unknown. Its privacy note says scanning reads files without editing,
uploading, or sharing their contents, and the catalog stays on this Mac. Back retains
the draft; Cancel discards it. Review lists every selected root and Scan collection atomically saves
the roots and completion flag before starting. Save failure retains Review and offers
Scan without saving for this session. Existing saved users bypass the wizard. Settings
reopens a flat editor with accepted values and Save does not scan.

Local schema version 1 uses native registry-selected IDs. Missing keys default; unknown keys ignored; malformed/wrong-type/relative root/unsupported-version data rejected without replacement. Reads reject nonregular files and are bounded at 1 MiB. Saves are atomic. No older persisted release exists; unsupported version handling is tested rather than invented migrations. Transient list selection and draft are discarded controller state. No presets, telemetry, sync or export of setup.

The provided PNG is used with its RGB and alpha intact. Packaging scales it onto a white rounded Dock tile and creates a smaller sidebar resource. Runtime sets applicationIconImage explicitly. A previous implementation incorrectly discarded alpha and exposed hidden RGB pixels, producing a different shape; that conversion is removed. Compare the rendered original with the packaged mark, not RGB bytes alone. Actual Dock visibility is part of runtime validation.

Tests use synthetic data and isolated settings. Light/dark, minimum/typical window, setup transitions, search, keyboard focus, selection and async scanning are exercised. This is a new intentional visual baseline; VoiceOver human testing and older macOS/Intel remain open.


The Check For Updates button checks plugins, samples, libraries and projects from every tab. It becomes Stop during work; Stop cancels and returns to Check For Updates while retaining the last accepted catalog. The live banner says Checking for changes, Updating collection and Matching references. Discovery reports entries checked and current location without inventing a denominator. Later stages show percentages of their own known work. Elapsed time updates once per second. A finished refresh does not mean reference coverage is complete; issues remain available. No ETA is shown because directory discovery and external/cloud storage have variable cost.

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
Plugin rows represent one durable product identified by verified product-specific
bundle identity, with physical formats as attributes. Unknown/conflicting identities remain separate. Manage
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
says “Saved collection · Choose Check For Updates to verify changes”; its tooltip has the snapshot time. This is
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
Libraries show maker → library installation → instrument → source-qualified articulation;
makers start expanded and
libraries collapsed. Proposed or unresolved product boundaries live in Needs identification.
Unassociated SINE metadata/archive pairs appear there as literal physical-content
rows with measured pair bytes; they are not named products or invented patches.
Separate installations and distinct vendor products sharing a container remain distinct.
Individual Samples shows configured root → real relative directories → discovered audio
file, with only the most specific selected root owning each sample. Empty directories are
not enumerated by this presentation layer. Equal root names include a distinguishing parent suffix. Location tooltips retain the exact path.

Disclosure uses native controls and arrow keys. Collection groups keep the compact
38pt height; item rows use a fixed 64pt height, or 82pt when plugin format or sample
breadcrumb context needs its own line, for up to two lines of read-only facet-colored
tag pills beneath the name. Pill text has equal vertical insets. An `+N more`
button opens a transient All tags popover with full labels; Escape closes it and
returns focus. Each depth adds
16pt native indentation. Maker/folder selection describes the
group; maker groups have no Finder action. Instrument rows retain maker/library
breadcrumb, inherited context tags, exact locator and Unknown usage. Library logical
size is shown when safe metadata-only storage accounting succeeds; detail names the
measurement basis. Unsafe or failed measurement says Size unavailable with a source
issue, never a guessed zero. Instrument size is Shared with library. Size sorting places library
installations in one global ordered list with maker breadcrumbs.

Library search retains only matching instruments, their matching articulation children,
and ancestors; metadata-only library
hits do not invent installed patches. One-letter name prefixes work during typing;
numeric and typed tag tokens retain exact matching. Sample search is flat with a
root-relative breadcrumb line and cross-root sorting. Full location remains in Finder tooltips. Search has separate
navigation state, so no-match → clear and category roundtrips preserve browsing position.
View state is session-only and resets on a new launch; inventory remains durable.

## Composer discovery v1

Browsing uses a single names-and-tags search field and a Sort control in every category.
Tags sorting remains available while the narrow Tags table column is hidden to give
names and pills more room. Names include maker
and parent library context; paths and internal
classification prose do not match. Instrument searches require an instrument-local
name/tag match to avoid promoting unrelated siblings.

An articulation is a named technique under its physical patch, with the patch's Finder
location and tag context. It does not acquire a separate size, date or usage fact.
SINE local catalog relations, reviewed Kontakt individual patches and verified
Spitfire brush headers can supply names; mic positions and rest-shell placeholders
stay outside the outline. A patch with one verified technique uses one row; patches
with multiple techniques disclose children. Unknown extraction coverage never shows
legacy guesses as verified choices. Search checks all words against one patch and at
most one articulation plus library
identity, in either word order. Factual technique titles remain searchable after a
tag override suppresses suggestions. `celli`/`cellos` match `cello`, and `harmonics`
matches `harmonic`; keys and numeric terms retain their prior exact behavior. Flat
Tags and Date added sorts keep articulation children attached to the patch. Search
clear restores the browsing expansion and selection, including selected techniques.

Column headers toggle native sort descriptors. Names and Tags start ascending;
sizes and dates start descending. Unknowns follow known values in both directions.
Groups stay ahead of children and ties use stable names/identities. Sorting preserves
selection and expansions. Installed dates remain Unknown until verified; sample Project
recency is explicitly a modification-time proxy. First observation never fills Installed.

The inspector shows the selected sound, its format subtitle, effective tags, and short
Last used, Date added, and Size values. Show in Finder serves sample and library items;
Manage formats keeps every plugin installation's path and Finder action accessible.
There is no Show Details disclosure or history body. Edit tags opens the existing
draft sheet; Undo is shown when available.

Product tags come from the bundled catalog, compatible offline caches and user edits.
Selected-pill provenance remains available without a network preference or Retry.
Metadata editor Save/Cancel/error handling and sample-specific fields remain unchanged.

The main Settings sheet also shows the OS-owned Accessibility status for Logic mixer
observations. Request Accessibility Access invokes macOS's standard permission prompt;
the status refreshes when Prism becomes active again. This permission lets Prism read
visible Logic mixer plugin names during periodic checks. Brief instances can be missed,
so Accessibility access does not establish exact instantiation time or provide Kontakt
or SINE instrument history. Permission state is read from macOS each time and is never
saved as a Prism preference. Settings also links to Steinberg's Usage Logging instructions.
Cubase logging is opt-in in Cubase preferences; Prism reads supported local log records
when present and never changes Cubase preferences.

Columns retain readable minimums; compact Format moves to the inspector unless actively
sorted, preserving date and size visibility. Native horizontal scrolling remains available. Verify
actual light/dark layouts at minimum/default sizes and ensure important date fields can
be reached. This scoped UI change does not satisfy the four-host usage release gate.


## Compact setup and direct tag editing

First-run setup uses three compact steps: Sounds, Projects, and Review. Back keeps the
draft; Cancel discards it; only the final Review accepts the scope and starts a collection check.
The Projects step offers an explicit way to continue without project folders. Review
shows the selected folder counts and whether standard system plugin folders are included.
Standard plugin folders default on for new setups; saved choices remain intact. Full
paths distinguish equal folder names, and folder removal retains list focus. Settings
uses a direct editor for later changes, with a native scrollable table and add/remove
controls. Both surfaces handle empty, mixed, overflow, and save-failure states.

Inspector tags are category-colored pills inspired by Logic's track palette. Color is
paired with category tooltips and accessible names. Pills wrap; long sets scroll. Each
pill reserves a remove button revealed on hover or keyboard focus. A trailing + opens a
single-tag category/value draft. Add and removal persist immediately, with one Undo.
The advanced field editor lives in Tag settings for restoring suggestions.

Plugin pills show one product-owned tag set, including canonical suggestions from all
current formats. Each add/remove writes the product once and has one Undo. Explicit
empty overrides suppress suggestions. The same tags drive the visible Tags column,
alphabetical sort, and search, including after a new format or restart. No files are
removed by a tag action.

## Settings and appearance
Sidebar Settings… and application-menu Settings… (Command-comma) open the same sheet.
Appearance sits above Collection locations: Light (default), Dark, Match system
preference. Choice previews across the app; Cancel restores accepted mode. Save
persists without scanning; changed folders retain the Check For Updates prompt. Initial
setup scans only from Review. Failed saves retain the form and offer Use for this session.
AppKit application appearance governs windows, sheets, popovers and dynamic colors.

## Prism branding
Public name is Prism. The supplied black-on-white burst artwork is preserved in
Resources/PrismLogo.jpg; packaging scales the original into sidebar and Dock resources.
Internal module names, bundle ID and legacy local storage paths remain stable for
existing settings and collections. New local app bundle is build/Prism.app.

## Global collection refresh and plugin products
The toolbar’s Check For Updates button checks every configured section and project root regardless of the
selected tab. Switching tabs does not change scope. Stop cancels the current work and
keeps the last accepted collection until a later check. Per-source decoded facts are
reused only when reader policy and all dependency stamps agree, including absent
optional sidecars. Metadata traversal and current physical binding still run. Standard
plugin locations are automatic; Settings only adds extra folders.
The standalone Tag settings entry is removed. Settings contains no tag-network controls;
source provenance is available on the selected pills' tooltip. Right-click Edit tags
opens the full editor for that clicked item. Plugin rows have combined formats under
the name and no Format column; library/sample formats retain their existing column.
Soundtoys grouping recognizes verified com.soundtoys.<format>.<product> identities,
keeping Deluxe, version and publisher differences separate.


## Qualified dates and product ownership
The visible Date added column uses a qualified date, never a receipt, scan, birth,
modification, or use timestamp. Known dates sort first in either direction. Plugin
product identity, canonical name, tags and earliest qualified date live in one
durable product row; formats are physical installations below it. The v4→v5
migration preserves old format evidence and metadata, with a verified backup.
One product retains its ID, tags, date and valid use history after a format is removed.
The format sheet concentrates on paths, sizes, availability and reviewed removal.

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
Date added first reads the filesystem's `addedToDirectoryDateKey`, then Finder's
`kMDItemDateAdded` when the direct source is unavailable. This keeps available dates
on volumes without Spotlight indexing. The date records arrival/rename into the
current directory; it can differ among formats and does not prove installation.
Show the earliest available Finder date ever qualified for the product, tied to its
exact installation when recorded; if unavailable, retain a confirmed addition record
when one exists. Never substitute birth, modification, scan, receipt or use time.
The selected summary shows one date with source explanation in accessibility text.
Unknown dates sort last in either direction. Physically located samples, libraries
and instruments also use their own available Finder Date Added; virtual/shared
entities remain Unknown. First indexed, observed arrival and receipt records remain
separate internal evidence, not inspector prose.
Samples, libraries and instruments retain the earliest qualified date for the same
verified physical/vendor identity across scans and reconnects. A similarly named
replacement cannot inherit it. No file creation/modification fallback is used.
Instruments never inherit their library/player's date. Apple defines the Finder
metadata as the date moved into the current location and notes that it may be
absent: [kMDItemDateAdded](https://developer.apple.com/documentation/coreservices/kmditemdateadded).

Plugin bundles in AU, VST2, VST3, AAX and CLAP use complete, checked metadata-only logical-byte
measurement. A grouped product shows a complete total only when every installation
was measured; otherwise the row says Partial or Unknown and the inspector qualifies
any known subtotal. Saved catalogs retain the last measured value with a saved-state
qualifier. These values do not claim reclaimable physical disk space. Library size is
shown under its source-qualified measurement basis; unsafe or failed measurements say
Size unavailable with a scan issue. Only unique whole installation folders claim a
complete product total. SINE installed content, candidate folders, and unassociated
content disclose their narrower coverage.
Instrument size remains Shared with library.

### Last used with host-qualified clocks
Qualified host use displays the calendar date alone. Accessibility text identifies the host and source clock limits. Never interpret this civil timestamp in the
current Mac timezone. Pro Tools likewise retains its source-local civil day. Cubase
and Logic report absolute instants; show their Gregorian day in this Mac's local
display timezone. Within Cubase or Logic, later instants win same-day ties. Across
host families, retain stable family priority because civil clocks are incomparable.
Plugin Last used sorts these calendar days, unknown last in
both directions; sample Project recency remains explicitly separate. Instrument and
library usage never inherit player use. Usage unknown filters only rows without
qualified positive history; it is not an inactivity or safe-removal filter.
