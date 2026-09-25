# Collection redesign and useful onboarding

Acting client Codex; tier 2; ui-ux and stateful-feature. User explicitly requests substantial UI improvement, research, useful setup, and visible supplied icon.

## Outcome / scope
Replace crowded vertical controls with branded sidebar (Plugins, Samples, Libraries), large collection list, contextual right inspector and restrained status. Use Projector typography/spacing/accent; supplied icon on a neutral white tile for visibility. Explicit applicationIconImage plus verified ICNS. Keep native AppKit controls and keyboard interaction.

On first launch show optional four-stage interactive setup: Welcome + standard plugin choice; Samples/Libraries folder pickers with Splice/Kontakt/player examples; optional Projects with honest coverage; Review and Scan. Back/skip/reopen supported; no scan until explicit action. Use draft configuration so dismissing never changes active roots. Remember accepted roots, standard plugin toggle and onboarding completion locally. New sessions reset filters/selection/results. No background scanning is implied. Settings failure is visible; allow session-only setup without overwriting unreadable/future-version settings.

## Evidence / system inventory
Current CatalogWindow stacks title, subtitle, actions, categories, filters, status, count, table, bottom raw inspector. Design-system JSON empty. All three collections, empty/no-match/loading/issue states, folder setup, selection inspector and application brand affected. Core read-only scanner unchanged. Research in .workflow/evidence/onboarding-redesign/ui-research-report.json; official Apple guidance and Finder, XO, DaisyDisk workflows.

## Boundaries and non-goals
Catalog remains read-only. No trash, tags, telemetry/web lookup, exact last-used promise, DAW checklist or recurring scanning. Root config stored in private local Application Support, never sent out. App icon artwork unchanged; native image layout only. Current scan remains bounded and uncancellable; busy status is honest.

## State contract
Native registry adds onboarding_completed; roots, standard_plugins, onboarding_completed participate in local setup persistence version 1. All other fields remain session-only. Encode only registry-selected fields and verify exact IDs. Missing fields use registry defaults; unknown fields ignored; wrong types/invalid root kind/relative path/corrupt JSON/future version rejected without overwriting source. Atomic save; no prior persisted release requires migration; version rejection tested. Setup stage/draft are transient controller lifecycle, discarded on close, no independent saved settings. Presets/undo/automation/sync/analytics/export excluded with explicit reasons. No credentials or network.

## Steps
1. Research comparable workflows and inspect Projector; critic review.
2. Implement shared theme/brand, three pane layout, inspector/empty state, setup draft and versioned store.
3. Add meaningful persistence/recovery/roundtrip tests and native setup/scan/navigation/screenshot tests. Keep smoke isolated from real settings.
4. Build/package/test; independent source and visual review; open running app after verification.

## Acceptance
AC1: debug/release, core/model/integration/state checks pass.
AC2: supplied icon appears in brand and running app; consistent light/dark typical/minimum layouts.
AC3: setup back/skip/reopen and accepted roots work; only explicit finish scans; cancel leaves active configuration intact.
AC4: accepted settings restore with filters/results reset; malformed/future settings preserved; disk errors actionable and session-only recovery.
AC5: native keyboard/search/category/selection and async scan states pass; unknown reference evidence explicit.
AC6: current source independent review and screenshot review; all cross-cutting policies covered.

## Verification
Exact toolchain checks: build-debug, build-release, unit-tests, integration-tests, template-integrity, adapter-integrity, catalog-state, app-package, catalog-runtime. Dock validation: capture actual Dock region with running packaged app; inspect supplied artwork there, not only NSApp icon property or ICNS. Native smoke uses synthetic 3000 samples, persisted settings isolated, screenshots light/dark minimum/typical plus setup pages, empty/loading/no-match/plugin/library. Capture changed composition as intentional new baseline; no blind pixel baseline acceptance. VoiceOver human, Intel and older macOS validation remain untested and reported.

## Risks / rollback
Persisted folder paths are private user data, local only. No installed audio modified. Removing project code and local bundle rolls UI back, existing settings remain. No scan totals called reclaimable space. Long paths truncate visually with full selectable detail and native tooltips.
