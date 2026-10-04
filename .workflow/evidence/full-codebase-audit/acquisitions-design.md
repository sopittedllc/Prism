# Composer discovery and New to explore

Status: **PROPOSED / UNVALIDATED**. Codex ux-architect lens; research and design only, 2026-09-25. No implementation, usability validation, popularity ranking, or accessibility certification. Specification-critic review remains required before implementation. Target: existing macOS AppKit collection. Confirmed primary audience: Film/TV/game composers using orchestral and hybrid libraries, including Spitfire, Orchestral Tools and Cinematic Strings. Proposed implementation domains: `ui-ux` and `stateful-feature`; no implementation/runtime gate is certified by this document.

## Evidence and limits

These are shipped product patterns documented by their vendors, not evidence of how often composers use a field or which products sell most. Research did not obtain representative search logs or installation market share. Vendor marketing such as “flagship” is not popularity evidence.

| Comparable workflow | Observed interaction, hierarchy and states | Transfer and limit |
| --- | --- | --- |
| Kontakt: composer locates an instrument preset | Search combines preset/product/bank and musical tags; filters include brand, sound type and character. Favorites combine with other filters. Factory and user content are distinguished. Its “New Instruments for you” surface is unowned product suggestions. | Transfer musical facets and composable favorites. Do not copy commerce suggestions into an owned-collection view. Documentation does not certify accessibility or establish search frequency. [Official browser manual](https://docs.native-instruments.com/ni-tech-manuals/kontakt-manual/en/browser-and-presets). |
| Sononym: producer classifies and retrieves local samples | Manual and automatic tags are distinct; hierarchy includes aliases; multiple tags support narrowing or widening. Removing an auto-assignment suppresses its return during refresh. Tag editor supports keyboard entry and multi-selection. Favorites can be sorted by date added. | Transfer provenance, aliases and durable suppression, plus intentional rediscovery. Filename inference can be ambiguous; its documentation explicitly discusses “kick” across instrument and foley domains. Accessibility beyond documented shortcuts is unverified. [Tagging](https://www.sononym.net/docs/manual/tags/), [Favorites](https://www.sononym.net/docs/manual/favorites/). |
| Splice: producer narrows sample results and downloads owned sounds | Search accepts filenames/keywords; filters distinguish loop/one-shot, instrument, genre, BPM and key. Licensed samples and locally downloaded samples are separate states; download can happen later or into a browser download folder. | Transfer asset-specific facets and ownership-versus-availability distinction. Splice's popularity ordering reflects its catalog, not local composer preferences or worldwide product share. No assumption that filesystem creation equals purchase date. [Finding sounds](https://support.splice.com/en/articles/8652594-finding-sounds), [Downloading sounds](https://support.splice.com/en/articles/8652591-downloading-sounds). |

Apple recommends communicating search scope with titles/placeholders and supporting scoped filtering where useful. Apply that guidance to category and collection filters, retaining an obvious reset path. [Apple Searching HIG](https://developer.apple.com/design/human-interface-guidelines/searching).

Orchestral vendor catalogs support a technique dimension: Berlin's series distinguishes orchestral sections and articulations; Spitfire Symphony Orchestra describes solo/ensemble and named techniques. These justify representing those distinctions, not claiming their frequency among users. [Berlin series](https://www.orchestraltools.com/berlin-series), [Spitfire Symphony Orchestra](https://www.spitfireaudio.com/products/spitfire-symphony-orchestra).

## Job and existing composition

Trigger: a composer has a musical need or remembers acquiring something but not its name. Success: find a relevant owned instrument with its parent and availability, or see genuinely newly detected content and intentionally save it for exploration.

Current category sidebar, outline, search, sort and inspector remain the governing shell. Tags are currently read-only; no recent-addition route exists. Source setup, source-specific baselines, stored first/last observation, stale identities, and plugin format groups must feed the same discovery model. Included consumers: three category views, search, inspector, metadata editor, source-change notices, saved catalog restore and scan completion. Excluded: sales recommendations, remote accounts, automatic plugin loading, DAW control, removal authorization, online sound inference and notifications outside the app.

## Metadata priorities: hypotheses to test

| Priority | Fields and examples | Semantics |
| --- | --- | --- |
| First | Instrument/family: accordion, bass clarinet, low strings, frame drum; maker; product/library; player; user tags/notes | Directly supports the user's named job. Instrument families are hierarchical; a family query includes descendants. Product and instrument remain distinct. |
| First for libraries | Technique/articulation: legato, pizzicato, tremolo; solo/ensemble and section size; register: low/mid/high; acoustic/synthetic/hybrid; musical role: pulse, pad, texture, ostinato, impact; character: intimate, dark, bright, evolving | Prioritize these composer descriptors over genre and tempo. Store structured facets where supported, flexible user labels otherwise. Register is contextual rather than a universal MIDI boundary. Do not infer every patch supports an articulation from a library marketing page. |
| First for samples | Instrument/type; loop/one-shot; duration; BPM/key when known; pack/source | Tempo/key are nullable, with source and confidence; unknown is not zero. These fields are not compulsory for library products or effects plugins. |
| First for plugins | Instrument/effect and function: synth, sampler, EQ, dynamics, reverb, delay, saturation; maker; format/version | Function may be multi-valued; manufacturer identity is distinct from bundle identifier. Player is not evidence of installed library contents. |
| Second | Genre/style; recording context and microphone/mix options; extended character vocabulary | Subjective character stays user-correctable. “Dark strings” is useful vocabulary, not a validated universal taxonomy. Recording options need adapter evidence. BPM/key remain optional contextual filters for loops and relevant samples, not required library-level fields. |
| Operational, separate | Availability, storage measurement, newly detected date, manually entered acquisition date, saved-project evidence | Never collapse these into musical tags or a single “last used” date. |

Proposed query behavior: tokenized multi-term matching rather than one literal phrase; AND between selected dimensions, OR among values inside a dimension, explicitly labeled. Example composer tasks: accordion → library/instrument results; strings + legato + solo; dark + pulse; reverb + plate; loops + percussion + 90–110 BPM. These are test scenarios, not frequency claims. Search human aliases (e.g. cello/violoncello) while preserving vendor titles. Do not merge culturally distinct instruments as synonyms without curated justification.

Metadata layers: observed/vendor facts; inferred suggestions; inherited context; explicit user overrides and suppressions. Display source on demand. User edits win and survive scans; inheritance must not leak sibling articulations. Batch editor shows mixed values, explicit Add/Remove/Replace, reviewed scope count, Cancel and Undo. Product-level context may inherit; patch-specific technique may not automatically promote to every child. No network lookup until an explicit, reviewable optional action.

## Proposed flow: New to explore

Add one small collection route, **New to explore**, alongside the category routes; reuse the collection and inspector rather than add a dashboard. It contains new detection batches awaiting a user disposition. Category chips constrain this route; ordinary category searches can use the same New to explore filter. Keep one shared query/filter state model, not independently implemented screens.

Use a quiet text/count badge for newly found products only, not animation, sound, a Dock badge or notifications. Accessibility name: “New to explore, 3 newly found products”; expose count/state through native semantics and announce changes once after a completed scan. If content is merely newly indexed or updated, use those explicit labels in the review list; do not combine those counts under New. Favor one row/card per library or plugin product; patches and formats are subordinate details, preventing a large library from flooding the queue.

1. First successful baseline: show “Collection indexed”; no enormous New badge. Optional “Choose something to explore” lets users intentionally queue existing items.
2. Later complete scan of previously covered scope: quiet summary, e.g. “3 libraries and 1 plugin newly found · Review”. No claim of acquisition or installation date. Partial/error scans do not imply complete discovery.
3. Review groups by scan batch/date, then product or sample pack/folder. One library with 2,000 patches is one top-level discovery; expanding shows newly indexed instruments. Multiple plugin formats are one product discovery.
4. Row identity, maker/player, meaningful instrument/type tags, observed date and offline/uncertain state take precedence over repeated Unknown usage columns. **Try next** adds a library/product to an ordered, user-managed exploration queue, with one product/library per row and optionally a supported, indexed instrument. The first row can be highlighted as the next writing-session choice; there is no single-item limit or forced replacement. Adding a product already queued reveals its existing row instead of duplicating it. Users can reorder with pointer or named Move up/Move down actions, remove an entry, or clear the queue with Undo. It is an explicit intention, not a scheduled action: no calendar, reminder subscription, playback or automatic plugin opening. Each row offers **Show location** and **Copy instrument name** (Copy library name when no patch is chosen). Missing/offline patches retain queue position and explain availability; the app never substitutes another patch silently.
5. Explicit actions: **Mark explored**, **Save for later**, **Favorite**. Selecting, queueing Try next, copying a name, opening details or using Finder does not mark explored. Mark explored means manually declared “I tried/explored this,” not proven DAW use or project inclusion; an inspector shows “Marked explored by you” and date separately from usage evidence. Do not add a second equivalent Tried toggle. Favorite is independent of exploration status. Later is an explicit saved collection without nagging reminders. All are reversible. A player/preview route may be added only after its supported formats and actual behavior are independently verified.

### Newness rules

| Event | Presentation |
| --- | --- |
| Initial baseline or newly added source root | Newly indexed existing collection, excluded from new-acquisition implication by default. |
| New identity after established baseline | Newly found on date; acquisition date unknown unless user explicitly supplies it or a trusted source proves it. |
| Drive reconnect / restored path / same known identity | Available again, not new. Preserve exploration state. |
| Existing product update / additional format | Updated installation or additional format, not new product. New instruments may be identified within that product. |
| Replaced metadata anchor / uncertain identity | Needs reconciliation; do not quietly duplicate or transfer user metadata. |
| Partial scan, denied source, interrupted scan | Coverage incomplete; retain previous collection. Do not claim absence, new complete baseline, or unused status. |
| Migration from current catalog | Seed baseline from known observations. Unknown historical dates remain unknown. Never mark all migrated rows newly acquired. |

## Interaction states and accessibility

Empty: “No new finds since your last complete scan,” with Scan and saved exploration access. Loading: preserve results and focus; announce scan completion once. Ready: grouped counts and explicit filter scope. Offline: retain records and disable actions requiring a file with reason text. Error: explain which source/storage action failed with retry; no silent loss of exploration edits. Successful mark: update status in place with Undo; move focus to next row only if the active filter removes the item. Cancelled batch edits leave state untouched. Undo must restore previous selection where possible.

Use named native controls and menus; actions available without hover and without drag. Command-F focuses search; Tab reaches filters/list/inspector/actions; arrows operate groups. Announce result count after debounced search, not every character; statuses expose names/values, not just star color. Sheet dismissal restores invoking row/control. Batch mixed state must be spoken, not only dotted styling.

At current 1040×680 minimum, collapse lower-priority columns before shortening product identity or disambiguating roots; make inspector collapsible/adjustable. Typical 1220×780 and larger retain shared hierarchy. Test long translated strings, RTL, largest supported text size, increased contrast and reduced motion. No celebratory animation or gamified deadlines; native focus and status text suffice. Numerical contrast/performance requirements require measured acceptance budgets before implementation.

## Cross-cutting policy for proposed state

Stable registry IDs required before code: discovery event/baseline fields, metadata override/suppression, exploration status and timestamp, favorite, manual acquisition date plus provenance, and `discovery.try_next` containing ordered queue entries with logical library/product ID plus optional supported instrument ID. Queue membership and order are user state; each product appears at most once. Try next defaults to an empty array; source scans, restarts and filter resets retain entries/order; explicit Remove or Clear is undoable. Event IDs and user-state IDs must survive labels changing. Each binds to stable physical/logical identity with explicit unresolved mapping; source paths alone are insufficient. The policies below include Try next, whose selected patches must also survive offline states without false identity reassignment. Queue membership/order neither affects nor derives from DAW usage, and produces no telemetry.

- Persistence: local catalog, transactional writes. Excluded from audio presets and DAW project persistence because these describe the user's collection.
- Defaults/reset: baseline items unmarked, favorite false, acquisition date nil; normal filter/reset and rescans retain user edits. Explicit reset of a user field is undoable; no silent bulk metadata wipe.
- Migration: versioned pure migrations, backup and rollback; existing schema fixture; older data does not fabricate exploration/acquisition. Unknown/newer schema preserves database and offers recovery.
- Undo: all manual classification/status/favorite/date edits, including batch. Derived scan observations are not user edits and are not undone by metadata Undo.
- Automation: no external mutation API or DAW parameter automation in this phase; excluded deliberately. Registry/roundtrip tests remain mandatory.
- Copy/paste: copy visible names/tags; batch tag paste only via explicit metadata editor with preview. Files remain untouched. Exploration/event history not implicitly pasted.
- Sync: excluded; local-only phase, no accounts. Future sync needs conflict resolution for overrides and suppressions.
- Accessibility: labels, enum values, mixed states and actions in native accessibility tree; complete artifact-only workflow required.
- Privacy/analytics: local provenance and timestamps; no outbound paths or telemetry. Optional future enrichment requires reviewed inputs and source recording.
- Export/import: consistent database backup includes state. No ad hoc CSV merge/import in this phase; explicit future interchange schema needed. User-visible export must disclose local paths.

## Validation and governing work

Before implementation: independent specification critique; registry completeness and semantics review; validate product-level grouping and root/baseline identity foundations. Update design-system authorities for facet chips, source indicators, metadata editor and exploration states together. Do not certify this proposal as a completed UI research or accessibility gate.

Automated cases: baseline versus new versus reconnect versus update; overlapping/new roots; moved file and replaced anchor; product with multiple formats; library with thousands of patches; failed/cancelled scan; migration; cached reopen; edits/undo after rescan; multi-term/alias searches with false-positive counterexamples. Runtime: keyboard-only and VoiceOver through query → edit → save for later → reopen → mark explored → undo; minimum/typical/wide, light/dark/high contrast and long-name screenshots; representative credible collection latency/memory measurements.

User research proposal: recruit Film/TV/game composers with orchestral and hybrid workflows, including Spitfire, Orchestral Tools and Cinematic Strings collections; ask them to find a forgotten recent acquisition and a sound described musically using their own vocabulary, then queue and prioritize libraries to try next. Record completion, time, false positives, missed results and corrections with consent. Compare this proposed field ordering against observed behavior before claiming “most searched.” Test that every participant can explain newly found versus newly indexed versus updated versus purchased, queued versus explored versus used, and favorite versus safe to remove. Verify that Try next membership/order/optional patches survive restart, offline volume, rename, reordering/removal/clear and Undo; adding a duplicate reveals its row; neither selecting nor revealing it marks it explored. No fixed market-wide popularity conclusion follows from this small formative study.
