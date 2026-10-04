# Library container traversal

Status: IMPLEMENTED AND VERIFIED; independent Codex container_critic and container_review PASS. Codex sole writer; risk 1; scoped follow-up to library-ownership.
Parent cleanup-essentials remains open. User authorized continued offline work.

## Outcome / evidence
A library root may contain a collection directory literally named Samples. The local
read-only drive snapshot records a top-level Samples folder containing a Kontakt
collection, with Instruments/NKI descendants. LibraryDiscovery currently skips every
directory named samples regardless of whether an owning library exists, making that
collection unreachable when the selected library root is its ancestor.
Snapshot lives in the private Prism Research Snapshots directory; no raw filenames or
paths are committed. It contains metadata only, not vendor manifest contents.

## Scope and non-goals
Change only the `samples` directory exclusion: skip it when a library owner exists;
when no owner exists descend under existing scope, symlink, depth and entry guards.
Other excluded directory names/packages stay unchanged. This is traversal, not proof
of identity. Existing manifest/proposed/unresolved semantics remain unchanged.
Do not change ownership inference, vendor adapters, scan limits, UI, catalog schema,
usage dates or removal. Folder contents remain subject to selected sample-root exclusion.
Known mixed folders beneath an owning manifest and sample scan scale remain separate
work; no claim this single change completes discovery across the drive.

## Files / implementation
Sources/SimplifyCore/LibraryDiscovery.swift; tests/SimplifyCoreTests/LibraryContainerTests.swift;
this plan and private research findings/evidence. No persistent state introduced.
1. Independent spec critique. Implement owner-sensitive Samples skip.
2. Synthetic tests exercise nested collection traversal, manifest and proposed owners,
   payload exclusion, scope precedence, symlinks and finite entry budget.
3. Native debug/release CLI run over a generated sparse hierarchy reflecting the
   observed nesting, with invented product names/content; verify exact found patches,
   no payload patch admission and unchanged fixture hashes. Fresh independent review.
4. Configured checks and final evidence; parent remains open.

## Acceptance
- Selecting an ancestor discovers a manifest-backed product through unowned Samples
  containers and attaches Instruments patches to it, retaining maker/identity.
- Selecting the collection directly produces the same product/patch identities.
- Samples payload under manifest/proposed owner remains untraversed, including decoy NKI.
- A Samples directory explicitly selected as sample scope remains excluded from
  library results; more-specific library scope still wins per existing contract.
- Linked containers remain skipped; low entry and depth budgets report incomplete, never bypassed.
- No date, ownership confidence or removal authority invented by traversal.

## Verification / runtime / risks
Read-only synchronous per-scan state, existing budgets and recursion limits. Walking
previously excluded containers may consume budget sooner; retain incomplete issues.
No audio/plugin execution, network or external source mutation. Local sparse runtime
fixture checks discovery integration, not binary parsing or full physical-drive coverage.
Exact runner: python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package
python3 scripts/workflow_gate.py check-complete (parent remains open).
No UI changes; no UI gate claimed. Native hooks unavailable, deterministic gates used.
Prior alternate Claude OAuth unavailable; independent Codex roles as documented fallback.

## State / rollback / resume
No state fields: defaults/presets/migration/undo/automation/sync/import/analytics not
applicable. Existing scan report export unchanged; privacy local only. Roll back only
this condition/tests, preserving other work. Source/test/doc changes invalidate evidence;
rerun affected gates. All eight configured checks passed, including 119 tests. Final evidence records the current content fingerprint. Native CLI replay and independent source review passed; parent completion remains pending.

## Results and next work
The Samples-only offline inventory exposed the unreachable container route. Updated
only the owner-sensitive Samples exclusion; no drive access needed for implementation.
Native debug/release sparse-fixture replay discovers two invented manifest products
through nested Samples containers, exact expected patch paths, and no payload decoys;
fixture hashes/mtimes are unchanged. Three new regression tests bring total to 119.
An initial new-test compile failure used nonexistent Asset.id; repaired to compare
actual path and LibraryIdentity, then reran tests. Fresh read-only source review passed.
The captured inventory records 28,210 NKI filenames beneath its top-level Samples
container. This is structural evidence, not an assertion that production discovery
has indexed all of them. Full offline findings remain beside the private snapshot.
Current sample entry cap and persisted/resumable indexing remain unresolved; do not
raise caps arbitrarily or treat capped scans as complete. Continue macro usage and
identity work with those limits visible; parent Last used remains open.
