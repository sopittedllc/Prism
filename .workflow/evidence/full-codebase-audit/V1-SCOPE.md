# Composer discovery: revised v1 scope

2026-09-25. User-directed scope revision, recorded by Codex. Planning only; no application changes.

This decision supersedes the field priorities and exploration workflow in `COMPOSER-DISCOVERY.md` and `acquisitions-design.md`. Those documents and their reviews remain historical research/proposal evidence; their review results do not certify this revision or an implementation.

## V1

Prioritize musical search and editable metadata for film/TV/game composers using Spitfire, Orchestral Tools and Cinematic Strings:

- Instrument and section.
- Technique/articulation.
- Solo/ensemble and register.
- Character, such as warm, dark, intimate or evolving.
- Musical role, such as ostinato, texture, pulse or impact.
- Contextual sample fields such as loop/one-shot, BPM and key where relevant.

Remove **Library identity** and **Advanced details** from the proposed user-facing metadata/filter groups. Do not add dedicated maker/series/edition/player facets or recording-space, microphone, pitch-range and dynamic-layer fields under this proposal. Existing item names, catalog grouping and internal identity safeguards remain necessary to identify results and preserve edits.

Keep new-acquisition discovery simple: highlight recently found content in the existing collection, with a recent-content filter/sort and an observed date. Group library patches and plugin formats so one acquisition does not produce thousands of top-level new items. No exploration queue or manually tracked exploration status in v1.

Newness must be honest: the initial scan establishes a baseline; a newly added root is newly indexed; a known drive reconnecting is available again; an existing product changing is updated. Only a newly observed item in previously established scope is newly found. Do not infer purchase or installation dates. Scope/baseline repairs identified by audit findings F03/F04 remain prerequisites. Partial scans preserve existing records and communicate incomplete coverage.

Metadata edits and suppressions must survive rescans. Search should explain supported matches without inventing installed articulations from product marketing. Keyboard access, accessible labels, persistence, migration and state validation remain requirements for eventual implementation.

## Bookmarked for v2

**Try next** and **Mark explored** are deferred to v2, together with the related Save for later list, queue ordering, exploration timestamps, dismissal/status workflow and associated Undo behavior. This is a backlog bookmark, not a request to implement bookmarking now.

The original interaction ideas are retained in [acquisitions-design.md](acquisitions-design.md) and the exploration sections of [COMPOSER-DISCOVERY.md](COMPOSER-DISCOVERY.md) for future reconsideration. They are not v1 acceptance criteria. Exploration must remain separate from observed DAW/project usage if implemented later. Deferring this workflow does not automatically defer the rejected Library identity and Advanced details groups into v2.

## Next implementation planning

Plan baseline/scope repairs, durable musical metadata and search, then simple recent-content highlighting. Obtain the required specification review and objective implementation evidence for that scope. Existing audit and prior-proposal reviews remain unchanged historical records; no implementation gate is passed by this revision.
