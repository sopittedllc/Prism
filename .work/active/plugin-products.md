# Plugin products, format removal, and multiple sound locations
Acting client Codex; tier2 user-facing file operation feature. User authorizes implementation, not removal of their real content during development. Prior read-only preview restriction is superseded for explicit in-app plugin removal only.

## Outcome / scope
One row per plugin product, with all discovered formats and individual installation paths in details. Select installations to keep/remove, or explicitly choose all discovered installations. Review exact paths, then move only selected plugin bundles to macOS Trash. Never permanent deletion, parent folder removal, shared presets/licenses/library cleanup, or privileged helper. Permission failures remain visible and failed items stay listed. No real user files removed in tests.
Samples and Libraries already store arrays and picker supports multiple selection. Make Add folders wording and unlimited repeated additions explicit; show chosen folder count; support separate Kontakt/SINE roots. No artificial folder count limit; existing bounded settings-file and scan-entry limits remain documented.

## Identity / boundaries
Core PluginProduct groups normalized exact names (case/whitespace and explicit format suffix only; preserve versions) plus compatible complete bundle identifiers. Only delimiter-separated terminal format tokens are removed. Conflicting IDs split; unknown identifiers stay separate by path. Grouping is a presentation heuristic, never an ownership claim. No fuzzy name matching. Raw scan reports remain installation-level; catalog maps representative paths to product groups and searches every member. Show all original names/paths in format sheet.
Core scanned plugin assets carry optional lstat device/inode/mtime/ctime identity. Removal service validates directory/plugin suffix, scanned identity, non-symlink ancestors and unchanged identity immediately before Trash; reject missing/changed/linked targets and overlapping paths. No recursive discovery during removal. Worker returns per-item success/error; model removes only successful paths, preserves failed entries/references/issues, reindexes and retains surviving product selection. Prevent scan/config/removal overlap. Unknown references are disclosed in confirmation; exact paths scrollable. Keep choices default; all-format action explicit and confirmed. Synthetic runtime checks actual macOS Trash and ensures unselected fixture remains; never real audio.

## State / risks
New product grouping indexes and removal operation/selection are derived ephemeral state; discarded on close/reset, no serializer schema change. Presets/project persistence/migration/automation/copy-paste/sync/export: excluded, operation scoped. Undo uses Finder Trash restoration rather than fabricated in-app undo; errors explained. Accessibility native labeled checkbox/buttons; privacy local paths only, no telemetry. Existing roots registry persists all selected folders. Risks: publisher heuristics may leave unusual names separate; no universal product ID; shared-container plugin remains one indivisible bundle. Race between final validation and OS path-based Trash cannot be eliminated; no adversarial atomic-removal claim.

## Steps
Research macOS Trash/confirmation and existing multi-root semantics; critic; implement core grouping and removal boundary; wire model/format sheet/details and folder affordances; regression, release package/native synthetic test; independent source/visual/state review; close gates.

## Acceptance
AC1 Multiple formats of same-name/same-publisher plugin show one row, formats in details, search any member, collision/version tests.
AC2 Chosen installations or entire discovered product require exact-path review; successful Trash removes only requested fixtures; keep/cancel, changed/symlink/missing/unsupported targets and partial failures tested. Scan/removal overlap rejected, failed rows retained.
AC3 Multiple sample/library roots can be added repeatedly, persisted/reopened, scanned without loss; Kontakt and SINE examples explicit.
AC4 Native light/dark/compact format controls, long paths, checkbox and keyboard naming, result/error views; 740pt bounds.
AC5 swift test; swift build -c release; python3 scripts/build_app.py; build/Simplify.app/Contents/MacOS/Simplify --ui-smoke captures/catalog; configured CLI/template/adapter/state checks; independent review.

## Resume
Only root writes product. Independent Codex critic/review when alternate client unavailable; disclose provenance. No publication, install, or real content deletion. All fixture paths generated inside private test directories; no user project archives scanned for this task.

## User steering: empty collections and plugin references
Read-only saved-root check: sample root is inside broader library root; current suppression discards it. Library-only scan returns15 candidates/no issues, so no evidence library path unreadable. Fix root precedence: explicit more-specific sample roots override broad library roots; nested explicit library roots still exclude their interiors. Library candidates explicitly configured as sample roots excluded. Add regressions and per-category empty diagnostics (saved but no current scan vs scanned empty/issues).
Plugin reference matching currently absent by design. Add conservative candidate associations from existing REAPER explicit plugin declarations (normalized exact product display name, optional format prefix and maker suffix); only unambiguous single product matches. Label candidate evidence and project modification proxy, never verified installation dependency or safe-delete. Other DAW plugin states remain unsupported visibly; do not pretend usage history is known. Review update before final completion.

## Review repairs and verification
Independent review required preserving complete identifier namespace (hosted domains
can have distinct vendors) and suffix-token boundaries (tableau is not table.au).
Reviewed Asset identities now reach the worker unchanged; a rescan cannot substitute
a new file behind the reviewed path. Synthetic native tests passed keep/cancel,
selected Trash preserving other format, and all-remaining Trash removing product row.
Saved real roots read-only check found14 libraries and75,446 samples before entry
limit; no paths/content exported. Per-category budgets prevent samples starving
project discovery. Scope remains bounded and partial scans explicitly labeled.
