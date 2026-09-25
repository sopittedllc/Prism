# Read-only discovery prototype

Acting client: Codex. Risk tier: 2 (filesystem integration); no user content mutation.

## Outcome and scope

Establish a reusable Swift discovery core and command-line probe on macOS. Inventory
plugin bundles in explicitly selected or standard plugin roots, loose sample files
in selected roots, and immediate library candidates in selected library roots.
Library candidates remain unverified unless a known marker is present; marker evidence
never establishes deletable ownership. The user clarified that inclusion in a saved
project is sufficient usage evidence; playback observation is unnecessary.
This is a feasibility prototype, not a finished UI or universal DAW integration.

No deletion, persistence, plugin loading, automatic private project inspection, vendor database
modification, web tagging, live DAW automation, background service, or licensing access.

## Current evidence

Template only; Swift 6.3.3 and Xcode 26.6 installed on Apple Silicon. Application
listing confirms Logic, Live, Cubase, and Pro Tools are available for future controlled
experiments. Sources: docs/research/audio-ecosystems.md and official Foundation
FileManager / Decent Sampler format documentation researched in this session.

## Interfaces and files

Package.swift; Sources/SimplifyCore for immutable scan models and scanner;
Sources/SimplifyProbe for argument parsing and JSON output; Tests for synthetic
fixtures; scripts/probe_smoke.py for end-to-end checks; toolchain, README, research,
and architecture documentation. No catalog persistence or editable product state yet.

## Behavior and failure modes

- CLI accepts repeated --plugins, --samples, --libraries paths; --standard-plugins
  explicitly enables standard system/user plugin roots. No arguments prints help.
- Plugin formats: component, vst, vst3, aaxplugin, clap. Bundle metadata is read
  without executing plugin code; missing metadata still yields a candidate.
- Library roots yield immediate child directories as candidates and supported
  container files (dslibrary); a dsbundle directory identifies Decent Sampler.
  Each directory candidate represents a location, not proven library identity.
- Samples: wav, aif, aiff, flac, mp3, m4a, caf, ogg; extension-based candidates only.
- Files under selected library roots or plugin bundles do not appear as loose samples.
- Do not follow symlinks (including symlink ancestors of an explicit root), hidden
  directories, or package internals. Report skipped symlinks, inaccessible/missing
  roots, traversal errors, and traversal limits as issues; never imply a complete scan.
- Duplicate/overlapping roots produce each path once per asset kind. Deterministic
  ordering; no content hash or reading audio bodies; paths are local sensitive output.
- Maximum traversal depth 64, maximum visited entries 100,000 per scan; truncation
  must be explicit. Directory sizes remain unknown; file sizes are logical bytes.
- Usage is explicitly unknown; no filesystem date becomes usage evidence.

## Project-reference amendment (user direction)

- Add repeated --projects directory roots. Scan only explicitly provided roots.
- First project adapter: REAPER .rpp text, scoped to FILE entries inside SOURCE
  blocks and plugin declarations inside FXCHAIN/TAKEFX blocks. Nested SOURCE wrappers
  are supported; quoted paths with spaces are preserved. Never search arbitrary
  strings in opaque plugin state for asset identity. Unknown sections stay unknown.
- Add experimental Ableton .als support only if factory files establish structure.
  Restrict sample extraction to SampleRef/FileRef. Plugin identity extraction is
  deferred because no factory plugin descriptors were found. XML external entities
  are disabled; gzip output is bounded.
- Each project report names adapter, coverage (partial/unsupported/failed), references,
  project modification time explicitly labeled as a proxy for saved-project recency,
  and limitations. Successful parsing never means complete dependency coverage.
- Recognize other major DAW project extensions as unsupported rather than empty.
- Match samples only by normalized absolute paths or project-relative paths; foreign
  Windows paths stay unresolved. No basename matching, symlink resolution, or content
  deduplication. Ambiguous Ableton paths remain separate candidate references.
- Plugin identities remain references, not automatic installed-product matches.
  Opaque player state cannot prove a particular nested library was used.
- Project input capped at 32 MiB, decoded data at 64 MiB, and nesting at 128.
  Malformed projects report failure and discard extracted references.
- A sample's latest referencing-project modification date is a recency proxy only,
  never exact use/add time. Preserve each reference and its project provenance.
- Fixture tests must cover muted/bypassed inclusion, nested sections, quoted paths,
  malformed inputs, foreign paths, unsupported formats, bounded parsing, and recency.
- Real-target validation may use bundled factory tutorials/templates, never private
  sessions without an explicitly selected project root. Host-save interoperability
  remains unverified until a controlled session is saved by the host.

## Acceptance criteria and verification

1. Swift build and tests pass with no external dependencies. Fixture tests prove
   plugin format/metadata discovery, candidate libraries and samples, root overlap,
   missing root, symlink boundary, bundle exclusion, and limit reporting.
2. CLI JSON is machine-readable; invalid arguments fail with nonzero status; help
   performs no scan; issues produce exit 2 with a partial report; no usage dates exist.
3. End-to-end smoke checks prove fixture files/content/modification times unchanged.
4. A standard-plugin scan on this Mac reports aggregate counts and duration only in
   durable evidence; detailed local output remains ignored. No third-party code loads.
5. Usage feasibility report distinguishes verified facts, proposed experiments, and
   unavailable runtime evidence for all ten DAW families; no universal usage claim.

Exact commands will be bootstrapped into .workflow/toolchain.json before gates run:
swift build; swift build -c release; swift test; python3 scripts/probe_smoke.py;
python3 scripts/template_self_test.py; python3 scripts/sync_agent_adapters.py --check.

## Sequence and rollback

Critique plan; build core and CLI; tests and smoke; run read-only local plugin scan;
record usage research; fresh review; repair; rerun affected checks and completion gate.
Rollback is removal of newly created prototype files; no scanned assets change.

## Resume notes

Implemented read-only scanner and experimental project readers. UI and controlled
host-saved fixture verification remain follow-on work. Independent Codex plan critique
passed; Claude is installed but not logged in. Native hook enforcement was not exercised;
shared deterministic gates are run directly. Final review and gate results live under
.workflow/evidence/discovery-prototype/. No real user projects were inspected.
