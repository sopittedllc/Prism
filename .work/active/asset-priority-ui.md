# Asset priority UI

Status: specification PASS by independent Codex critic; implementation under verification. Driver Codex; risk 2; UI/UX and stateful-feature. User explicitly requests this UI work while real usage proof remains the cleanup release gate. This slice does not implement DAW tracking or installation-date collection.

## Outcome
Plugins and libraries lead with meaningful metadata and lifecycle facts, not paths. Interpret pending ambiguous “pulls” as dropdown filters after allowing response time. Existing tag field/value dropdowns gain a visible Tags label and their own row. List name subtitles show deduplicated effective tags (suggested/edited provenance remains in inspector). Main inspector shows tags, installed formats/player, size, Last used and Installed. Known catalog observation remains separately labeled First found/indexed, never installed. Missing tags invite editing.

## Implementation
- CatalogWindow: keep native tag dropdowns, add separate Last used dropdown row with Recently found. All usage / Usage unknown are enabled; Used in last 30 days / Last used over 90 days ago visible but disabled until admitted evidence exists. Explain unavailable tracking beside controls. No “never used” option. Same semantics for plugins and libraries; hide usage control for samples where project recency remains separate.
- Model: session-only usage_filter enum all/unknown; both return all currently unknown plugin/library assets. Combine with text/tags/recent using AND, category switch and Clear filters reset it. Include in navigationQuery, snapshot, registry/default reset; no preset/persistence/undo/automation/sync/export/analytics. Accessible local-only browser control. No invented dates.
- Main inspector removes paths and raw project evidence, displays Last used: Unknown and Installed: Unknown for plugins/libraries. Existing first-found text retained with observation caveat. Deduplicate row tags; inspector installation labels use formats, not paths. Add Details… sheet for original paths, exact installation labels and available reference/identification evidence. Selected item only, read-only, Close returns focus. Finder/removal behavior unchanged.
- Format column becomes visible for plugins using product formats. Avoid additional date columns at compact widths: lifecycle dates consistently visible in inspector; size shown there (Not measured where unsupported). No scope expansion to storage measurement/removal changes.
- Files: CatalogModel/Window, feature-registry, state completeness/UI docs, CatalogTests/native smoke. Refresh isolated demo against updated release modules.

## Acceptance
1. Plugin/library default inspector has tag values or explicit empty state, Last used and Installed labels; contains no absolute installation paths. Details retains paths. First found cannot render as Installed.
2. Row subtitle includes effective tags for plugin/library/instrument and does not use paths. Existing metadata editing and single-installation selection unchanged.
3. Last used control exists for plugins/libraries, restores selection after refresh, combines with existing filters, clear/category reset, unavailable date ranges disabled with explanation; unknown is not age evidence.
4. Native state registry and documented policies agree. Existing 77 tests plus behavior tests and native compact/light/dark captures pass. Review captures for clipping at 1040 and default width.
5. Build/test/package/native runtime commands from .workflow/toolchain.json via run_check where feasible. Independent read-only source/UX review. No real DAW coverage claim; parent cleanup task remains pending.

## Risks/recovery
Do not hide dates behind disclosure or equate observation with installation. No background metadata web requests without clarification. One selected plugin can represent several installs; deduplicated subtitle is discovery only, edits remain installation-specific. No database schema changes. Revert only this slice if checks fail; preserve existing user and v1 changes.

## Verification
swift build; swift test; python3 scripts/catalog_state_check.py; python3 scripts/probe_smoke.py; python3 scripts/template_self_test.py; python3 scripts/sync_agent_adapters.py --check; swift build -c release; python3 scripts/build_app.py; build/Simplify.app/Contents/MacOS/Simplify --ui-smoke captures/catalog. Native enforcement unavailable: deterministic scripts are authoritative. Cross-client review unavailable in this session (Claude CLI not logged in); independent Codex fallback required.
