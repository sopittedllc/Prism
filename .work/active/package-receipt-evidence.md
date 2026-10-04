# Plan: bounded macOS installer-record source

**Status:** IMPLEMENTED — source review passed; final checks recorded separately
**Owner:** Codex coordinator/implementer
**Last updated:** 2026-09-26
**Task ID:** cleanup-essentials
**Risk tier:** 1 (read-only diagnostic source; no automatic catalog admission)

## Outcome / non-goals
Acquire a truthful installer record for an explicitly selected package and plugin
bundle. This is the first concrete input source for date evidence, not a claim of
original Date added or Last used. No full-package enumeration, background service,
receipt modifications, UI change or automatic catalog write. Catalog attachment still
requires matching a freshly verified physical installation identity and retaining
source provenance; no path-only attachment to replacement nodes.

## Research / evidence
Local primary man pages pkgutil and pkgbuild: use public pkgutil queries rather than
receipt storage paths; package versions/IDs are independent of bundle versions/IDs.
Version-checked skips, update-only bundles, scripts and relocation prevent a receipt
from proving when current bytes were installed. --export-plist adds no per-bundle
version in the controlled receipts. Current FabFilter/Kontakt AU package versions
match their bundle versions exactly; Diva does not. Legacy similarly named receipts
can coexist, so never match by product name or guessed package ID.
Read-only researcher usage_feasibility verified these findings. Official entry point:
https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution

## Interfaces and behavior
New PackageReceiptReader.swift and BoundedCommand.swift in SimplifyCore;
PackageReceiptTests.swift; explicit CLI --inspect-plugin-receipt PACKAGE_ID BUNDLE;
CLI smoke tests and this/parent plans. Existing catalog schema/API unchanged.

Public reader acquires --pkg-info-plist ID, --files ID, then --pkg-info-plist ID again
from fixed /usr/sbin/pkgutil, with argv (no shell). Both info results must decode to
identical relevant receipt fields; changes reject acquisition. Package ID is nonblank,
<=1,024 UTF-8 bytes, no controls/leading hyphen; never enable regexp. Receipt info <=
256 KiB, file list <=4 MiB, <=100,000 lines, each <=4,096 bytes, strict UTF-8/control
validation. Package output must match requested ID. Date is a finite, positive integral
Unix timestamp <= explicit observation date. Required volume '/', installation location,
package version and supported receipt-plist-version 1. Unknown volumes reject without
traversing them. Relative payload paths reject absolute paths, empty/interior empty,
dot/dot-dot components, backslashes and controls. Allow one trailing LF in file output.
Installation location may be root/empty or slash-delimited path beneath '/' with optional
leading/trailing slash; same traversal restrictions. No normalization-based name match.

Bundle must be a real directory with .component/.vst/.vst3/.aaxplugin/.clap extension,
safe ancestors (no symlinks) and a bounded direct Contents/Info.plist. Require nonblank
CFBundleIdentifier, simple CFBundleExecutable filename, and at least one nonblank
CFBundleVersion/CFBundleShortVersionString. Executable must be a real regular file in
Contents/MacOS with safe ancestors. Capture bundle/info/executable lstat metadata before
and after acquisition; changed inode/device/birth/mtime/size rejects. This narrows races
but is not a content hash or protection against hostile concurrent filesystem mutation.

Report statuses: associated (exact Info.plist AND executable receipt path membership,
package version byte-exact equals at least one declared bundle version),
notListed, versionMismatch. Report retains package ID/version/time, observedAt, bundle
path/ID/versions, matched version and explicit limitations. Only associated reports
represent a corroborated installer record; none is confirmedAddition or confirmedUse.
Malformed input/unavailable bundle/command failures throw and emit no report. Nested
helper .bundle is rejected. Missing/symlink executable cannot qualify.

Bounded command helper is internal, synchronous/off UI/audio threads. Fixed reader
commands use a nonblocking stdout pipe, discard stderr, cap bytes and use monotonic
deadline (5 seconds per command). Check deadline while draining and after EOF; do not
wait indefinitely for a process that closes stdout. On failure terminate the owned
child and reap it, closing handles. Tests use known system executables, never user
scripts. No raw paths or logs in tracked fixtures; no plugins loaded or run.

## Acceptance / verification
1. Independent specification critique, then implement.
2. Synthetic tests for path traversal, false IDs/types/times, exact version matching,
   independent bundle/package IDs, helper/missing/symlink bundles, byte/line bounds,
   modified metadata, invalid file lists and command timeout/output/nonzero handling.
3. CLI malformed-argument and controlled invalid-receipt failure tests.
4. Real read-only debug/release inspection of the three known installed products:
   FabFilter/Kontakt associated, Diva versionMismatch. Preserve input hashes/mtime;
   keep reports private. Each report states historical/association limitations.
5. Fresh source review and configured checks:
`python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package`
Run parent `python3 scripts/workflow_gate.py check-complete` truthfully; date release
gates stay open. Native installed bundle validation cannot imply UI coverage.

## State / compatibility / recovery
No new persistent state or settings. Presets, migration, undo, automation, sync,
clipboard, accessibility, analytics and import are inapplicable to this explicit
read-only CLI/source increment. Private report export only; no web uploads. Missing
receipts are unknown, not proof of never-installed content. Process/filesystem errors
are explicit, never empty success. Remove new source/CLI option to revert.

## Resume
Next: independent critic. Alternate-client authentication previously failed; distinct
Codex read-only critic and reviewer are the available fallback. Parent writer is sole
implementer. Final docs precede fingerprint-bound verification.

## Critique clarifications
Info.plist limit is 256 KiB. observedAt must be finite; numeric receipt fields reject
booleans. Compare joined receipt/bundle paths as exact UTF-8 bytes, with no case or
Unicode folding. Either required path missing => notListed; versionMismatch is only
possible after both required paths match.
Use posix_spawn with owned pipes and waitpid(WNOHANG), avoiding any unbounded wait.
After failure: SIGTERM, 100 ms grace; then SIGKILL against the still-unreaped owned
PID and another 500 ms nonblocking reap deadline. A reaping failure returns a distinct
cleanupFailed error (no success/report); never block indefinitely or signal after
reaping. Child stdin/stderr are /dev/null, stdout is the sole bounded pipe. Deadline
also applies after stdout EOF; tests cover early EOF, timeout and nonzero exit.

## Completed checkpoint
Independent Codex specification critic group_source_review passed after bounded
TERM/KILL/reaping and exact type/path clarifications. Implementation uses posix_spawn
and waitpid with owned descriptors; native tests cover timeout, ignored TERM, early
stdout EOF, excess output and nonzero exit. All 151 tests passed in the initial native
run. Source reviewer container_review passed after the CLI invalid-receipt test was
strengthened to reach pkgutil using a valid synthetic bundle.

Debug native checks corroborated the current FabFilter Pro-Q 4 and Kontakt 8 AU receipt
paths/versions; Diva AU remained versionMismatch. Package dates/versions were compared
against fresh public pkgutil output, and Info.plist/executable SHA-256 and mtime were
unchanged. Ignored build/receipt-evidence holds replay code and private manifests.
Final configured checks and debug/release replay evidence are recorded separately
under the parent task. No user's catalog was modified and no plugin was executed.

Remaining product work: automatic receipt discovery, exact current-node association,
historical provenance retention, replacement identity handling and UI source labels.
Do not map this report into confirmedAddition/use or a recent-acquisition indicator.
The reader's associated status only corroborates an installer record, not current-byte
installation time. A provider for actual usage remains separately unqualified.
