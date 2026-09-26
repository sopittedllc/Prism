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
`build/Simplify.app`. Icon conversion requires the approved packaging escalation
in this environment. Run `build/Simplify.app/Contents/MacOS/Simplify --ui-smoke captures/catalog`
for synthetic native interaction/capture tests (GUI escalation required).
`python3 scripts/catalog_state_check.py` checks the native state registry and setup persistence IDs.
There is no distribution signing, sample/library deletion, or background service yet. Accepted folder setup and final inventory catalog are stored locally; filters remain session-only. The catalog restores asynchronously and marks retained unobserved entries stale. Full DAW compatibility and host-generated REAPER fixture checks remain unverified.
The runtime probe is machine-specific and excluded from generic CI. CI requires macOS.

Native smoke moves only generated dummy plugin bundles to macOS Trash; it never removes installed user plugins. Core removal validation tests inject failures without mutating real audio.
