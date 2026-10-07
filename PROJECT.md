# Prism

**Status:** Discovery
**Owner:** TODO
**Primary target:** macOS desktop application; minimum OS and distribution channel TBD.

## Product statement

Prism is a free, lean audio collection manager supporting Altadena Girls.
Musicians and composers can inventory installed plugins, individual samples, and
instrument libraries, classify them, understand saved-project references, and remove
unwanted content. Charity presentation and donation destination remain to be defined.

## Primary workflow

Two primary jobs govern the interface: reclaim storage from infrequently used content,
and discover recently added content or a specific instrument already in the collection.
Libraries browse as maker → library → instrument, while Individual Samples mirrors the
chosen folder trees. Library footprint belongs to the whole installed library, not each
patch. Tags are inherited with durable editable user overrides. The current basic
catalog contract is [.work/active/catalog-basics-product-model.md](.work/active/catalog-basics-product-model.md):
one durable plugin product owns its formats, tags, and qualified history. Missing
source data stays Unknown; broader host and individual-sound usage gates remain open.

1. Discover installed plugins and choose one or more sample and library folders,
   including local Splice downloads and external drives.
2. Browse Plugins, Individual Samples, and Libraries; search names and tags.
3. Sort sounds by Tags, Date added, Last used, size, or name. Last used may include
   an exact item's qualified saved-project/backup membership at that snapshot's
   modification time, as well as qualified project-open or plugin-instance events.
   Candidate references remain separately labeled. Unknown coverage stays visible.
4. Review selected files and dependencies before removing unwanted items.
5. Routinely detect additions and offer a batched classification queue, with manual
   tags using the bundled offline catalog and manual edits.

This workflow is the north star for feature and architecture decisions.

## Users and environment

- Primary user: macOS musicians, producers, composers, and audio engineers.
- Skill level: no filesystem or plugin-format expertise required.
- Physical/host environment: major macOS DAWs, standalone players, internal/external storage.
- Typical session length: quick inventory and cleanup; quiet ongoing discovery.
- Worst credible operating conditions: large collections, disconnected drives,
  partial downloads, moved folders, shared content, and older projects depending on assets.

## Non-negotiable constraints

- Reliable Last used and Date added are the two highest-priority capabilities and
  release gates. Validate saved-project references across all four primary hosts
  before treating cleanup as delivered; UI polish and metadata breadth cannot
  substitute for this evidence. Live observation is outside this delivery.
- Date added must distinguish original addition, recorded installation/update, and
  first discovery by Prism. Initial inventory, rescans, updates, moves, and reconnects
  must not make an existing product appear newly acquired. Unknown original dates
  remain unknown; discovery of a plugin by a DAW does not establish use.
- macOS only; compatibility target covers ten DAW families, with related products
  included, as recorded in [ecosystem research](docs/research/audio-ecosystems.md).
- Logic Pro, Ableton Live, Cubase, and Pro Tools are mandatory primary targets.
  REAPER coverage does not satisfy that requirement. Validate each host separately.
- Usage evidence should cover individual samples and player-specific instruments
  where exact saved-state identity is available. For Kontakt saved projects, the
  owner chose verified **library-level** membership; exact NKI attribution is
  outside that delivery scope and must remain Unknown rather than inferred.
  For supported Cubase Omnisphere, Keyscape, and Trilian states, resolve only
  exact installed preset-library membership; a player instance or top-level
  multi label does not establish every loaded library.
  `Last used` means the latest qualified saved-project or backup reference to
  the exact installed item, timestamped by that saved snapshot's modification
  time. Muted or bypassed saved references count. Unsaved activity and removed
  items without a saved reference do not count. Preserve source and coverage so
  a saved reference is never presented as playback. For Individual Samples,
  exact saved paths qualify; Quick Look, Preview, and Splice previews do not.
  Historical host observations remain stored but are excluded from this Last Used
  projection; see
  [activity research](docs/research/daw-activity-history.md).
- Keep scanning incremental and avoid disrupting audio sessions; numerical budgets
  require a measured prototype.
- Distinguish plugin product, installed format, player, library, preset, and loose sample.
- Never present installation or scan time as last used. A project's modification
  time qualifies only when that exact item is referenced in that saved snapshot;
  otherwise it is an explicitly labeled candidate-reference recency proxy.
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
