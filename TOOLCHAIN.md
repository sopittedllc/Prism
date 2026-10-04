# Toolchain

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

Run `.build/debug/simplify-probe --help` for read-only scan options. JSON contains
local paths and should stay private. No arguments performs no scan. SwiftPM uses its
own build sandbox; in Codex this environment requires the approved `swift build` or
`swift test` escalation, not disabling SwiftPM's sandbox.

Build `swift build -c release` before packaging; the user app uses the optimized release executable.
A native AppKit preview is packaged by `python3 scripts/build_app.py` into
`build/Prism.app`. Icon conversion requires the approved packaging escalation
in this environment. Run `build/Prism.app/Contents/MacOS/Prism --ui-smoke captures/catalog`
for synthetic native interaction/capture tests (GUI escalation required).
`python3 scripts/catalog_state_check.py` checks the native state registry and setup persistence IDs.
There is no distribution signing, sample/library deletion, or background service yet. Accepted folder setup and final inventory catalog are stored locally; filters remain session-only. The catalog restores asynchronously and marks retained unobserved entries stale. Full DAW compatibility and host-generated REAPER fixture checks remain unverified.
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
