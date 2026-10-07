# Reviewed product tag sources

2026-09-26. Researcher: independent Codex `asset_priority_design`. Implementation:
Codex coordinator. Six official HTTPS endpoints returned HTTP200 during research;
the product client must separately pass `product-tag-sources` before admission.

This is deliberately limited product-level coverage. Exact maker/name matching
retains editions and distinguishes Cinematic Studio Strings from Cinematic Strings2.
No fuzzy matching, website content installation claims or patch inheritance. Store
merchandising tags and publication dates are never musical tags or installation dates.

| Product | Official source / extraction | Reviewed suggestions |
| --- | --- | --- |
| Spitfire Symphony Orchestra | [Product JSON](https://www.spitfireaudio.com/products/spitfire-symphony-orchestra.json), product.title/body_html | strings, brass, woodwinds, harp, piano, percussion; ensemble |
| BBC Symphony Orchestra Core | [Product JSON](https://www.spitfireaudio.com/products/bbc-symphony-orchestra-core.json), product.title/body_html | strings, brass, woodwinds, percussion; no Discover/Professional capabilities transferred |
| Berlin Strings | [Product page](https://www.orchestraltools.com/berlin-strings), unique Product JSON-LD name/description | strings, ensemble, legato |
| Cinematic Studio Strings | [Official WordPress excerpt](https://cinematicstudioseries.com/wp-json/wp/v2/pages/68?_fields=id,slug,link,title,excerpt), title.rendered/excerpt.rendered | strings; excerpt names no particular articulations |
| Cinematic Strings2 | [Official WordPress excerpt](https://cinematicstudioseries.com/wp-json/wp/v2/pages/900?_fields=id,slug,link,title,excerpt), title.rendered/excerpt.rendered | strings, warm |
| FabFilter Pro-Q4 | [Product page](https://www.fabfilter.com/products/pro-q-4-equalizer-plug-in), title and raw meta name=description | equalizer/EQ function; advertised formats are not installed formats |

Descriptors in ProductTagSources.swift retain only source URLs, exact identities,
reviewed taxonomy and SHA256 description fingerprints. Normalize extracted strings
by collapsing Unicode whitespace to one ASCII space; preserve case/HTML/entities.
Runtime accepts only the reviewed fingerprint. Different or ambiguous identity,
changed/negated/related-product content and unsupported schemas need source review.
No full copyrighted page is bundled or cached. Valhalla returned403 and is omitted.

Client bounds:2MiB decompressed body,15-second request/30-second resource timeout,
ephemeral session, no cookies/credential storage, no redirects. Only the static
reviewed sources are reachable from the UI. Finite snapshot queue, each source once,
continues after failures; fresh7-day cache hits require no request. Failed fetch
retains dated prior suggestions. Source updates require reviewed app descriptors;
this does not claim automatic understanding of arbitrary vendor prose.

Specification critique initially rejected free-form keyword extraction and a
starvation-prone20-item cap. Revised fingerprint admission and finite complete queue
passed independent Codex critique. Claude cross-client fallback remained unavailable
because the CLI was not logged in. Actual four-host last-used remains unimplemented.

Runtime diagnosis: Orchestral Tools redirects its former /store/collections route to /berlin-strings. The descriptor uses the verified canonical200 endpoint; redirect rejection remains enabled.

## Reviewed structured records (catalog version 2)

The bundled source catalog is a versioned set of exact identities and validated taxonomy
records. Each record carries its stable record ID, review date, taxonomy version, canonical
HTTPS product page, and (for refreshable records) an extraction format plus fixed content
digest. Seven additional product-fact groups (eight exact identity records, including the distinct Glade Studio name) were reviewed on 2026-10-04 and are bundled offline
(`networkEnabled: false`):

| Record | Official product evidence | Bundled suggestions |
| --- | --- | --- |
| `8dio-rhythmic-aura-vol-1` | [8Dio Rhythmic Aura](https://8dio.com/products/the-new-rhythmic-aura-1-for-kontakt-vst-au-aax-samples) | arpeggiator, sound design, texture |
| `audio-imperia-glade` | [Audio Imperia Glade](https://www.audioimperia.com/product/glade/) | strings, woodwinds, percussion, choir; ensemble; sound design, texture |
| `audio-imperia-glade-studio` | [Audio Imperia Glade](https://www.audioimperia.com/product/glade/) | same reviewed product-level role facts; exact edition identity retained |
| `audio-imperia-nucleus-lite` | [Audio Imperia Nucleus Lite Edition](https://www.audioimperia.com/product/nucleus-lite-edition/) | strings, brass, woodwinds, percussion; ensemble |
| `native-instruments-straylight` | [Native Instruments Straylight](https://www.native-instruments.com/products/straylight) plus the official manual reviewed in the source audit | synth, granular synthesis, sound design, texture, evolving |
| `plugin-alliance-bx-glue` | [Plugin Alliance bx_glue](https://www.plugin-alliance.com/products/bx_glue) | bus compressor, compressor, VCA |
| `plugin-alliance-bx-digital-v3` | [Plugin Alliance bx_digital V3](https://www.plugin-alliance.com/products/bx_digital-v3) | equalizer, EQ |
| `softube-chandler-curve-bender` | [Softube Chandler Limited Curve Bender](https://www.softube.com/uk/plug-ins/chandler-limited-curve-bender) | equalizer, EQ, mastering, mid-side |

These records are offline because the review is of the structured facts above, rather than a
runtime interpretation of vendor prose. The ordinary network cache remains available for
the earlier digest-checked sources. Cache format/TTL and fetch policy remain separate
from the versioned bundled catalog. Exact local Native Instruments vendor-browser
categories and instrument facts remain the primary patch-level facts; patch names do not
become parent product claims. Explicit overrides, including clearing a field, dominate
all suggestions. For products with reviewed `synth` classification, lexical instrument
family guesses are suppressed while non-family local facts remain available.

All 100 reviewed records live in the bounded `product-tag-catalog-v2.json` resource and
are decoded through a schema-versioned importer before they enter the same exact-match
source registry. Changing review facts requires a catalog-version update and review; it
does not widen network access. Network refresh remains limited to the original
fixed-digest source records and uses `ProductTagStore`'s existing cache, TTL and failure
cooldown. The reviewed resource is imported from the app bundle. Opt-in shared records
pass the same bounded validator; automatic suggestions require an exact trusted maker
and an official domain already established by curated records. Local paths and arbitrary
vendor pages are not accepted. Automatic provenance stays distinct from curated review,
and user edits, including intentionally cleared fields, retain precedence.

The 2026-10-06 starter expansion adds 86 conservative offline records while preserving
the previous 14 source identities: 100 distinct products in total, evenly split between
plugins and libraries. Each added record stores its official product page and a concise
`sourceFact` for review. Exact edition/name and maker evidence is required; a source page
is never an installed-item inventory. Previously verified `com.fabfilter` manufacturer
namespace can qualify new FabFilter records when the exact product name also matches;
unverified plug-in namespaces remain absent. A bounded, normalized kind/name index
narrows matching candidates without weakening the maker or bundle checks.

## Installed VST3 categories

The VST3 SDK documents `moduleinfo.json` as JSON5, with the modern descriptor at
`Contents/Resources/moduleinfo.json` and an older layout at `Contents/moduleinfo.json`.
The reader uses Foundation's native `JSONSerialization.ReadingOptions.json5Allowed`,
reads at most 1 MiB from a safe regular file, and never loads the plugin binary. Only
`Audio Module Class` entries contribute. Where a bundle has multiple audio classes,
the product receives only the intersection of recognized `Sub Categories`; the
reader does not combine sibling-only classifications. Exact SDK categories are kept
literal in the existing musical facets (`Dynamics` stays `dynamics`, `Instrument`
stays generic `instrument`, and `Synth` stays `synth`). Unknown custom values and
controller classes do not add tags.

The optional vendor fact object is cached inside the existing plugin asset payload.
Restore and scan refresh it off the main actor. If moduleinfo is missing or the bundle
is unavailable, the last validated cached facts remain available; a readable malformed
descriptor or unsafe path clears the facts. Explicit user edits, including empty
facet values, override reviewed product metadata, which overrides exact VST3 facts,
which override name-based suggestions. The tag inspector reports the VST3 source and
shared-class policy. On this machine, a read-only census found categories on 406 of
408 audio classes; product coverage increased from 138/1,225 to 438/1,225, with 300
previously untagged products gaining categories across 331 products with VST3 facts.

Reference: [Steinberg VST Module Architecture — ModuleInfo JSON](https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical%2BDocumentation/VST%2BModule%2BArchitecture/ModuleInfo-JSON.html).
