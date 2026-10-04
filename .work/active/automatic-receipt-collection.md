# Plan: collect installer evidence after plugin inventory

**Status:** IMPLEMENTED — scoped verification evidence; parent release gates remain open
**Owner:** Codex coordinator/implementer; sole writer
**Last updated:** 2026-09-26
**Task ID:** cleanup-essentials
**Risk tier:** 2; existing user intent, no product decision needed
**Domains:** source integration, asynchronous lifecycle, persistence

## User outcome / non-goals
Automatically discover and retain corroborated installer records for freshly scanned
plugin installations. Inventory remains usable while collection runs off the UI actor.
No original-addition/use claim, UI date projection, receipt database mutation, external
scan, new setting, vendor/package-name guessing or network request.

## Research / current state
The exact-installation binder is implemented and verified. Production scans do not
invoke it. Local Apple pkgutil(1) documents --pkgs-plist and sequential multi-command
queries; receipt filesystem layout is explicitly not an API. On this machine direct
--file-info-plist returns empty path-info plus stderr read errors even for known owned
files, so it is unavailable rather than negative ownership evidence. 2,495 package IDs
returned in 0.146s; all metadata queried in batches of64 returned2,495 plist documents
(1,307,450 bytes) in4.303s, with no command errors. A33-ID unbatched metadata/files sample
cost6.69s. A16-package export batch timed out after15s; export is rejected for this work.
Installation-location filtering alone leaves1,948 candidates. Exact declared version
matching (already required for association) additionally narrows file-list queries.
Independent read-only researcher usage_feasibility confirmed documented batching and
ownership lookup limitations. Source: installed Apple manual, current native output.

## Boundary / implementation
- Add PackageReceiptCollector in Core. Public async collect(assets, store) returns a
  Sendable summary with attempted/recorded counts, per-source failure count and explicit
  complete/incomplete/cancelled status. This describes this bounded corroboration pass,
  never all historical installations or original dates. Only fresh plugin catalog IDs
  are eligible; no cached/stale assets, samples or libraries.
- Enumerate package IDs once, validate entire typed plist (<=1MiB, <=4,096 IDs, unique
  UTF8 IDs <=1,024bytes; no controls/blank/leadinghyphen). Metadata batches of32 via
  sequential --pkg-info-plist args (<=256KiB/batch); parse concatenated XML documents
  strictly with fixed pkgutil XML framing and PropertyListSerialization. Require exact
  requested count/order/IDs, no duplicates/trailing garbage; malformed batch is unknown.
  Missing/error batches cannot become negative evidence. Do not retain raw outputs.
- Reuse reader's typed receipt/path parsing and bounded bundle snapshot as internal
  interfaces. Filter candidates by root volume, current exact declared bundle version,
  and whether the bundle path is a descendant of receipt install-location. Version and
  path comparisons are byte exact. No heuristic package ID/brand/name matching.
- For each remaining package query --files once (<=4MiB), join validated receipt root
  and require BOTH exact Info.plist and declared executable membership. Only then call
  existing observe with fresh public queries; binder still revalidates current catalog
  identity. Acquisition index is a hint, never persisted evidence itself. Failed or
  changed receipt inputs retain earlier evidence and mark this pass incomplete.
- Resource limits: <=2,048 input assets; <=512 index payload queries (fresh observation queries are additional); <=256 confirmed-pair
  observation attempts; <=64MiB cumulative command output; <=120s monotonic pass budget;
  every command <=5s and <=remaining budget. Budget exhaustion returns incomplete;
  never truncates an output into valid negative evidence. No unbounded retries. All fresh observe re-queries count toward time/output budgets. Package IDs and bundles sort by UTF8 bytes for deterministic limited coverage. Recorded counts include idempotent replays; failure count counts failed package/bundle operations, not uniqueness.
- Collection executes in detached utility work. Add cancellation checks within
  BoundedCommand's existing polling loop and between commands/attachments. Child cleanup
  remains bounded. Collection rejects any command stderr via a separately drained bounded diagnostic pipe; empty/error output is not negative ownership evidence. Binder checks cancellation at actor entry before opening its transaction, and again before commit; a deterministic queued-call test verifies cancellation while waiting for the actor. The collector awaits each exact-node binder write, never holds a DB
  transaction during process queries. In-flight already committed evidence remains valid
  on cancellation; cancellation must prevent starting another attachment.
