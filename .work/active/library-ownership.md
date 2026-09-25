# Library ownership foundation

Acting client: Codex, implementer. Independent Codex critic/reviewer used because
no alternate-client runner is available. Implements the first identity increment of
library-catalog-redesign.md; does not claim the full redesign is delivered.

## Outcome and current evidence
Library discovery must retain product → instrument → installed content relationships
before persistence and the outline browser adopt them. Current Kontakt fallback
creates a library for every NKI-containing folder; SINE drops all but one microphone
path per instrument and uses that path as its implicit identity.

## Scope / interfaces
- LibraryMetadata.swift: optional additive identity/ownership metadata, identification
  confidence, separate context tags vs aggregate searchable instrument tags; preserve
  decoding existing reports. Vendor SINE collection/instrument IDs are namespaced;
  paths remain locators, never pretend to be stable logical vendor IDs.
- LibraryDiscovery.swift: infer a proposed Kontakt boundary at a folder with an
  Instruments child and Samples or Kontakt sample containers; inherit ownership down
  the tree. Manifest identity wins. Unsupported layouts remain explicitly unresolved.
  Inference is never vendor confirmation or removal authority. No climbing outside
  selected scope. Sample roots, symlinks, budgets, duplicate roots remain respected.
- Tests: synthetic CAGE Winds, manifest precedence, nested separate libraries,
  ambiguous folders, multi-microphone SINE, Ark 2 vs 3, no sibling-tag inheritance,
  backward-compatible decoding and deterministic order.
- docs/research: executable acceptance matrix for Logic/Ableton/Cubase/Pro Tools
  usage feasibility, with unknowns and positive/negative fixture requirements.

No new UI/state settings, SQLite adoption, editable tags, storage totals, usage dates,
file removal or DAW compatibility claims in this increment. The comprehensive plan
requires SQLite before replacing the tree; this work supplies its adapter contract.
No user audio or vendor data written. Session-derived fields keep existing state
policies; probe JSON explicitly exports the additive fields.

## Ordered implementation
1. Critique this plan before changes.
2. Define explicit ownership metadata with backward-compatible optional fields.
3. Fix Kontakt proposed boundaries and SINE file membership/IDs deterministically.
4. Add golden regression fixtures and usage acceptance matrix.
5. Run swift test, swift build -c release, CLI integration, template/adapter/state
   checks; read-only local library probe plus independent review; close workflow.

## Risks and acceptance
AC1: CAGE Winds Instruments/Low Winds and High Winds belong to one proposed product,
not two libraries; manifest-backed product remains verified and overrides inference.
AC2: No merge of neighboring products or escaping selected root, even on overlapping
roots; manifest ambiguity is reported and no arbitrary manifest owns all patches.
AC3: SINE stable vendor identities survive microphone order/path changes; every
installed scoped mic metadata/archive pair is retained, no outside or missing pair.
Ark 2 and Ark 3 stay distinct. Equal names do not merge vendor IDs.
AC4: Context tags contain maker/product only (series only with evidence); effective
instrument search tags add that instrument's tags, never siblings' tags. Existing
report decode succeeds without additive fields. No inferred dates or totals.
AC5: Four mandatory hosts have explicit evidence matrix and unknown/validation
status; all regression commands and fresh read-only review pass.

## Validation / resume
Exact commands: swift test; swift build -c release;
python3 scripts/run_check.py --task library-ownership --gate automated_tests integration-tests template-integrity adapter-integrity catalog-state;
python3 scripts/workflow_gate.py check-complete.
Local read-only probe uses configured library roots; raw paths/output stay private.
UI composition unchanged: native outline and visual validation belong to next increment.
Resume after this increment with SQLite graph + migration/state policies, then outline.

Review repair: ownership identity must propagate through Scanner and CatalogModel
indexing and native table selection; physical reveal continues to use real paths.
Additive read-only SINE database injection enables full scanner/model fixtures.
Malformed nested manifests clear inherited product ownership. Added acceptance
fixtures for both findings. No new presentation or persistent state.

## Delivered evidence
54 Swift tests pass; independent source review PASS after two integration repairs.
Read-only local check: 379 library groups with 9,871 instrument entries; CAGE Winds
is one group with five patches; SINE has 20 distinct collection IDs and 2,486 known
metadata/archive memberships. Prior grouping was 455 with the same instrument count.
Three coverage issues remain: sample entry cap, library entry/depth cap, one unparsed
Kontakt manifest. No claim of complete disk inventory. Initial local debug check
11.32s includes loose-sample roots; this is not a scan-speed benchmark.
