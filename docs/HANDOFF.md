# Prism portable checkpoint — 2026-10-05

## Read first

Read `AGENT_GUIDE.md`, `PROJECT.md`, `.workflow/collaboration.json`, and
`.work/active/catalog-evidence-coverage.md`. The active parent is
`libraries-complete-workflow`; its acceptance criteria are still open.
This is an in-progress development checkpoint, not a completed feature or release.

The user requires app-wide basics, not fixes specific to one collection:
- Last Used means a music application's actual load/access attempt, even temporary,
  with no playback or saved project required. Never substitute scan/install/project
  modification timestamps. Individual sample Quick Look, Preview, and Splice previews
  must not count.
- One plugin product owns multiple formats; preserve major versions/vendor identity.
- Complete configured-root indexing, meaningful physical sizes, Date Added,
  actual articulations, searchable durable tags, and responsive sorting.
- Tags must improve through reviewed catalog updates and exact local vendor metadata;
  manual edits and deliberately cleared fields win. Classify product purpose rather
  than source ingredients (Straylight is a granular synth; Una Corda is a piano).
- Astra leads architecture/review; cheaper models implement bounded work. One writer.
  Avoid scope creep, repeated research, or declaring selected examples sufficient.

## Included changes

Earlier library work includes resumable directory indexing, Kontakt group extraction
with the attributed MIT FastLZ implementation, the qualified Spitfire Core Techniques
profile, local NI category enrichment, SINE accounting, Finder Date Added, durable
plugin grouping repairs, reviewed product tags, and complete plugin bundle sizing.

The browser no longer launches an unconditional whole-collection scan on restore.
Metadata/search caches and filesystem-free comparisons reduced a saved-catalog release
benchmark to approximately 0.5 seconds to open Libraries, 0.6–0.9 seconds to search,
and 1.1 seconds for the first tag sort. Those measurements precede the latest v6 work;
repeat them before accepting the final implementation.

Latest shared-system work:
- Live cache reading skips well-formed disabled/unsuccessfully scanned rows instead
  of rejecting the whole cache. Actual cache module scan state 3 exposed this bug.
- Schema v6 adds usage subjects for existing assets and exact library-scoped
  instruments, migrating existing evidence with a backup and transactional copy.
- Typed item access records distinguish outcome, event time and ingestion time,
  require recognized music-app identities, and preserve replay/history. Old untyped
  attempts remain readable without being newly promoted to Last Used.
- Item history projection, library rollups, instrument sorting, and source error
  separation are implemented but need final full-suite and native acceptance.
- A versioned offline reviewed JSON tag catalog and validation are included alongside
  local NI category facts and user override precedence. This is not a universal web
  lookup service or automatic community learning backend.
- Eligible unidentified folders can receive measured physical-folder sizes independent
  of a marketing identity. Shared/overlapping ownership still needs qualified scope.

## Evidence and unfinished work

Before the latest shared-system edits, 296 Swift tests, release build and packaging
passed. Native UI smoke failed because a window screenshot could not be created.
After the latest edits, six focused migration/access/tag/folder tests, state validation,
JSON validation and diff whitespace checks passed. Check the final checkpoint's
workflow evidence for any later whole-suite result; historical passing evidence is
not current acceptance.

A real Live collector check on a private copy of the saved catalog saw 741 eligible
VST3 installations, 799 cache classes, 797 class/path bindings, 24 recorded events,
three projected product histories, ten unbound coverage failures and two rejected
incomplete documents. Multiple classes can belong to one installation. No production
catalog was modified by this check.

**No real sample or Kontakt/SINE patch access collector is implemented.** Shared
storage/projection tests do not establish acquisition. The broad macOS observation
route researched is Endpoint Security, requiring an Apple-granted entitlement,
signed deployment and user approval. No privileged observer was installed. Existing
host adapters remain limited to their documented source/version combinations.
See `docs/research/daw-activity-history.md` and the unified plan. Do not build a fake
observer, infer patch use from a player load, or claim universal historical recovery.

The last collection-wide baseline was 690 library rows, 47,592 instruments,
307 measured library sizes and 207 libraries with product-level metadata tags.
These are different from effective UI tags, which merge additional sources. No new
production-wide size/tag census was performed after the latest fallback/catalog edits.
Universal articulation extraction and the parent four-host usage matrix remain open.
The earlier production refresh correctly grouped bx_glue, PA bx_digital V3 including
mix, and Softube Curve Bender; UAD implementations stayed separate. Rhythmic Aura's
real owner retained 18 patches and size. Celli Core variants each retained 15 choices.
Una Corda's effective tag was Piano and Straylight's Synth/Granular Synthesis.

## Continue on the other laptop

Fetch and check out the checkpoint branch supplied with this handoff. Use Swift 6
on macOS; minimum deployment target is macOS 13, not a tested compatibility claim.

```sh
swift build
swift test
python3 scripts/probe_smoke.py
python3 scripts/template_self_test.py
python3 scripts/sync_agent_adapters.py --check
python3 scripts/catalog_state_check.py
swift build -c release
python3 scripts/build_app.py
```

Then open `build/Prism.app`. For an isolated synthetic inventory without an external
drive, use `python3 scripts/create_offline_demo.py` with a fresh output directory.
These fixtures are not playable content. Native host/real-library tests are opt-in
and require separately available DAWs, plugins, drives and private fixtures.

The local catalog, setup, audio content, DAW logs, screenshots, private runtime
fixtures, temporary harnesses and built app are NOT in Git. Configure roots on the
new laptop; do not assume this machine's paths or private evidence are available.
Do not copy a live SQLite file casually; use a coherent SQLite backup if transferring
private catalog state separately. The production app on the original laptop still
runs the prior packaged build; latest v6 source was not deployed to its catalog.

## Next actions

1. Inspect the current diff/plan and run the portable suite. Resolve any checkpoint
   failures without weakening assertions. The late-restore MainActor timing test
   has intermittently failed in parallel runs; investigate its synchronization.
2. Review v6 migration, exact instrument identity/history, typed process admission,
   parent rollup and patch sorting together. Preserve event times, old payloads,
   explicit tags, and no cross-library inheritance. Recheck UI latency after v6.
3. Verify current plugin source collection in the actual app, then resolve a real
   sample/patch event source and its required OS authority. This is the critical
   missing deliverable; more ledger tests do not close it.
4. Measure effective tags and qualified physical sizes across the whole collection,
   verify unseen-product behavior and catalog update/import paths, and address actual
   remaining shared causes. Do not claim improved percentages without a census.
5. Run final configured gates once the source is frozen, package, perform native UI
   and host acceptance, and run `python3 scripts/workflow_gate.py check-complete`.
   Keep failed/pending gates truthful. This checkpoint is not release approval.
