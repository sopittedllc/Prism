# Toolchain

Project-scan memory checks use synthetic files only. Run the configured
`project-buffer-memory-runtime`, `ableton-preflight-memory-runtime`, and
`ableton-batch-memory-runtime` checks with `scripts/run_check.py`. Each starts a
separate test process with `PRISM_PROJECT_MEMORY_RUNTIME=1`, so prior tests cannot
mask memory growth through the process high-water mark. Fixtures use at most
192 MiB of disk and are deleted afterward; no user projects are scanned.
The peak-growth limits are 96 MiB for malformed CPR files, 32 MiB for
one 4 MiB ALS document, and 64 MiB for 24 valid ALS documents. Generic tests do
not enable these memory measurements.

`large-inclusion-runtime` creates a synthetic report whose original per-sample
reference evidence exceeds the 32 MiB SQLite cell bound. It verifies exact
referenced and no-reference rows through durable save/restore and cancelled retry,
while keeping the existing SQLite bounds. The fixture contains no user audio files.

`decoded-fact-cache` runs focused synthetic cache and reader tests. The separate
`scan-responsiveness-runtime` check creates 99,000 empty sample files in an
isolated disposable catalog and prepares a 100,000-path hierarchy. It measures
main-actor heartbeat during durable scan, saved-catalog restore, and projection;
run the runtime check alone
so other test processes do not distort the 250 ms threshold.

Native Swift package, no third-party downloads. Verified on Apple Silicon with
Swift 6.3.3 / Xcode 26.6. Package deployment floor is macOS 13; that older OS and Intel
have not been runtime-tested. `.workflow/toolchain.json` contains executable argv.

| Check | Command |
| --- | --- |
| Debug build | `swift build` |
| Release build | `swift build -c release` |
| Core fixture tests | `swift test` |
| CLI integration | `python3 scripts/probe_smoke.py` (debug build first) |
| Local runtime probe | `python3 scripts/probe_runtime.py` (installed plugins and factory Ableton demo only) |
| Template controls | `python3 scripts/template_self_test.py` |
| Adapter consistency | `python3 scripts/sync_agent_adapters.py --check` |
| Offline tag catalog | `python3 scripts/validate_product_tag_catalog.py` |

Run `.build/debug/simplify-probe --help` for read-only scan options. JSON contains
local paths and should stay private. No arguments performs no scan. SwiftPM uses its
own build sandbox; in Codex this environment requires the approved `swift build` or
`swift test` escalation, not disabling SwiftPM's sandbox.

Build `swift build -c release` before packaging; the user app uses the optimized release executable.
A native AppKit preview is packaged by `python3 scripts/build_app.py` into
`build/Prism.app`. Icon conversion requires the approved packaging escalation
in this environment. Run `build/Prism.app/Contents/MacOS/Prism --ui-smoke captures/catalog`
for synthetic native interaction/capture tests (GUI escalation required).
For a beta without touching the existing packaged preview, run configured
`beta-clean-build` in a separate ignored SwiftPM scratch path, then
`beta-package-rebuild`, `beta-package-local`, `beta-dmg-local` and
`beta-runtime-local`. These create an ad-hoc signed app and unnotarized DMG under
ignored `release-build/` and use isolated synthetic runtime fixtures. They do not
use credentials, upload, install, or publish. The release owner follows
`docs/release/PRISM_BETA.md` to produce and validate the separately Developer ID
signed, notarized, stapled final artifact.
`python3 scripts/catalog_state_check.py` checks the native state registry and setup persistence IDs.
The ordinary preview is ad-hoc signed; Developer ID distribution is a separate release-owner workflow. There is no sample/library deletion or background service. Accepted folder setup and final inventory catalog are stored locally; filters remain session-only. The catalog restores asynchronously and marks retained unobserved entries stale. Full DAW compatibility and host-generated REAPER fixture checks remain unverified.
The runtime probe is machine-specific and excluded from generic CI. CI requires macOS.
Set `PRISM_ABLETON_FACTORY_DEMOS` to override its optional Ableton demo location;
an invalid explicit directory fails rather than silently dropping project coverage.

