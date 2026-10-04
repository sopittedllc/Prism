# Compact setup and tag pills — Codex

User outcome: halve setup size and copy across all four steps; default standard plugin
folders on; category-colored Logic-inspired tag pills, hover removal and trailing +.
Non-goals: usage/installation adapters, scan/removal behavior, metadata provider expansion.
Parent cleanup-essentials remains open; no release or real-audio removal.

Evidence: SetupWindow is 740x602 with long copy and logos; inspector has plain tag text
and a separate field editor. Metadata overrides already support explicit empty categories,
validation, durable saves and Undo. New writes must preserve suggestion suppression.

Design: setup540x420 (51% area), Plugins/Sounds/Projects/Ready, one sentence each, compact
bounded folder lists with name/parent labels and full tooltip. Preserve saved preferences,
Cancel draft semantics, all root kinds, save errors and session-only recovery on failure.
Tags wrap in a bounded scroll area, stable category hues in theme, text labels/tooltips
and keyboard-accessible delete buttons shown on hover/focus. + opens category/value/Add
and Cancel; Return saves, Escape cancels. Empty/duplicate/invalid values stay editable.
Existing advanced editor remains available via tag settings for restoring suggestions.
Product pills represent union by category and normalized value; edits affect all current
installed formats as one atomic operation and one Undo, changing only that tag/category
while preserving unrelated installation overrides. Explicitly disclose all-formats scope
in tooltips/add dialog. Single assets/instruments retain their exact metadata subject.
Failed writes preserve pills/draft; busy controls disabled; captured targets avoid races.

State: existing metadata override schema unchanged. Batch undo is session-only, resets
with model. Add draft/popover/error are transient; cancelled or dismissed drafts do not
persist, no presets/automation/sync/export/telemetry. Existing registry metadata policies
apply; category colors are static presentation tokens. No new persistent preference.

Steps: independent UX/spec critique; setup copy/layout; shared pill and entry components;
atomic metadata mutation/undo; inspector integration; tests and native screenshots;
independent code/visual review; rebuild/reopen isolated demo.
Affected: SetupWindow, CatalogTheme, new TagPills, CatalogWindow, CatalogModel,
CatalogStore batch override writer, catalog/core tests, native smoke, design/state docs.
Risks: cramped footer, lost installation-specific values, stale-node mutation, suggestion
reappearance, failed-write draft loss, hidden keyboard actions, low color contrast.
Acceptance: setup <=540x420 with all four footers usable and default checked; tag category
colors consistent; add/delete/Undo persists through restart; batch rollback is atomic;
hover and keyboard delete accessible; + wraps last; long lists scroll; light/dark pass.

Research (official comparables): Logic color palette for visual categorization; Finder
colored tags with text/keyboard routes; Reminders add/remove named tags. Colors here are
Logic-inspired, not claimed as immutable official hex constants.
https://support.apple.com/en-ie/guide/logicpro/lgcp7a5a5423/10.7/mac/11.0
https://support.apple.com/en-kw/guide/mac-help/mchlp15236/mac
https://support.apple.com/en-nz/guide/iphone/iph474a6685c/ios

Verification: python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package
Native: python3 scripts/run_check.py --task cleanup-essentials --gate runtime_tests catalog-runtime
Native hooks unavailable; deterministic gates required. Cross-client CLI unavailable;
independent Codex critic/reviewer fallback. Check-complete parent remains honestly pending.
Specification: independent Codex simplify_spec PASS, including atomic all-format tag edits.
Resume: implementation present; verification and independent source/visual review in progress.
