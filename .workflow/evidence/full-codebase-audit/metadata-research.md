# Composer search metadata: vendor evidence and proposed taxonomy

Researcher: independent Codex metadata reviewer. Researched 2026-09-25 Pacific.
Scope: official catalog/manual comparison; proposed schema and query behavior, not implementation. No product edits. High confidence describes documented vendor fields; proposed composer queries remain hypotheses until task testing. Public manuals do not establish permission or technical ability to extract the same fields from local proprietary formats.

Audience update: the user explicitly identified Spitfire Audio, Orchestral Tools, and Cinematic Strings users as the primary audience. Orchestral retrieval therefore sets the default facet priority. Synth, beat-production, and mixing examples below are secondary extensibility evidence, not competing defaults.

## Observed catalog structures

| Comparator and primary source | Observation | Proposed implication |
| --- | --- | --- |
| [Kontakt browser](https://docs.native-instruments.com/ni-tech-manuals/kontakt-manual/en/browser-and-presets) | Distinguishes maker/product, hierarchical sound types, independent character, preset identity, and user content. | Keep identity separate from musical descriptors; support user authority over classification. |
| [Orchestral Tools Metropolis Ark 1 notes](https://orchestraltools.helpscoutdocs.com/article/371-metropolis-ark-1-notes) | Instrument tables distinguish ensemble composition, register, techniques, range, dynamics, round robins, and microphone information. Low Strings includes cellos and basses; marcato can be long or short. | Represent instrumentation, playing technique, and length separately; preserve detailed vendor names. |
| [Spitfire Symphony Orchestra](https://www.spitfireaudio.com/products/spitfire-symphony-orchestra) | Catalog separates sections/soloists, techniques, and microphone positions. | Solo versus section and recording perspective are meaningful dimensions; a product capability is not proof every patch has it. |
| [Cinematic Studio Strings](https://cinematicstudioseries.com/strings/) | CSS combines a compact patch list with keyswitch/CC-controlled articulations; documented techniques include legato, spiccato, harmonics, and con sordino. | Search articulation capabilities inside a patch; do not fabricate one instrument/file per technique. |
| [Cinematic Strings 2](https://cinematicstudioseries.com/cs2/) and [official CS2/CSS distinction](https://cinematicseries.zendesk.com/hc/en-us/articles/206359724-What-is-the-difference-between-Cinematic-Strings-2-CS2-and-Cinematic-Studio-Strings-CSS) | CS2 is the earlier concert-hall library; CSS is a separate scoring-stage library. Both expose multiple articulations through their interface. | CS2 and CSS need distinct product identities and scoped aliases; similar names and one developer do not establish equivalence. |
| [VSL Synchron Brass](https://www.vsl.co.at/instruments/synchron/brass) | Distinguishes ensemble sizes, low-brass lineups, staccato/portato, attack variants, dynamics, and tempo-specific repetitions. Some lineups lack techniques that other lineups offer. | Apply capabilities at the specific instrument/variant level; avoid inheriting the product's complete technique list. |
| [Omnisphere browser filters](https://support.spectrasonics.net/manual/Omnisphere/browser/operation/page04.html) | Attribute columns change with sound category: a sound source can use source/timbre, while voices use technique-related attributes. Attribute browsing and filesystem browsing are distinct. | Use contextual facets over one extensible model, not identical visible fields for every asset. |
| [Arturia Pigments 5 manual](https://dl.arturia.net/products/pigments/manual/pigments_Manual_5_0_0_EN.pdf) | Preset browser includes type/designer plus genres, styles, and characteristics. This is a version-pinned historical comparator. | Synth role, creator, stylistic context, and sonic character should be independently searchable. |
| [Heavyocity Damage 2](https://heavyocity.com/products/damage-2) and [official upgrade description](https://heavyocity.shop/products/upgrade-damage-2) | Kit and loop design are different content uses; loops include organic/hybrid/processed profiles and straight/triplet rhythm. | Cinematic percussion needs role, phrase/one-shot distinction, processing character, and rhythm—not only instrument names. |
| [Splice finding sounds](https://support.splice.com/en/articles/8652594-finding-sounds) | Exposes sample/preset, loop/one-shot, tempo, musical key, instrument, genre, and provider. | Loose-sample music metadata is distinct from file extension and byte size. |
| [FabFilter processing modes](https://prod.fabfilter.com/help/pro-q/using/processingmode) | Processing mode affects operational properties; zero-latency operation and linear-phase behavior are explicitly distinct. | Plugin function, latency, and resource requirements are separate dimensions with configuration-dependent evidence. |
| [Valhalla VintageVerb](https://valhalladsp.com/shop/reverb/valhalla-vintage-verb/) | Reverb algorithms and color modes describe different aspects of one effect product. | Effect family, algorithm/style, and preset character should not collapse into one tag. |

The first-priority retrieval corpus should contain Spitfire, OT, and Cinematic Strings products, with orchestral articulations, sections, register, player, and maker/library context. The broader comparators test schema extensibility. Selection is purposeful coverage, not a ranking of installed popularity.

## Composer-first defaults

Prioritize instrument/family, section or solo/ensemble, articulation capability, register, maker/library, and player. Put recording perspective, character, dynamics, and notes in secondary facets/details as evidence allows. Keep recently indexed and storage/usage views available for the user's other two jobs. BPM, genre, synth engine, and effect processing should appear for relevant asset types rather than occupy the default orchestral workflow.

An instrument record should support `capabilities[]` with source and applicability. A multi-articulation NKI remains one installed instrument whose capabilities can include several techniques; searching a technique returns that patch with a matching-capability explanation. Only independently discovered patches become separate instrument rows. A source-supported internal articulation may be shown as a capability/subitem, never as a separately removable file or independently proven usage event. A product's advertised capabilities alone do not prove a particular local patch/version implements every one.

The official CS2/CSS comparison establishes that they are different libraries, not alternate spellings. Proposed aliases: `CS2` → Cinematic Strings 2; `CSS` → Cinematic Studio Strings, scoped to recognized product identity. A vague query for “Cinematic Strings” can show both as clearly labeled results rather than silently choose or merge them. Vendor marketing pages also contain stale/copy inconsistencies; no installation-size or minimum-version assertion is imported here.

## Proposed shared fields and extensions

**Shared identity:** stable local ID; vendor ID where proven; asset kind; canonical title; preserved vendor title; aliases; maker/developer; product, edition and version; containing pack/bank/library; player requirement; installed location and availability. Store observations such as first indexed and last observed separately from purchase, release, and installation dates. Those dates have different meanings.

**Shared user layer:** favorite, custom tags, notes, user collections, corrected name/classification, explicit rejection of an inferred tag. Keep source assertions and user decisions separately so rescanning cannot erase corrections. Search should explain why an item matched and whether a descriptor is vendor-supplied, user-supplied, or inferred.

**Shared musical dimensions, when meaningful:** instrument family and instrument; musical role; sonic character; genre/style; acoustic/electric/synthetic/hybrid source. Multi-valued fields are necessary. A hybrid percussion sound can have both acoustic sources and substantial processing. Absence of a value means unknown, not a negative assertion.

**Libraries and instruments:** ensemble makeup and size; solo/section/tutti; register; playable range; articulation/technique; attack/length; dynamic behavior; phrase versus playable instrument; recorded tempo where relevant; mic/perspective; recording space; required player/version. Product coverage, installed coverage, and individual patch capabilities remain separate. Articulations may be internal options in one patch rather than child files.

**Loose samples:** loop/one-shot/phrase; instrument and musical role; BPM or interval plus confidence; key tonic and mode plus confidence; duration; channels; sample rate and bit depth; pack/provider; original versus transformed derivative. Tonality may be unknown or not applicable. An unpitched hit should not receive a guessed musical key merely to fill a column.

**Plugins:** instrument/effect/MIDI/utility role; effect family and supported functions; installed formats/architectures and versions; player versus sound generator; preset-bank association. Optional evidence can describe latency/oversampling modes, surround layouts, and resource observations. An effect plugin's installed size is not its CPU use, and a vendor's qualitative efficiency claim is not a comparable measurement.

## Terminology mapping without flattening meaning

| Vendor/query wording | Proposed mapping | Boundary |
| --- | --- | --- |
| NI Sound Type; Arturia Type; Omnisphere Category | `sound_type`, with narrower instrument/role fields | These taxonomies overlap; retain vendor namespace and original value. |
| NI Character; Arturia Characteristics; Omnisphere Timbre | `character` assertions | Warm, dark, airy, and bright are subjective; do not manufacture synonyms as facts. |
| Longs / sustains / long notes | Broad sustained behavior, plus exact technique | Legato may additionally encode transitions; it is not interchangeable with sustain. |
| Shorts / staccato / spiccato / marcato short | A broad short-behavior query can expand to supported techniques | Spiccato and staccato remain different; plain marcato does not imply short. |
| Celli / cellos; Ark II / Ark 2 | Scoped lexical aliases | Do not merge Ark 2 and Ark 3, editions, players, or separate installations. |
| Low brass | Register + family, optionally explicit vendor ensemble | A multi-instrument patch differs from a matching solo tuba. Show result kind. |
| Organic / hybrid / damaged | Source and processing descriptors | Preserve marketing language as attributed tags, not a scientific classification. |

## Search cases to validate with composers

- **“warm strings”**: instrument/family constraint plus character assertion within the chosen collection. In the primary Libraries workflow, present orchestral matches with section/library context; any broader synth results need a clear result kind. Show missing character coverage rather than treating untagged strings as cold.
- **“CSS con sordino”**: resolve the supported CSS alias to Cinematic Studio Strings, then match the capability on the installed patch. Keep legacy CS2 separate; do not create a fictitious con-sordino NKI or infer patch-level use from a Kontakt instance.
- **“short low brass”**: brass family, low register, short behavior; expand through supported technique mappings. Keep individual patch evidence distinct from a library whose marketing mentions these capabilities. Explain which technique matched.
- **“accordion Kontakt”**: instrument identity plus player requirement. A concrete accordion patch is a stronger result than a library-level description. A Kontakt plugin installation alone is not a result proving accordion ownership.
- **“CPU-light reverb”**: effect family plus user resource preference. Without compatible local measurements, show known reverbs and explicitly unknown resource evidence, or user-tagged favorites. Any benchmark must identify machine, host, plugin version, sample rate, buffer, channel layout, preset and processing mode; do not silently execute plugins during indexing.
- **“the new library from last week”**: recent first indexing after a completed baseline, with maker/player refinement. Do not relabel a cached baseline or website release date as installed last week.

These are proposed task scenarios, not measured rankings of composer search demand. Start with plain text plus visible facets and aliases; natural-language parsing should expose interpreted constraints and permit correction.

## Acquisition, provenance, and priority

1. Implement durable user metadata and source assertions first: subject ID, field, raw/normalized value, source kind/reference, confidence, observed time, adapter/version, and user accept/reject/replace state. Inherit identity context such as maker/product/player; aggregate child capabilities for library search without pushing them onto siblings.
2. Populate verified local manifest fields and user edits. Add bounded audio-header inspection for objective sample properties. Filename parsing is a proposed assertion, not authoritative metadata. Preserve unrecognized vendor tags instead of discarding everything outside a small whitelist.
3. Add adapter-specific mappings backed by fixtures. Public product catalogs can enrich an identified product through optional lookup, but cannot prove the particular local instrument/mic is installed. Keep lookup provenance, version applicability, and offline behavior explicit.
4. Validate first with orchestral composers using Spitfire, OT, and Cinematic Strings, including CS2/CSS coexistence and multi-articulation patches. Ask participants to retrieve forgotten real items and describe them before showing a prepared taxonomy; prioritize observed task success, correction rate, and missing metadata over raw tag counts. Broader production cohorts are later checks of extensibility.

## Market-evidence limits

[KVR's awards methodology](https://www.kvraudio.com/readers-choice-awards/) describes self-selected member voting. It can select recognizable product families for research; it cannot establish market share or composer query frequency. [Splice's trends report](https://splice.com/trends) and [MIDiA's Sounds of 2025](https://www.midiaresearch.com/sounds-of-2025) describe platform-specific demand signals. They support eventual production/genre extensibility, but do not override the user's explicit orchestral audience or establish its query priorities. Root's market synthesis covers the current award/report corpus in more detail.

Confidence is high that these dimensions exist in real vendor products; medium that the proposed normalization transfers well across them; unvalidated for facet priority, default UI density, automatic extraction completeness, and the distribution of composer queries.
