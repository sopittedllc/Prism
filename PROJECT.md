# Simplify

**Status:** Discovery
**Owner:** TODO
**Primary target:** macOS desktop application; minimum OS and distribution channel TBD.

## Product statement

Simplify is a free, lean audio collection manager supporting Altadena Girls.
Musicians and composers can inventory installed plugins, individual samples, and
instrument libraries, classify them, understand saved-project references, and remove
unwanted content. Charity presentation and donation destination remain to be defined.

## Primary workflow

Two primary jobs govern the interface: reclaim storage from infrequently used content,
and discover recently added content or a specific instrument already in the collection.
Libraries browse as maker → library → instrument, while Individual Samples mirrors the
chosen folder trees. Library footprint belongs to the whole installed library, not each
patch. Tags are inherited with durable editable user overrides. The researched redesign
contract is [.work/active/library-catalog-redesign.md](.work/active/library-catalog-redesign.md);
its proposed implementation remains outstanding.

1. Discover installed plugins and choose one or more sample and library folders,
   including local Splice downloads and external drives.
2. Browse Plugins, Samples, and Libraries; filter by type, maker, player, and location.
3. Sort by referencing-project recency and size. Unknown coverage stays visibly unknown.
4. Review selected files and dependencies before removing unwanted items.
5. Routinely detect additions and offer a batched classification queue, with manual
   tags or optional web-assisted metadata suggestions.

This workflow is the north star for feature and architecture decisions.

## Users and environment

- Primary user: macOS musicians, producers, composers, and audio engineers.
- Skill level: no filesystem or plugin-format expertise required.
- Physical/host environment: major macOS DAWs, standalone players, internal/external storage.
- Typical session length: quick inventory and cleanup; quiet ongoing discovery.
- Worst credible operating conditions: large collections, disconnected drives,
  partial downloads, moved folders, shared content, and older projects depending on assets.

## Non-negotiable constraints

- macOS only; compatibility target covers ten DAW families, with related products
  included, as recorded in [ecosystem research](docs/research/audio-ecosystems.md).
- Logic Pro, Ableton Live, Cubase, and Pro Tools are mandatory primary targets.
  REAPER coverage does not satisfy that requirement. Validate each host separately.
- Usage evidence must cover individual samples and individual library instruments
  (Kontakt NKI and player-specific equivalents), not only plugins or whole libraries.
  Inclusion counts whether or not audio was played. Distinguish saved references,
  observed loads, failed attempts, and unknown history; see
  [activity research](docs/research/daw-activity-history.md).
- Keep scanning incremental and avoid disrupting audio sessions; numerical budgets
  require a measured prototype.
- Distinguish plugin product, installed format, player, library, preset, and loose sample.
- Never present installation or scan time as last used. Project modification time may
  be shown only as an explicitly labeled reference-recency proxy.
- A player reference does not establish inclusion of every library installed for it.
- Offline volumes are unavailable, not deleted; repeated scans preserve user tags.
- Proposed removal default: reviewable move to Trash where supported; never silently
  fall back to permanent deletion. Shared or uncertain ownership requires special handling.
- Local inventory works without web access. Metadata lookup is optional, minimizes
  outbound data, records sources, and never overwrites user tags silently.
- Free product; support for Altadena Girls must not imply an unconfirmed affiliation.

## Architecture boundaries

Discovery, usage observation, classification, and removal are separate capabilities.
Player-specific discovery adapters report evidence and content ownership. A local
catalog presents three simple views without exposing adapter complexity.
These are proposed boundaries, not an implemented architecture; see
[research and feasibility work](docs/research/audio-ecosystems.md).

## Definition of done

A feature is done when:

- its approved acceptance criteria pass;
- documented build, test, and static-analysis commands pass;
- relevant failure modes are covered;
- real-target validation is complete when behavior depends on hardware, UI, audio,
  timing, a plugin host, a service, or an OS integration;
- documentation describes any changed public contract;
- no known blocker is hidden.

For UI/UX work, done additionally means the semantic family was inventoried, the
governing design-system authority was updated, applicable states/sizes/inputs were
verified, accessibility and visual gates passed, and the assembled workflow was tested
at runtime. A local cosmetic patch or single screenshot cannot satisfy completion.

## Authority boundaries

- User owns product intent, charity presentation, and meaningful privacy tradeoffs.
- Agents may research, prototype with synthetic fixtures, and run local checks.
- Publishing, payments, and removal of the user's real audio content require authority.
- Real DAW/player verification requires available installations and representative content.

## Explicit non-goals

- Building a DAW, audio plugin host, vendor installer, or license manager.
- Claiming universal historical usage or declaring an asset safe to delete from age alone.
- Implementing every feature of Plugin Station.
