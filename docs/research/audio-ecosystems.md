# macOS audio ecosystem discovery

Research date: 2026-09-24. Acting client: Codex; role: research/documentation.
Status: initial scope and feasibility findings, not verified integrations.

## Product scope

The user confirmed macOS-only and coverage of major DAWs. The following ten families
are a proposed compatibility matrix, not a market-share ranking or a limit on generic
plugin discovery. Inventory should work independently of which DAW is installed.
Each family's usage support needs separate version-specific runtime verification.

| Target family | Related coverage / official reference |
| --- | --- |
| Logic Pro | Include GarageBand in the Apple-host test matrix; [Logic Audio Units](https://support.apple.com/en-ie/guide/logicpro/lgcp22a0dab0/10.7/mac/11.0) |
| Ableton Live | [Plugin formats and operation](https://www.ableton.com/en/live-manual/12/using-plug-ins/) |
| Pro Tools | [AAX](https://developer.avid.com/aax/) |
| Cubase / Nuendo | Separate runtime cases within the Steinberg family; version-specific format investigation remains open |
| Studio One / Fender Studio Pro | Include both names and installed generations; [Fender product](https://www.fender.com/products/fender-studio-pro) |
| FL Studio | [External plugins on macOS](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/basics_externalplugins.htm) |
| REAPER | [Supported formats](https://www.reaper.fm/about.php), including AU, VST, CLAP, LV2, and JSFX |
| Bitwig Studio | [VST and CLAP](https://www.bitwig.com/modern-foundations/) |
| Reason | [VST3 support](https://www.reasonstudios.com/press/vst3-support-for-the-reason-music-making-software); Rack Extensions require separate handling |
| Digital Performer | [VST3 support](https://cdn-data.motu.com/site/docs/dp/v10/DP101ReadMe.pdf); validate current versions separately |

Shared discovery scope: AU, VST2, VST3, AAX, and CLAP. Investigate AUv3 app extensions,
shell plugins, and host-native formats separately; do not promise that every plugin
is an independently removable bundle. LV2, JSFX, Rack Extensions, and bundled host
instruments need explicit inventory/removal policies rather than silent omission.

## Library player families

This is a practical coverage shortlist, not a measured popularity ranking. Vendor
documentation establishes ecosystems and installation concepts, not a supported API
for third-party usage tracking. Every adapter below is still unimplemented.

| Creator / ecosystem | Player or engine | Discovery implications and source |
| --- | --- | --- |
| Native Instruments and third parties | Kontakt / Kontakt Player | Baseline: registered and unregistered libraries both matter; Native Access is not exhaustive. [NI setup](https://support.native-instruments.com/support/solutions/articles/69000879721-setting-up-a-third-party-kontakt-library) |
| Orchestral Tools | SINEplayer; legacy Kontakt products | Model engine per product/version. [SINE entry point](https://www.orchestraltools.com/welcome), [Kontakt-to-SINE example](https://www.orchestraltools.com/berlin-percussion) |
| Vienna Symphonic Library | Synchron family, dedicated piano/harp/organ players; investigate legacy Vienna Instruments | Vienna Assistant manages content, including external locations and optional mic downloads. [Player families](https://www.vsl.co.at/tutorials/faqs/libraries), [installation](https://www.vsl.co.at/manuals/synchron-player/installed-programs-and-files) |
| Soundpaint | Soundpaint | Multiple library directories and rescans are documented. Detect installed libraries separately from parts/programs. [FAQ](https://soundpaint.com/a/faqs) |
| Decent Samples and third parties | Decent Sampler | User-chosen sample-library folder; published history of an internal library database does not prove a stable usage API. [File browser](https://www.decentsamples.com/2022/12/24/whats-the-deal-with-the-file-browser-tab-in-decent-sampler/) |
| Spitfire Audio | Dedicated plugins, legacy LABS, and Kontakt depending on product | Do not assign one engine to the entire vendor. [Dedicated plugins](https://support.spitfireaudio.com/en/articles/11816090-what-is-a-dedicated-plugin) |
| Splice | INSTRUMENT, incorporating LABS | Separate instrument content from loose Splice Sounds files; account for older installations. [LABS transition](https://splice.com/instrument/labs-instrument), [content-location record](https://support.splice.com/en/articles/15465836-how-to-share-instrument-content-across-two-systems) |
| EastWest | Opus and legacy PLAY | Cover both generations; investigate shared content and partial instrument downloads. [FAQ](https://www.soundsonline.com/support/faq), [manuals](https://www.soundsonline.com/support/manuals) |
| UVI and third parties | UVI Workstation / Falcon | A soundbank may be usable by multiple players; avoid counting or deleting shared content twice. [Loading soundware](https://support.uvi.net/hc/en-us/articles/360000877437-Loading-UVI-Soundware) |
| Steinberg and third parties | HALion / HALion Sonic | Include sound libraries independently from the player. [HALion family](https://www.steinberg.net/vst-instruments/halion/) |
| IK Multimedia | SampleTank, Syntronik, Miroslav Philharmonik | Shared content relationships require explicit ownership. [IK FAQ](https://www.ikmultimedia.com/support/faq/index.php?category=11&topic=sampletank-3) |
| Spectrasonics | Instrument-specific engines using STEAM / SAGE content | Plugin software and library folders are separate; shared roots are not deletion units. [Knowledgebase](https://www.spectrasonics.net/support/knowledgebase/article/view/175/21) |
| Toontrack | Superior Drummer, EZdrummer, EZkeys, EZbass | Treat expansions and players separately. [Products](https://www.toontrack.com/), [file locations](https://www.toontrack.com/faq/where-are-my-files-located/) |
| Best Service / Engine Audio | Engine Player and legacy ENGINE 2 | Mixed catalog also includes Kontakt products; classify per product. [Downloads](https://www.bestservice.com/en/downloads.html) |
| UJAM | Product-specific players | Documented separate content blobs, plugin binaries, and authorization data. [File locations](https://support.ujam.com/hc/en-us/articles/4407073303442-Default-File-Locations-for-UJAM-products) |

Next catalog candidates include XLN Addictive Drums/Keys and other instrument-specific
engines. Their exact content discovery rules need further research. General user-selected
folder inventory remains the fallback for unknown vendors; unknown ownership blocks
automatic grouping for removal.

## Loose samples and metadata

[Splice documents](https://support.splice.com/en/articles/8652631-where-do-my-downloaded-samples-presets-midi-files-go)
local pack-organized downloads and a default macOS Splice folder. Users can choose
other roots; do not assume one fixed path. Browser downloads may live elsewhere.
[Bridge-modified samples](https://support.splice.com/en/articles/10302760-where-to-find-samples-that-have-been-modified-with-bridge)
are separate local content whose edits cannot be recovered by downloading originals.

Proposed metadata: kind, product name, creator, player, plugin format, type tags,
location, size, discovery time, and evidence-backed usage. Sample-specific fields may
include loop/one-shot, instrument, tempo, and key when known. Libraries may have many
instrument types; player and sound category are distinct fields. Preserve manual tags
over inferred tags. Record source/confidence for web suggestions and retain Unknown.

Known library internals must not appear as thousands of independently removable loose
samples when selected roots overlap. Store membership and physical file identity.

## Discovery is separate from usage

[Apple FSEvents](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/Introduction/Introduction.html)
reports directory-tree changes. It is a candidate for incremental discovery, not proof
that an instrument was played. Proposed approach: initial inventory, change-driven
incremental scans, periodic reconciliation, and checks on app launch/volume remount.
The mechanism for scanning while the app is quit remains an explicit implementation
decision; no background helper is installed or authorized by this research.

No universal historical plugin/library usage API was established in this research.
For every DAW/player, investigate separately:

- Whether a supported API or log supplies a timestamp and stable asset identity.
- Whether optional project inspection can establish a reference (not actual playback).
- Whether future observation can distinguish validation scans from genuine loading.
- Whether the exact library can be identified inside a multi-library player.
- Behavior with cached/preloaded content, frozen tracks, nested hosts, and offline drives.

Do not label filesystem access/modification dates, project-save dates, plugin validation,
or Simplify scans as last used. A project reference and an observed load are separate
evidence types, neither automatically proves audible use. Unknown is not Never used.
Runtime tests must establish accuracy, permissions, overhead, and version coverage
before choosing a monitoring mechanism or promising cross-DAW last-used ranking.

## Proposed discovery and removal behavior

Coalesce additions into one review queue; wait for downloads to settle. Detect updates
and moves without re-prompting for classification or discarding user metadata. An
unmounted or permission-denied root remains unavailable until successfully rechecked.
Optional web lookup uses product/creator information, not uploaded audio or full paths.

Removal previews exact assets and format variants, treats shared libraries separately,
and prefers Trash. A file-level removal is not a complete vendor uninstall. Installed
players, licenses, presets, and common content roots must never be swept up by a name
match. No usage signal alone establishes that an asset is safe for old projects to lose.

## Next feasibility work

1. Read-only discovery prototype with synthetic plugin/library fixtures and selected roots.
2. Usage experiment matrix across the ten DAW families, reporting per-version evidence
   and explicit unsupported cases; no fabricated historical dates.
3. Validate priority player discovery: Kontakt, SINE, VSL, Soundpaint, Decent Sampler,
   Spitfire/Splice, and Opus; expand through the catalog above.
4. Specify simple classification and removal flows before implementing destructive behavior.

No DAWs, libraries, vendor databases, licenses, or personal audio content were scanned
or modified during this research. No app functionality has been implemented yet.
