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
