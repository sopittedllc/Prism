# Catalog identity and evidence repair
Acting client Codex; tier 2. Root writes; independent critic/reviewer required; alternate client unavailable in current environment.

## Outcome
Use exact newly supplied JPG for all app branding. One plugin product row across actual Arturia/NI format layouts, name and Last used only. Keep per-installation review and whole-product Trash. Identify actual libraries from manifests/catalogs and make instrument names/tags searchable. Setup describes chosen project locations and actual coverage, not a REAPER-centric promise. Major four DAWs remain mandatory; do not fabricate support or dates.

## Evidence and boundaries
Actual Arturia IDs use com.arturia.component.Acid-V versus com.Arturia.Acid-V.vst3 and com.arturia.aax.Acid-V. NI legacy Kontakt uses Synth/MusicDevice tokens. Only narrowly scoped verified vendor normalization; preserve unrelated publishers and versions. SINE SINELibrary.db schema provides collections/instruments/articulations/mic paths; catalog includes uninstalled products, so require on-disk non-symlink content within chosen roots. Read-only SQLite with bounded queries. Kontakt NICNT embeds ProductHints XML; extract only Name/Company/UPID, never licensing fields. NKI filenames provide searchable instrument labels, not use evidence. Soundpaint libraryInfo.lib is binary; Parts/info.json exposes name/tagging. Research VSL/Spitfire/Decent/Spectrasonics structures; never call random folders libraries.

## Risks/state
All new scan metadata derived and session-only, no new settings/presets/undo/sync/automation/analytics participation; local read-only, exported only in explicit probe JSON. No web upload of local paths or auth data. Keyword inference labeled; player database presence alone not proof of installed content. Bounded metadata reads/depth/entry count, skip sample payloads. Metadata adapter failures surface, do not silently assert complete discovery. History gaps remain unknown. Icon is copied exactly then deterministically resized, no generated replacement.

## Steps
Research official structures and bounded local schemas; critic. Fix icon pipeline and vendor grouping, simplify list. Add structured library metadata and search adapters with provenance and incomplete coverage. Improve actual supported project candidates where verified; report mandatory host gaps explicitly. Tests, local read-only checks, native release capture, independent source/UI review and workflow gates.

## Acceptance
AC1 Exact JPG source checksum, generated mark/Dock visually inspected.
AC2 Acid V formats group into one row; publisher/version collisions separate; selective/all removal retained; plugin table only name/Last used, unknown dates explicit.
AC3 Actual SINE installed collections/instruments and Kontakt manifest/NKI discovery; nested roots work, random folders excluded, Accordion/Banjo search fixtures pass, metadata provenance visible.
AC4 Setup and coverage reflect host-specific truth; no REAPER-centric main detail; broader matching only with validated evidence and no date fabricated from file access.
AC5 Swift tests, release build/package/native smoke, CLI and state/template checks, independent source and visual review.

## Verification
swift test; swift build -c release; python3 scripts/build_app.py; build/Simplify.app/Contents/MacOS/Simplify --ui-smoke captures/catalog; python3 scripts/run_check.py --task catalog-identity --gate automated_tests integration-tests template-integrity adapter-integrity catalog-state; python3 scripts/workflow_gate.py check-complete.

## Outstanding product requirements
Full Logic/Cubase/ProTools/Ableton project and individual instrument usage adapters require host-generated fixtures; do not claim done based on UI copy. Dynamic web enrichment and durable editable taxonomy remain outstanding unless implemented and separately validated during this task. Continue research; record concrete blockers rather than claim complete support.

## Adapter limits and failure criteria
Metadata file cap 8 MiB (NICNT prefix read capped at 64 KiB; only ProductHints XML extracted), XML depth 64 and reject DOCTYPE/entities. SQLite opened READONLY, no extensions, 100 ms busy timeout, progress handler abort after 2 million VM operations, output at most 25,000 rows and 2,000 instruments per collection. Library traversal uses the request entry budget per explicit root (so one root cannot starve another), with a 32-level depth cap with payload directories pruned; instrument lists capped at 2,000 and truncation noted. Errors report issues and partial metadata. Tests must reject malformed/oversized/entity XML, missing/out-of-root/symlink SINE physical content, and catalog-only entries. No input strings become SQL. Only allowlisted columns are read; no license/account tables.

Review repairs: instrument-path dedup across overlapping roots precedes output cap.
SQLite rejects existing special files through nonblocking descriptor preflight and
NOFOLLOW open, but the vendor API reopens by path; adversarial file replacement
between validation and SQLite open remains a residual race. No atomic nonblocking
guarantee is claimed. No writes or plugin execution occur.
