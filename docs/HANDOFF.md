# Prism development handoff — 2026-10-03

This is a portable checkpoint for continuing on a Mac without the external
Samples drive. The project is a native macOS Swift package and AppKit preview,
not a released or complete cleanup product. Start with [AGENT_GUIDE.md](../AGENT_GUIDE.md),
[PROJECT.md](../PROJECT.md), [TOOLCHAIN.md](../TOOLCHAIN.md) and
[.workflow/collaboration.json](../.workflow/collaboration.json). The active
parent task is `cleanup-essentials`; its four-host, individual-asset Last used
acceptance criterion remains open.

## What works now

- Inventory finds installed AU, VST2, VST3, AAX and CLAP bundles without loading
  them; it discovers individual audio files, Kontakt manifest/instrument-name
  candidates, SINE catalog entries, Soundpaint parts and recognized STEAM
  structures. Explicit sample and library roots can overlap. Scans are bounded,
  show incomplete/unavailable scope, and preserve stale catalog history when a
  volume is offline.
- The native browser has Plugins, Samples and Libraries, name/tag search,
  column sorting, hierarchy, contextual details, source labels, local settings,
  editable tags/metadata with Undo, and measured size where available. Plugin
  formats and installations can be reviewed and moved to Trash with identity
  checks. Sample/library removal is not implemented. Sizes are observations,
  not guaranteed reclaimable bytes; instrument size can be shared or unknown.
- The app preview was renamed Prism and packages the supplied logo. Settings
  persist Light (default), Dark or Match system appearance. Compact setup and
  inspector tag pills support keyboard interaction; category-scoped scans keep
  other categories visible. Plugin products group installed formats. Date added
  distinguishes a known exact day from **By** (present no later than that day)
  and **During** (appeared between observations); neither label turns first
  discovery into a proven original acquisition date.
- Catalog inventory, setup, tags and immutable date evidence persist locally.
  Recorded package receipts can support a labeled installation/update date;
  first discovery is separate; original Date added remains unknown without a
  qualified source. Scans and project mtimes do not become Last used.
- Partial REAPER/Live/Logic saved-project references and Pro Tools/Cubase
  diagnostic/export readers exist. A project reference is a candidate or an
  explicitly labeled recency proxy, not a successful load timestamp. See
  [usage plan](../.work/active/usage-evidence-delivery.md) for adapter limits.

## Last used: exact current coverage

The user counts even a brief DAW instantiation; playback is unnecessary. The
adapters below only promote the positive sequences that were actually qualified.
Unknown does not mean unused. Binding is to the observed plugin product/class
and current installed-format candidate; it does not prove physical installation
lineage or that an old event belongs to a copied bundle.

| Host | Admitted plugin evidence | Important limit |
| --- | --- | --- |
| Ableton Live 12.4.5/12.4.6 | Completed VST3 document restore; separately, manual create with matching Going-to-create, successful processor load, and Created records, bound by exact VST3 class/cache identity. Native Pro-Q 4 create/delete-before-save control passed. | No arbitrary Live version, player instrument, sample, audible output or universal history claim. Startup load chatter and failed restores are excluded. |
| Cubase 15.0.30 | VST3 Add candidate promoted only after project activation and successful Project Status: Load in Usage Logger, with exact cache tuple/path binding. Scan-only control was negative. | Native manual Add/Remove occurred on a disposable track, but Add has no proven plugin-instance success token; manual use is not admitted. Logging may be disabled or unavailable. |
| Logic Pro | Current mixer accessibility observation of an AU plugin group with bypass/open controls, persisted as an observed-use event. | Polling/AX observation can miss brief use; coverage is limited to exposed mixer controls. There is no guaranteed instantiation event stream or full historical Logic project coverage. Requires Accessibility. |
| Pro Tools 24.10.2 | AAX Host Instantiate candidates within a completed session restore, source-local clock v2 and exact unique installed-AAX name binding. Full native restore of Pro-Q 4, Kontakt 8 and Diva passed parse, store/reopen and presentation checks. | Name binding is product association, not a stable plugin ID. Startup failure and host-internal AudioInjection remain excluded/unbound. Native manual Pro-Q 4 insert then FreePlugIn on a temporary track was visually confirmed, but had no distinct completion token and is not admitted. Legacy v1 dates remain readable history but cannot set Last used. |

No adapter yet proves Last used for an **individual WAV** across the required
four hosts. Kontakt public state exposes candidate library ID `P44` for the
controlled Accordion state, and exact SNPID can bind that ID to an installed
manifest. The active instrument name, NKI path, load outcome and event time
remain unproven. A separate filename table yielded a Wineglass NKI path but
its association with an active program was not established. Neither a whole
Kontakt library candidate nor project modification time may be promoted to
instrument usage. Other player-specific instruments remain open.

## Evidence and limits on this checkpoint

The last pre-handoff configured run recorded **226 passing generic Swift tests**,
a release build, app packaging, and a separate opt-in native Pro Tools restore-v2
test. The native Pro Tools control used complete private logs, an unchanged
disposable PTX and actual installed AAX products; manual insert/remove produced
Host Instantiate and FreePlugIn but no restore completion. Other native controls
for Live/Cubase/Logic and package receipts are described in
[the active plan](../.work/active/usage-evidence-delivery.md). These historical
results are not a claim that this later portability edit has the same fingerprint;
run the generic checks below on the new Mac.

