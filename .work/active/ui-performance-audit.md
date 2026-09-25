# UI audit remediation and fast first inventory
Acting client Codex, tier2, UI and performance. User requests full UI audit, fastest reasonable scan, and no foreground scan wait beyond one minute.

## Audit evidence
Read-only UX/visual, accessibility and scan reviews complete in .workflow/evidence/ui-performance-audit. Table cells/sidebar lack shared inset/centering; setup root lists unflipped; inspector style leaks on no selection; root edit focus forced forward; long text untested. Scanning withholds all assets until project parsing/matching; model repeatedly sorts full arrays and linearly searches reference state. Existing local 10k sample baseline <1sec does not reproduce slow external drives. Same-machine before/after benchmark stored separately in captures/performance-audit.

## Scope
Fix governing UI components: padded centered reusable table cells, inset native sidebar button draw rect, top-aligned folder list, bounded inspector heading with full tooltip/selectable path, explicit empty inspector style, root edit focus continuity. Shared spacing tokens and geometry assertions; exercise setup long/error and minimum/light/dark states. Determinate progress fill must match numeric value; replace native animated fill if necessary with static accessible rendering.

Scanner stays read-only and bounded. Create basic assets immediately during library/plugin/sample discovery using cached resource properties. Stream throttled immutable inventory snapshots at <=1Hz, first item immediately and asset-stage boundary forced; traverse project roots only after basic inventory boundary. Existing optional progress callback and CLI final reports retained. Heavy plugin plist and project reading/matching continue in same utility worker. No always-on service or silent scans. Pending reference copy explicit until final analysis. UI uses dictionary indexes and cached filtered/sorted rows to avoid repeated sorts. Source property prefetch and prefix-before-context parser improvement allowed if existing invariants pass. Package optimized release executable for user's prototype (debug remains tests).

Foreground budget: first basic snapshot makes browser useful immediately; after10sec independently show browser/background status even if discovery I/O stalls. Do not falsely claim complete inventory, do not pre-count tree or drop valid files for timing. One scan active; progressive assets replace old report only as new generation arrives; stale callbacks rejected. Config locked until worker ends; cancellation and persisted catalog caches remain out of scope. No universal hard60sec guarantee on stalled external/network/filesystem calls. Benchmark objective is first-inventory under60sec on representative local synthetic fixture and installed-plugin roots; quantify results and limits.

## State / privacy
New inventory readiness/background flags, indexes and presentation timer are derived per-scan state; no new persisted settings or serializer IDs. Reset/new generation clears derived caches and pending flags. No external telemetry or source paths in saved benchmark summaries. Original alpha logo remains untouched.

## Acceptance
AC1 shared text insets and alignment verified geometrically and in native min/typical light/dark scans/setup/detail/no-match/error states.
AC2 keyboard focus remains useful after adding/removing folders; native/explicit accessibility labels retained; no VoiceOver human claim.
AC3 basics delivered before project analysis, partial results browseable, reference state pending, stale snapshots rejected; progress and final issue semantics retained.
AC4 same fixture before/after time to first inventory, total time and counts reported; no unsafe file reads or false speed claim. First local inventory <60sec.
AC5 core/model tests, integration, state contract, release/debug build, package/native smoke, independent review pass.

## Sequence and checks
Critic after audits; implement; profile synthetic and standard plugin roots with bounded CLI metrics (no full real archive pass); swift build, swift build -c release, swift test; configured integration/state/template checks; native smoke with long-project fixture, selection/search during background analysis and geometry checks; independent review. Native template self-test must run after screenshot work, not concurrently (it copies transient capture files).

## Limits / rollback
No data removal; no unsupported DAW parsing added. Scan snapshots add bounded memory <= existing100k entry cap. No persistent cache invalidation problem introduced. Roll back new callback/model/UI changes without modifying user's content or existing saved setup. Broader DAW compatibility and native VoiceOver testing remain separate.

## Implementation / measured evidence
Basic inventory streams before projects; cached model indexes remove repeated sorts
and row lookups. Release same-fixture three-run median core duration fell1.057s to
0.741s (~30%); first item0.082s, all basics0.161s. Local installed plugins:3065
installations, basics0.127s, final0.532s with2 retained issues. Local warm-disk
measurements are not a stalled external-drive deadline.

Native validation caught and repaired a card width constraint activated before
views shared an ancestor; ObjC exception unwinding initially obscured the cause.
Long folder paths also expanded the sheet: constrain setup width740pt, allow path
compression, preserve Remove size. Test now asserts sheet width and table text
alignment rectangles. Runtime captures include save failure and long folder rows.
Screenshot child processes wait off-main; native actions are dispatched through
NSApplication. The delegate lifetime is explicit across application.run().

Independent reviews use Codex roles because alternate client is unavailable;
this is independent review, not cross-client corroboration. No VoiceOver human
certification, cancellation, recurring monitor, or all-DAW support is claimed.
