# Composer metadata and new acquisitions: proposed product direction

2026-09-25. Research/specification only; no application changes. Audience confirmed by the user: film, TV and game composers using **Spitfire, Orchestral Tools and Cinematic Strings**. This proposal extends the [full audit](REPORT.md). It is not a claim that these fields or acquisition controls are implemented.

## Decision

Prioritize **what plays, how it plays, and how it feels**, then the library/player and practical constraints. New content should become a small, intentional **Try next** queue. Avoid a giant tag wall, thousands of new-patch notifications, or silently treating browsing as proof of musical use.

The recommended default facets are **Instrument, Technique, Solo/ensemble, Character, Library/maker**. Register is readily available for orchestral content, and player/availability remain easy refinements. Microphone, recording space, range and detailed technical data live under More filters or the inspector. Rhythm/key/tempo appear when loops and hybrid material make them useful. This ordering is a well-supported design hypothesis, not a measured ranking of composer search terms.

This document governs the proposed field priority and product decisions. `metadata-research.md` is supporting evidence/input, not a competing priority list. `acquisitions-design.md` supplies the detailed interaction/state policies. All remain proposed until prototype validation.

## What market research can establish

| Evidence | What it supports | What it does not support |
| --- | --- | --- |
| [KVR 2025 reader awards](https://www.kvraudio.com/readers-choice-awards/2025/) | A recognizable test corpus: BBC Symphony Orchestra, Noire, Omnisphere, Falcon and Pro-Q occur among category winners. The votes are from participating KVR members. | Worldwide installed share, sales ranking, representative film-composer preference or actual query frequency. Current product pages can update version labels; use product families rather than infer award-era versions. |
| [MIDiA / Splice Sounds of 2026](https://www.midiaresearch.com/sounds-of-2026) | Platform search/download behavior is measurable: the public summary reports 1.3 million Afro house searches and 6.7 million downloads in 2025. This supports genre as a real retrieval dimension for that audience. | Genre priority among orchestral composers. These are not library/plugin ownership data. Only the public summary was reviewed, not an independently audited underlying dataset. |
| Official vendor catalogs/manuals | Which distinctions actually occur in the target libraries and how vendors name them. | How often users search a term, whether its metadata can be extracted locally, or whether a marketed feature is installed on this machine. |
| Our verified source audit and probes | What Simplify can represent/retrieve today and which foundations must be repaired. | User satisfaction or demand for an unbuilt feature. |

No representative public dataset of this target audience's local-library search queries was found in this research. Do not manufacture a “top 10 composer searches” chart from bestsellers, forum anecdotes or store categories. Use the three named vendors as the primary corpus because the user chose them, and the market signals as secondary breadth checks.

## Representative corpus, not a popularity leaderboard

- **Spitfire:** BBC Symphony Orchestra editions and Spitfire Symphony Orchestra. Include solo and ensemble strings/brass/woodwinds, percussion, differing player/edition and microphone availability. The vendor documents concrete section/technique/mic distinctions; edition-level facts must stay edition-specific. [SSO product](https://www.spitfireaudio.com/products/spitfire-symphony-orchestra), [BBC Core manual](https://support.spitfireaudio.com/en/articles/16390288-bbc-symphony-orchestra-core-user-manual).
- **Orchestral Tools:** Berlin Strings/Solo/Special Bows and Metropolis Ark collections. Include different ensemble lineups, registers, extended techniques, and installed mic subsets. Berlin and Ark are distinct series; Ark numbers are product identity, not interchangeable aliases. [Berlin series](https://www.orchestraltools.com/berlin-series), [Ark 1 notes](https://orchestraltools.helpscoutdocs.com/article/371-metropolis-ark-1-notes).
- **Cinematic Strings / Cinematic Studio Series:** keep **Cinematic Strings 2 (CS2)** and **Cinematic Studio Strings (CSS)** separate. The vendor explicitly distinguishes the older hall-recorded product from the newer scoring-stage library. Use both in alias/identity tests, alongside section and technique queries. [Official distinction](https://cinematicseries.zendesk.com/hc/en-us/articles/206359724-What-is-the-difference-between-Cinematic-Strings-2-CS2-and-Cinematic-Studio-Strings-CSS), [CSS](https://cinematicstudioseries.com/strings/).
- **Secondary breadth:** a hybrid percussion library, a texture/synth product, an acoustic solo instrument such as accordion, and orchestral mixing effects. These prevent a string-only taxonomy without changing the composer-first priorities. Product selection is a research fixture decision; buying or installing them is not authorized or necessary for this proposal.

Use actual installed versions and licensed local content only when later validating adapters. Website descriptions support product-level research, never fabricated installed patch records.

## Proposed searchable metadata

| Priority / question | Facets | Example values and constraints |
| --- | --- | --- |
| Core: “What instrument?” | Family, instrument, section, instrumentation | Strings; cello; violins I; low strings; bass clarinet; low brass. A composite ensemble records its constituents; a solo tuba is not the same result type as a low-brass ensemble. |
| Core: “How is it played?” | Technique, transitions, duration behavior, modifiers | Legato, sustain, staccato, spiccato, pizzicato, tremolo, trills; muted/con sordino; sul ponticello/sul tasto. Keep canonical IDs and exact vendor labels. Multiple dimensions may apply simultaneously. |
| Core: “How many / which register?” | Solo/section/ensemble, player count if known, register | Solo violin, chamber section, full section, low/high; numeric counts only from scoped evidence. “Intimate” cannot automatically prove a small ensemble. |
| Core: “What character?” | User-correctable sonic character | Soft, warm, dark, bright, intimate, tense, aggressive, airy, evolving. Vendor/user/inferred sources remain distinguishable; subjective does not mean unusable. |
| Core: “Which library was it?” | Maker, series, product, edition, aliases, player | Spitfire / BBCSO / Core; Orchestral Tools / Ark 2; CSS versus CS2; Kontakt versus SINE. Preserve product/version/installation distinctions. |
| Contextual: “What role in the cue?” | Musical role and motion | Melody, ostinato, bed, texture, pulse, transition, rise, hit/impact, drone. These may be personal tags or attributed vendor descriptors. |
| Advanced orchestral | Recording space, mic/perspective, range, dynamic behavior | Hall/stage/studio name; close/tree/ambient or vendor mix; playable pitch range; dynamic layers if verified. Close mic is not synonymous with dry. Do not expose unsupported fields as if measured. |
| Contextual hybrid/sample | Loop/one-shot/phrase, BPM, key, meter/rhythm, duration | 110 BPM, D minor, straight/triplet, playable versus recorded phrase. Unknown/not applicable are real states; a bare filename number is not automatically tempo. |
| Operational, separate | Availability, footprint, discovery/acquisition dates, explored state, favorites | Offline; measured/partial size; first found; manually supplied acquisition date; Try next. These must not become ambiguous musical tags or usage dates. |
| Plugins for this audience | Function, maker, format/version, relevant modes | Reverb, delay, EQ, dynamics, saturation. “Low CPU” requires comparable measurements or an explicit personal label; no silent plugin execution during scanning. |

### Important model distinction: an articulation is not necessarily a file

A single Kontakt instrument can expose several articulations internally. Search should return that installed instrument with a matched capability when supported by version-specific evidence. Do not invent a separate installed NKI or tree child for each technique on a vendor webpage. Separate:

1. Product advertises a capability.
2. Installed instrument/variant is verified to provide it.
3. Current load/configuration uses that capability (usually unknown to Simplify).

The first can support a labeled product-level search result; only the second supports an installed-instrument match. The third is outside passive inventory unless a validated observation adapter provides it.

### Example searches to test

| Query | Expected interpretation and useful result |
| --- | --- |
| `solo cello legato` | Instrument=cello, ensemble=solo, transition capability=legato. Explain the matched installed instrument. |
| `short low brass` | Family=brass, register=low, short behavior. Show matching specific techniques without equating all shorts. |
| `soft strings con sordino` | Strings + muted technique/modifier + attributed soft character. Preserve missing-character coverage. |
| `Spitfire violin tremolo` | Maker plus instrument and technique; do not include every sibling patch in a broadly matching library. |
| `Ark 2 low strings` | Resolve exact series/product alias plus instrument; never merge Ark 3. |
| `CSS spiccato` | Resolve Cinematic Studio Strings identity and supported technique. `CS2` remains a distinct product. |
| `dry chamber strings` | Strings + ensemble evidence + recording/character assertion; no deduction of dry from close microphone alone. |
| `accordion Kontakt` | Instrument plus player requirement; Kontakt itself is not evidence of an accordion library. |
| `dark evolving texture` | Character/role constraints with transparent match reasons; title-only matches ranked separately. |
| `hybrid percussion loop 110 bpm` | Contextual loop/tempo/role filters, tolerant range only if the user selects it. |
| `new orchestral libraries` | Orchestral classification plus newly found after an established inventory baseline; no invented install date. |
| `strings on my external drive` | Instrument + chosen root/availability; retain offline results with a clear label. |

AND across chosen facets, OR within an explicitly multi-selected facet is the proposed default. Free text should expose recognized constraints so the user can correct them. Exact names/aliases and instrument evidence outrank generic marketing descriptions. Retain broad free-text matching for notes and uncertain metadata, but label why results match.

Synonyms require scope: celli/cellos may normalize; shorts can group related duration behaviors but does not erase staccato/spiccato differences; marcato can be long or short; legato is not merely sustain. Preserve manufacturer terminology and edition/variant context. A negative tag decision must survive rescanning.

## New acquisitions as an exploration workflow

Use **New to explore**, not an assertion that all new files are new purchases. It is an owned-collection view, not an advertisement or a push-notification funnel.

A later scan can show a quiet message: **“3 libraries newly found · Explore”**. The list groups by product/library and discovery batch. One library with 2,000 instrument files remains one top-level discovery. Additional plugin formats or mic positions update an existing product; they do not create a flood of new acquisitions.

A card/row answers: **what is it, why might I use it, and what can I do next?** Show product/maker/player, a few supported instrument/technique/character descriptors, first-found date and availability. Offer one supported starting instrument when evidence permits; otherwise offer the library without a made-up recommendation.

Actions:

- **Try next:** deliberately pin a library/instrument to a short queue for the next writing session. Users choose the order; no arbitrary automatic limit or countdown.
- **Save for later:** retain it in a deferred list without reminders.
- **Mark explored:** explicit user-declared review status, undoable. It does not mean loaded in a DAW, played, used in a project, or safe to remove.
- **Favorite:** independent durable preference, also undoable.
- **Show location / Copy instrument name:** practical initial handoff. A real sample Preview or Open in player action appears only when that route is implemented and validated; browsing must not silently execute plugins.

Merely viewing a row or opening Finder never marks it explored. Existing favorites and “Try next” items remain searchable when offline; unavailable actions explain why. Newness and exploration are separate: an old library may be intentionally queued; a newly found library may already be familiar. Dismiss from new is an explicit reversible disposition, not deletion.

| Actual event | Honest label / behavior |
| --- | --- |
| Initial catalog scan | Existing collection indexed; no thousands-of-new-items badge. |
| Newly selected root | Newly indexed location; optional review, not automatically newly acquired. |
| New identity within previously established scope | Newly found, with observation date. Installation/purchase date unknown. |
| Known drive reconnects | Available again; preserve original identity and user state. |
| New patch/mic/version for existing library | Library updated, with scoped changes if known. |
| Identity ambiguous after move/reinstall | Needs reconciliation; do not silently duplicate or transfer edits. |
| User supplies acquisition date | Acquired on date — user supplied. Preserve original observed dates. |
| Partial scan | Coverage incomplete; retain earlier items and avoid conclusions from absence. |

F03/F04 in the audit (scope continuity and baseline completeness) are **prerequisites** for trustworthy newness. Discovery events should bind to stable inventory identities; acquisition dates and exploration decisions need independent fields and provenance. Favorites are not deletion protection unless the UI explicitly defines that policy; a separate Protected state would be a later cleanup contract.

### Explicit proposed state transitions

| Action | Queue and review effect | Independent state |
| --- | --- | --- |
| Try next | Add at queue end; duplicate add reveals existing entry. Move out of Later if present. | Does not fabricate a new discovery or reset prior explored history; Favorite unchanged. |
| Save for later | Move out of Try next into Later; no scheduled reminder. | Prior exploration and Favorite unchanged. |
| Mark explored | Set user-declared exploration time and remove from Try next/Later in one undoable operation. Confirm this effect in action help/batch preview. | Never changes DAW/reference evidence, discovery date or Favorite. |
| Dismiss from new | Dismiss the discovery event from the New view. | Preserve explicit Try next/Later membership, metadata and Favorite. |
| Undo | Restore all fields/order changed by the last manual operation. | Does not undo a filesystem scan or alter source files. |

New to explore excludes explored/dismissed events by default but can show them through a status filter; queued/deferred items retain visible status. No automatic expiry or view-count-as-review behavior. A later user can deliberately queue a previously explored library again.

For metadata, removing an effective inferred/inherited value creates a subject+facet+normalized-value suppression across lower-priority assertions, including subsequent scans. Rejecting one suggestion can instead reject only that source assertion; the editor must distinguish those operations. Raw source evidence remains inspectable. A user-added value can explicitly override/reset suppression. Global vocabulary changes must not rewrite vendor facts.

Queue identity should use a proven logical product plus edition; optional target is a proven instrument ID. Distinct installations remain selectable locations under that entry only when equivalence is established. Unknown/mixed or ambiguous installs stay separate until reconciliation; do not transfer edits/queue membership by shortened name. Migration and reconciliation must preserve or surface unresolved user state, never silently discard it.

## Implementation and validation sequence

1. Repair scope/baseline and missing-adapter-diagnostic defects; establish event semantics before adding New badges.
2. Add durable assertions and user overrides/suppressions; preserve raw vendor values. Implement the first small taxonomy with the named vendors rather than universal inference.
3. Add facet search and a shared metadata editor, including bulk mixed values and Undo. Verify same-name products, internal articulation capabilities and partial installs.
4. Add New to explore and explicit Try next / Later / Explored states on the same collection model; no second independent catalog UI.
5. Measure with representative composers before claiming these are “most searched” fields. Test with their own vocabulary, a forgotten acquisition and a sound they know they own. Avoid prompting the answer with our tag names.

Suggested formative study: 6–8 target composers, covering the named vendors and orchestral/hybrid work. Ask each to supply 8–10 recent natural-language retrieval questions before seeing the UI. Code queries into intent dimensions, report raw counts for this small sample, observe task success/time/false matches and correction needs. It is qualitative prioritization, not population statistics. Collect only consented, redacted examples; no silent telemetry or uploads of project/library paths.

Proposed acceptance targets for that prototype: at least 8 of 10 seeded retrieval tasks per participant without help; no false installed-instrument claim in the curated capability fixture; every participant can distinguish newly found from purchased and explored from used; baseline/new-root/reconnect/update fixtures produce the declared labels. These targets are proposed test criteria, not completed results. Performance requires end-to-end measurements, not the current pure projection benchmark.

Full interaction, state, accessibility and persistence policies: [acquisitions design](acquisitions-design.md). Vendor field evidence: [metadata research](metadata-research.md). Current implementation limitations and remediation priorities: [audit](REPORT.md).