For an offline demonstration without installed plugins, DAWs or the Samples drive,
run `python3 scripts/create_offline_demo.py` after cloning. It creates a small
synthetic catalog under ignored `build/offline-demo/` and prints the four roots to
add in Prism Setup. Run the CLI against those roots for an isolated inventory;
the app also includes standard system plugin roots automatically. Package and
open the app to inspect the synthetic folders alongside any standard plugins;
the fixture contains no playable audio, licensed library content or real usage
events. The path-free Samples-drive scale aggregate is
`tests/fixtures/samples-drive-aggregate.json` and is separate from this small demo.

Native smoke moves only generated dummy plugin bundles to macOS Trash; it never removes installed user plugins. Core removal validation tests inject failures without mutating real audio.

`product-tag-sources` runs `.build/debug/simplify-probe --check-product-tags` to validate reviewed official product endpoints. It requires network access, reads no local inventory, and is separate from deterministic CI fixtures.

`receipt-binding-runtime` runs `env PRISM_RECEIPT_BINDING_RUNTIME=1 swift test --filter nativeReceiptBindingRuntime`. This opt-in macOS check reads existing FabFilter Pro-Q 4, Kontakt 8 and Diva AU bundles and public package receipts. It binds/replays evidence only in a disposable synthetic catalog; installed bundles and the user catalog are unchanged. Not part of generic CI.

`automatic-receipt-runtime` runs `env PRISM_AUTOMATIC_RECEIPT_RUNTIME=1 swift test --filter nativeAutomaticReceiptRuntime`. It enumerates public receipt metadata and automatically resolves the three existing AU controls into a disposable catalog, twice, with command/timing measurements. No installed bundle or user catalog writes. Separate from generic CI. The filter also runs the native CatalogModel scan-to-evidence test against those three bundles with isolated catalog storage.

`live-usage-runtime` runs `env PRISM_LIVE_USAGE_RUNTIME=1 swift test --filter nativeLiveCompletedRestoreRuntime`.
This opt-in local check parses completed and crashed Live controls, reads the existing
Live cache and three installed VST3 controls, and binds/replays product-class history
only in a disposable catalog. It does not launch a host or modify installed plugins.

`protools-restore-v2-runtime` runs `env PRISM_PROTOOLS_RESTORE_V2_RUNTIME=1 swift test --filter nativeProToolsRestoreV2Runtime`.
This opt-in check parses the private captured full-header restore and before/after
insert/remove snapshots, binds the three restore products by unique exact names to
currently installed AAX assets, and verifies persistence/replay plus local-date
presentation in an isolated catalog. It does not read or write the user catalog, launch
Pro Tools, or admit manual-insert use. It is separate from generic CI and parent
four-host completion gates.
It requires the private capture and matching installed AAX controls, but does
not launch Pro Tools; `PRISM_PROTOOLS_RESTORE_FIXTURE_DIR` may point to a copied private
capture directory. Generic `swift test` does not enable this check.

`cubase-native-restore-runtime` runs `env PRISM_CUBASE_NATIVE_RESTORE_RUNTIME=1 swift test --filter nativeCubaseRestoreRuntime`.
This opt-in check reads private before/after saved-reopen captures and the current
Cubase VST3 cache. It requires an exact one-class Glow binding and leaves the user
catalog, installed plugins, and Cubase untouched. Generic tests skip the private
check when the environment variable is absent.

`PRISM_KONTAKT_TABLE_RUNTIME=1` enables separate private Kontakt state/table
controls. The Accordion manifest-binding check additionally requires
`PRISM_KONTAKT_MANIFEST_PATH` set to a local `Accordion.nicnt`; without it the
opt-in test records an explicit failure. Generic tests do not require the drive.
The separate opt-in `PRISM_SAVED_PROJECT_RUNTIME=1` controls require
`PRISM_SINE_CONTROL_PROJECTS` to point to a local directory containing
`sinetest.cpr` and `sinetest-empty.cpr`; no user-specific path is committed.