- CatalogModel receives optional injected collector (nil in unit/demo contexts); app
  production composition supplies the real one. Start only after successful plugin
  inventory persistence using freshly observed saved IDs, not retained stale items.
  No collection on restore or sample/library-only scan. Cancel on new scan, reset,
  accepted root change and removal. Generation guard prevents late summary publication;
  cancellation handler forwards cancellation to detached work. A transient summary is
  retained for diagnostics/future projection; no table/inspector label changes here.

## Files / state coverage
Core collector/reader/command; CatalogModel + app composition; Core/Catalog tests;
TOOLCHAIN/runtime entry; catalog.date_evidence registry policy and state documentation.
Existing registry group covers automatic population and transient operational summary:
local-only, no preset/project/undo/automation/clipboard/sync/analytics participation;
reset cancels work/clears summary but retains ledger; old payload/schema unchanged;
SQLite backups include only evidence, not transient summaries. No new control/accessibility
surface. Historical paths remain private. No new persisted setting or schema version.

## Acceptance / verification
1. Independent specification critique before implementation.
2. Synthetic tests: strict batch framing/order/duplicate/type/budget rejection; exact
   version/location filtering; shared package/file list queried once; positive exact
   two-file matching -> binder -> replay; mismatch/error/unsupported metadata/budget
   preserves unknown; cancellation stops queries and writes and reaps process promptly.
3. Model injection tests prove successful plugin save starts off-main work; samples,
   restore and failed save do not; reset/new scan/config/removal cancel; late result
   cannot overwrite newer state. Inventory completion does not wait for receipt work.
4. Opt-in native runtime enumerates real metadata with only the three known AU targets,
   binds FabFilter/Kontakt in disposable catalog, checks the known Diva receipt is excluded for mismatch (other genuinely matching receipts remain admissible), replays without
   duplicates. Verify source stamps unchanged. Measure elapsed and command counts;
   no installed plugin or user catalog mutation. Document exact argv before running.
5. Fresh independent source/state review. Final exact checks:
`python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package`
Configured automatic-receipt-runtime check; parent check-complete remains open for
full Last used/Date added/UI release criteria. All content edits precede final checks.

## Risks / recovery / limits
No package receipt implies neither never installed nor unused. Version mismatch,
relocation, skipped installation, removal/replacement and errors remain unknown.
Output/resource/time limits deliberately reduce coverage and must be visible in summary.
No durable candidate cache yet: repeat scan reruns bounded discovery; large collections
may require resumable indexing later. This pass is not full historical coverage.
Per-source failures do not erase prior evidence or prevent final inventory use.

## Resume
Implemented discovery, utility-task scan integration, diagnostic rejection and cancellation
at subprocess/actor/model boundaries. Independent Codex specification critique passed;
fresh source/state review passed after clarifying index-query accounting and adding
settings/root/removal cancellation coverage. Two fixture issues were corrected: binary
plist encoding for an invalid NUL identifier and use of the configured standardized URL
when testing Settings removal. Actor access/async semaphore test code and an app closure
inference error were repaired during compilation. Production cancellation hooks passed.

Native collector discovery enumerated all2,495 installed receipts, issued94 commands,
queried9 index file lists, and retained2 records with0 failures in10.78/10.59 seconds on
two passes. The second pass remained idempotent; bundle snapshots were unchanged. The
opt-in runtime filter additionally exercises CatalogModel's actual three-bundle scan to
automatic collection in disposable storage. Final configured evidence is authoritative.

Next: date presentation must label this as installer evidence, not original Date added.
Successful-use adapters, original-addition qualification and sample/library date sources
remain open. Large inventories can exhaust bounded discovery and need resumable indexing;
no claim of universal historical coverage. No user catalog or installed bundle was
modified during validation. Alternate Claude OAuth previously unavailable; separate read-only Codex
critic/source reviewer fallback. Parent remains sole writer. No approval needed.
