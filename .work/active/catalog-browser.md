# Native catalog browser and reference validation

Acting client: Codex. Tier 2; domains ui-ux and stateful-feature.

## Outcome and current evidence

User asked to continue from the read-only CLI and supplied a project folder for
read-only testing. Its path is intentionally not stored in versioned documentation.
Existing core has 17 passing tests, real plugin discovery, experimental RPP/ALS
readers, and explicit unknown coverage. No GUI exists.

Deliver a runnable native macOS browser: select scan folders, scan, switch among
Plugins/Samples/Libraries, search/sort, inspect paths and saved-reference evidence.
Validate supplied project-folder coverage and record aggregates only.
Add a bounded experimental Logic metadata reader for Alternatives/000/MetaData.plist:
only AudioFiles and PlaybackFiles arrays become unresolved sample candidates; skip
UnusedAudioFiles and all backup/other alternatives. Coverage explicitly states that
000 is not proven active and metadata inclusion is not confirmed current use. Never
auto-match these candidates. Reject linked metadata paths, oversized/nonregular files,
wrong-type arrays, and missing metadata without hiding failure. Validate against
factory metadata and a bounded sample from the user-authorized root.

## Non-goals

No deletion, background service, persistent catalog/settings, tag editing, exact last-use
claims, plugin execution, project changes, or unsupported parser guesses. UI is a local
preview; folder choices and filters last for the current session only. No account,
network requests, donations link, or implied charity affiliation in this slice.

## UI and interaction contract

- Native AppKit controls, system colors/fonts, standard window at least 960x680.
- Three collection categories, searchable/sortable table, readable selected-item detail.
- Toolbar actions: folder selection by Plugins/Samples/Libraries/Projects, Scan,
  standard plugin folders toggle. Show selected roots and allow removing each root.
- No automatic first-launch scan. Empty state explains Choose folders / Scan.
- One in-flight scan, executed off main thread. Disable folder edits and Scan while
  busy; search/navigation remain available. Preserve old results until replacement.
- Unavailable roots and unsupported/failed project counts remain visible; issues can
  be inspected. A zero-row result is distinct from first launch and search no-match.
- Sample reference date labeled "Project recency" with modification-date caveat in
  detail; plugin/library references show "Not available". No "unused" label.
- Detail includes full selectable path, candidate classification, logical file size
  when known, and matching project paths. Unknown size is not zero.
- Root list and inspection text scroll; long paths do not widen the whole window.
- All actions have visible names and accessibility labels. Keyboard uses native
  controls, table selection, and search focus shortcut. No custom gesture-only actions.
- English first preview. Native appearance supports light/dark, system accessibility
  colors, and reduced transparency. Other OS versions and VoiceOver user validation
  remain explicit limits until exercised.

## State completeness

One native registry declares session-only category, query, sort, standard-plugin
toggle, roots by category, and selection. No persistence/presets/import/export yet;
all exclusions have reasons in feature-registry.json. Default/reset and runtime-ID
coverage tests required. Reopening a new browser session resets defaults by design.
Scan report/loading are derived runtime status, not editable settings.

## Files and boundaries

New SimplifyCatalog library for MainActor model and AppKit controller, executable
SimplifyApp launcher, app-bundle build script, model tests and app runtime smoke.
Core scanner remains read-only. UI uses immutable reports; background completion
returns to MainActor. No user project content or paths in fixtures or screenshots.

## Acceptance and checks

1. Debug/release builds and existing/new fixture tests pass; no regression to core.
2. Model filtering, deterministic sorting, unknown-last recency, selection retention,
   roots add/remove, duplicate suppression, and defaults are tested.
3. Native runtime smoke clicks actual category/scan controls on synthetic folders,
   exercises search and selection, waits for async completion, verifies detail text,
   and captures minimum/typical light/dark layouts plus empty/loading/issues states.
4. Accessibility structural checks verify named buttons/search/table and visible
   state text; screenshot matrix reviewed independently. Do not claim untested
   VoiceOver or cross-OS certification.
5. Provided project root is inspected read-only, bounded, with format/coverage counts
   only saved; unsupported formats remain unsupported.
6. Registry policies and ID/default coverage pass; no hidden serialization paths.

Commands added to toolchain before execution: swift build; swift build -c release;
swift test; python3 scripts/catalog_state_check.py; python3 scripts/build_app.py;
build/Simplify.app/Contents/MacOS/Simplify --ui-smoke captures/catalog.
Native GUI launch requires environment escalation, not bypassing permissions.

## Risks and rollback

Large scans may be slow; no cancellation promise in this preview. Closing window does
not mutate inputs. Files on offline/cloud storage can remain unavailable; no force
download is requested. Package support and source-asset equivalence remain incomplete.
Rollback removes newly added app artifacts; no scanned content is changed.

## Resume

Implementation and native fixture smoke complete; independent review passed.
Final executable gates and launch are in progress. Claude was unavailable earlier; use independent Codex reviews if it
remains unavailable. Shared deterministic gates run directly; native hooks not claimed.

## User steering

Project renamed Simplify, including package/targets/app bundle and directory.
Projector is the explicit UI reference: 16pt title, 13pt panel headings, 12pt body,
8/12pt spacing, rounded 8pt panels, hot-pink primary action, semantic native colors.
User requested launching the runnable preview after verification.