Only source, synthetic tests and sanitized summaries belong in Git. Ignored
`build/` holds private DAW logs, PTX/ALS/CPR controls, screenshots, transient
catalogs and package outputs. The original offline Samples metadata snapshot
is also private on the first Mac, outside this repository. No audio, NKI,
sample payload, private report, log or database should be copied into the
checkpoint. Some historical `.workflow/evidence/**/*.json` records refer to
ignored `*.log` files; those paths document local verification and are not
replayable on a clean clone.

A sanitized [Samples structure aggregate](../tests/fixtures/samples-drive-aggregate.json)
retains scale information from the private metadata-only snapshot: 2,150,069
files, 162,992 directories, depth histograms, anonymized top-level subtree
counts and selected extension counts. It contains no names, paths, file dates,
device IDs, audio or instrument bytes. The full collection exceeds the current
100,000-entry per-category preview limit; the small synthetic demo below is
for functional development, not a scale substitute.

## Fresh clone on a Mac without Samples

After the checkpoint commit, the coordinator creates a local
`build/Prism-portable.bundle` for transfer; the bundle itself is not committed
or pushed. Copy that file to the other Mac, then:

```sh
git clone /path/to/Prism-portable.bundle Prism
cd Prism
swift build
swift test
```

The clone's `origin` points at the transferred bundle, not a hosted remote.
If a hosted remote is wanted later, configure it deliberately from the
existing repository; this handoff does not include a private remote URL or
perform an automatic push.

For the complete original folder inventory, separately transfer the private
`build/Prism-Samples-metadata.tar.gz` archive from the first Mac. It contains
only the read-only inventory database, folder tree, research notes and query
script; no audio or instrument payloads. It retains real collection names and
paths, so keep it private and out of Git. It is optional for normal development.

```sh
mkdir -p build/private-samples
tar -xzf /path/to/Prism-Samples-metadata.tar.gz -C build/private-samples
python3 "$PWD/build/private-samples/Samples-research/query.py" accordion
```

The query reads the transferred metadata database, not the original drive.
Recorded source paths are historical strings, not mounted-volume requirements.

Use **Swift 6** tools (last verified with Swift 6.3.3/Xcode 26.6). The package's
macOS 13 deployment floor is a separate target and has not been tested on that
older OS. No external drive, installed DAW, commercial plugin or network request
is required for the generic commands:

```sh
swift build
swift test
python3 scripts/probe_smoke.py
python3 scripts/template_self_test.py
python3 scripts/sync_agent_adapters.py --check
python3 scripts/catalog_state_check.py
python3 scripts/create_offline_demo.py
.build/debug/simplify-probe \
  --plugins build/offline-demo/Plugins \
  --samples build/offline-demo/Samples \
  --libraries build/offline-demo/Libraries \
  --projects build/offline-demo/Projects \
  --metrics > build/offline-demo/report.json
```

The demo generator refuses to overwrite an existing destination; pass a fresh
`--output` directory for another run. Its tiny text payloads have audio/plugin
extensions for inventory tests but are **not playable audio or installed
plugins**. The CLI report contains local paths and stays in ignored `build/`.
For the native browser, run `swift build -c release` and
`python3 scripts/build_app.py`, then open `build/Prism.app` and add the four
generated roots in Setup. The app also includes standard system plugin roots
automatically; use the CLI command above for an **isolated** synthetic inventory.
The isolated
`build/Prism.app/Contents/MacOS/Prism --ui-smoke captures/catalog` flow is a
separate automated AppKit check; it creates its own fake catalog and exits.

Native checks are **opt-in** and intentionally machine-specific. In particular,
`PRISM_PROTOOLS_RESTORE_V2_RUNTIME=1` requires private full-log captures and
installed AAX controls; `PRISM_PROTOOLS_RESTORE_FIXTURE_DIR` can point to a
private capture copy. `PRISM_KONTAKT_TABLE_RUNTIME=1` requires private state
tables and `PRISM_KONTAKT_MANIFEST_PATH` for the native Accordion manifest.
Other host checks likewise require the documented local controls. An explicitly
enabled check with missing prerequisites reports failure; absence from a generic
run is not native validation. See [TOOLCHAIN.md](../TOOLCHAIN.md).

## Next work, in priority order

1. Re-run generic checks on the new Mac; inspect coverage and only then create
   new revision-bound evidence. Do not use historical passing JSON as current
   signoff. Use the offline demo for browser/discovery work without reconnecting
   Samples.
2. Qualify native manual Pro Tools and Cubase success/failure grammar before
   admitting their brief unsaved insertions. A lone Add or an unrelated save
   marker is insufficient. Keep private controls out of Git.
3. Establish exact individual-WAV and active instrument/NKI identity plus
   source-local load times in each of Live, Logic, Cubase and Pro Tools. Saved
   project inclusion alone cannot establish historical instantiation time.
4. Continue resumable indexing and partial-coverage UX for collection scale;
   test against synthetic bounded structures and the sanitized aggregate until
   representative content is available. Finish parent cleanup gates, reviews,
   accessibility/visual/runtime checks and release decisions separately.

Coordination preference: Astra handles product management and final review;
Sol/Luna take bounded implementation and research tasks, with one source writer
at a time and independent read-only review. The current handoff is a checkpoint,
not an assertion that the whole product or four-host usage matrix is complete.
