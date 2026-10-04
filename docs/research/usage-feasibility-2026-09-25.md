# Four-host usage feasibility checkpoint

2026-09-25. Acting client: Codex; independent read-only researcher:
`usage_feasibility`. This is research evidence, not a passed host-support gate.

## Decision

Reliable last-used is the user's highest priority. Validate host signals before
implementing a timestamp that could falsely suggest content is unused. Inclusion
without playback counts. Distinguish saved inclusion, confirmed load, attempts,
binary mappings and project modification dates.

## Read-only local observations

All four hosts are installed: Logic Pro 12.3, Ableton Live 12.4.5 Standard,
Cubase 15.0.30 and Pro Tools 24.10.2. No host was launched, logging enabled or
user session modified for this research. Only aggregate findings are retained.

| Host | Available route | Observed evidence and next proof |
| --- | --- | --- |
| Pro Tools | Per-launch plaintext logs | Five files, 41 InstantiatePlugIn token occurrences, 22 host/track-shaped events and four kCantInstantiatePlugIn failures. Tokens are not confirmed successes. Correlate completion, session clock and stable plugin identity in controlled fixtures. Exclude mixer events. |
| Live | Saved ALS state; device-tree observation; diagnostic logs | Seven logs contain 122 restore attempts and 122 restore failures. No successful usage inferred. Establish exact installed identity from saved/device state and distinguish failed restoration. Standard installation does not establish availability of a Max-based observer. |
| Cubase | Optional usage logs | Usage-log directory absent. Generate controlled logs before claiming supported grammar, identity or timestamps. |
| Logic | Active saved-project state and prospective host observation | No validated historical usage adapter. Read-only lsof succeeded for two related processes but found no third-party bundle mappings. No controlled positive load was performed, so this proves neither support nor absence of use. |

The earlier Live aggregate of 95 attempts is superseded by this observation.
Neither count is an immutable fixture. Private tracks, project names, plugin names
and source log contents are not included in this report.

The coordinator additionally checked `AXIsProcessTrusted()` from this execution
session: **false**. Automated host interaction is not currently available through
macOS Accessibility. This is a concrete runtime-test dependency, not a reason to
mark synthetic fixtures as host validation.

## Candidate architecture and admission

Use separate host adapters and a durable local evidence ledger recording asset
identity, host/version, source/version, evidence kind, outcome, timestamp meaning,
session identity and coverage. Admit each host/asset/evidence combination only
after the [validation matrix](usage-validation-matrix.md) passes.

Process mappings obtained through libproc can correlate an exact installed bundle
with a process lifetime. They cannot independently establish instantiation or
project inclusion: validation, resident binaries after removal and separate AU
hosting processes confound that inference. Do not refresh last-used merely because
a binary remains mapped. FSEvents concerns filesystem changes, not use. Endpoint
Security requires an Apple-granted entitlement and is not an assumed dependency.

Player identity does not identify a Kontakt/SINE patch. Validate one patch versus
a sibling and copied samples versus originals independently. Preserve coverage
gaps when logs rotate, tracking stops, permissions fail or source schemas change.

Logic's third-party lpx-toolkit is a research lead for saved-project AU identity,
not a supported historical usage API. Its author documents an undocumented binary
format, testing against Logic 12.2 only and phantom references from undo history.
The local host is 12.3. No third-party code was imported or executed.

## Primary sources

- [Avid launch-log documentation](https://kb.avid.com/pkb/articles/Troubleshooting/Exporting-Log-files-from-a-Pro-Tools-System): per-launch plaintext logs.
- [Ableton crash-report documentation](https://help.ableton.com/hc/en-us/articles/5301568366354-Reading-Ableton-Live-Crash-Reports): restore attempts can precede failure.
- [Steinberg Usage Logging](https://helpcenter.steinberg.de/hc/en-us/articles/32371744743826-Usage-Logging): disabled by default; includes plugin and timing information when enabled.
- [Live Device API](https://docs.cycling74.com/apiref/lom/device/) and [Track API](https://docs.cycling74.com/apiref/lom/track/): device-tree research, not proof of installed identity or player-patch coverage.
- [Apple libproc source](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c).
- [Apple out-of-process AU guidance](https://developer.apple.com/documentation/audiotoolbox/debugging-out-of-process-audio-units-on-apple-silicon).
- [Apple FSEvents](https://developer.apple.com/documentation/coreservices/file_system_events).
- [Endpoint Security entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.developer.endpoint-security.client).
- [lpx-toolkit author documentation](https://github.com/rhydlewis/lpx-toolkit): saved Logic AU manifests, version limits and phantom-reference caveats.

## Next experiment

Use an isolated blank session in each host, a synthetic loose WAV and an installed
plugin. Compare add-without-playback, save/reopen, removal, bypass/mute, failed
restore and validation-only. Capture private raw evidence locally and commit only
redacted fixture shapes. Then repeat with distinct player instruments when their
content is available. Disconnected sample drives remain a separate dependency for
representative library tests. No adapter is admitted yet; all usage gates remain
pending. Size and removal work remain in scope after usage proof.
