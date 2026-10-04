# Four-host evidence architecture and fixture checkpoint

2026-09-26. Codex coordinator; independent read-only researchers `host_research`
and `player_research`. This document records feasibility and admission decisions,
not completed usage support. Private originals were inspected without launching
plugins or modifying sessions. Aggregate observations only are recorded here.

## Product decision

Usage is an evidence pipeline, not a timestamp attached by the scanner. Four DAWs
and three asset classes require separate coverage declarations. A plugin can have
saved references while its instrument patch is unresolved and its actual load date
is unknown. None of these cases may be converted into an unused recommendation.

Saved inclusion counts even without playback. An exact last-used time still requires
a validated event clock: saving an unchanged project, copying a project, scanning
installed files or inspecting a running process is not a new plugin load.

## Routes and tradeoffs

| Route | Strength | Limitation | Decision |
| --- | --- | --- | --- |
| Offline saved project | Automatic history discovery, host need not run | Proprietary formats, retained state, no exact event clock | Preferred discovery route when structural evidence is validated; candidate coverage otherwise |
| Official host export / scripting | Host interprets its own state | Export requires host workflow; SDK licensing/version support; may omit player dependencies | Supported fallback to investigate, not a hidden mandatory setup burden |
| Prospective successful-load events | Potential actual event time and session association | Coverage starts when tracking begins; failure/validation events confound logs; no universal instrument identity | Separate future adapter per host, with positive/negative runtime tests |

### Ableton Live

Vendor documentation states that ALS contains references, while media and plugins
remain external. Collect All and Save can copy media and does not collect plugins.
This means saved absolute paths, copied assets and original assets cannot be merged
by filename alone. [Ableton project transfer documentation](https://help.ableton.com/hc/en-us/articles/209071909-Transferring-Projects-to-another-computer)

The supplied Live 12.4.5 session contains three direct VST3 descriptors under track
DeviceChain/Devices/PluginDevice/PluginDesc. The existing reader only understands
VST2 PlugName and misses these. A narrowly scoped candidate-descriptor fix is
supported by this structure. Browser labels, preset names and arbitrary Name fields
must not count. Nested racks/master routes need separate fixtures before extension.
ALS is empirically observed here, not a published stable schema.

### Logic Pro

Logic 12.3 metadata provides a relative WAV reference. Its proprietary ProjectData
also contains three embedded AU state dictionaries; installed AU type/subtype/maker
tuples match. This is promising identity evidence, but searching for XML delimiters
does not establish active-instance record boundaries. Alternative 000 is not proven
active. No binary parser is admitted on this evidence.
[Apple project alternatives](https://support.apple.com/it-it/guide/logicpro/lgcpa158ef77/10.7/mac/11.0),
[Apple AU fullState](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/fullstate?language=objc)

### Cubase

The supplied Cubase 15.0.30 CPR is approximately 39.5 MB. Bounded exploratory parsing
of typed UID/name records finds 21 distinct named products, including the three
expected test plugins. This does not prove 21 active instances. The source may
contain template, inactive or retained state; a removal/save control is necessary.
The WAV name also occurs in unrelated plugin state, so global filename scanning is
specifically rejected. The current 32 MiB reader input budget must not simply be
raised to fit this fixture: a CPR parser needs its own streaming/chunk budget design.

The MIT-licensed author's [cubase-project-plugins reader](https://github.com/fgimian/cubase-project-plugins)
uses typed records but does not establish active ownership. It is a reference for
candidate extraction, not a ready-made usage tracker. [CubaseTools format notes](https://github.com/schwifty00/CubaseTools/blob/master/docs/cpr_format.md)
include heuristic relationships; these are not adopted as cleanup evidence.
Official track archives are a possible structured export route; alternate versions
need explicit handling. [Steinberg track versions](https://www.steinberg.help/r/cubase-pro/15.0/en/cubase_nuendo/topics/track_handling/track_handling_trackversions_c.html),
[Steinberg archive manual](https://archive.steinberg.help/cubase_pro/v11/en/Cubase_Pro_11_Operation_Manual_en.pdf)

### Pro Tools

PTX has no implemented reader. Official Export Session Info as Text offers plugin,
file, clip and track EDL lists; pool membership and timeline placement must stay
separate. [Avid reference guide](https://resources.avid.com/SupportFiles/PT/Pro_Tools_Reference_Guide_12.8.2.pdf)

The [Avid scripting SDK](https://kb.avid.com/pkb/articles/en_US/Knowledge/Pro-Tools-Scripting-SDK-FAQ)
is IPC control of an open session, not an offline file decoder. No SDK was downloaded
or click-through accepted. Its [published agreement](https://my.avid.com/cpp/Content/doc/Avid%20Pro%20Tools%20Scripting%20SDK%20License%20Clickthrough.pdf)
restricts SDK use for reverse engineering session formats; do not treat it as a
shortcut to PTX decoding. The third-party author's [libptformat](https://github.com/zamaudio/ptformat)
exposes media/regions/tracks, not plugin or Kontakt attribution. LGPL obligations,
version coverage and parser isolation need review before any dependency adoption.

### Kontakt and plugin identity

Kontakt processor/AU state in the supplied Live/Logic sessions does not expose the
expected instrument path as plain UTF-8/UTF-16. Unrelated NKI-looking text exists
near browser-like data. No instrument attribution follows from this finding.
VST3 delegates state streams to plugins, with no universal external-file manifest.
[Steinberg persistence](https://steinbergmedia.github.io/vst3_dev_portal/pages/FAQ/Persistence.html)

The [Kontakt Lua API](https://docs.native-instruments.com/ni-tech-manuals/kontakt-api-reference-manual/en/instrument)
works with the current rack and allows mutable instrument names. The inspected API
provides no current instrument source-filename getter. Names alone are insufficient.
[API setup](https://docs.native-instruments.com/ni-tech-manuals/kontakt-api-reference-manual/en/introduction-and-setup),
[Kontakt saving model](https://docs.native-instruments.com/ni-tech-manuals/kontakt-manual/en/classic-view)

Diva's saved VST3 UID matches its installed module metadata. Pro-Q 4 and Kontakt 8
on this machine lack that optional metadata. Missing IDs must not silently downgrade
to verified name matches. Moduleinfo is JSON5-compatible (including trailing commas)
and has both historical and modern locations; strict JSON-only parsing is inadequate.
[Steinberg moduleinfo](https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical%2BDocumentation/VST%2BModule%2BArchitecture/ModuleInfo-JSON.html),
[JSON5 specification note](https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical%2BDocumentation/Change%2BHistory/3.7.5/ModuleInfo.html)

## Proposed domain boundaries

- Source snapshot: host/version, adapter/version, project/version identity, content
  fingerprint, source locator, capture time and source-modified time separately.
- Evidence: asset class, format-specific identifier, host track/device context,
  evidence kind, success/failure/unknown outcome, source locator and coverage.
- Resolution: exact, ambiguous or unresolved association to a catalog node. Never
  use a player association to assign use to sibling libraries or patches.
- Current membership: replace only when the same source was parsed successfully;
  missing source/drive or failed scan marks prior evidence stale, not absent.
- Historical events: append/deduplicate only validated events; source rescan is not
  an event. Removing a plugin from a later save does not erase a past observed load.
- Presentation: latest proven load; separately project-reference recency; unknown
  with coverage reason. A product aggregate must retain format-level evidence.

A future durable ledger needs registry coverage and migration tests before code:
local persistence included; defaults unknown; no user-editable timestamps; undo,
presets, automation and sync excluded; no analytics/upload; explicit private export.
Event/source deduplication, concurrent scans, clock changes, log rotation, parser
version invalidation, source relocation, cancellation and bounded resource use are
required design tests. None of this proposed ledger is represented as implemented.

## Controlled next experiments

Keep originals immutable; use host-saved copies with before/after digests. For each
host compare empty, added, removed-before-save, bypassed and missing-plugin states.
Test copied/collected WAV versus original, unused media pool and alternate versions.
For Kontakt compare empty rack, the known NKI, replacement, two NKIs, rename,
browser-only selection, removal/save and equal filenames in different directories.
Measure event clocks against controlled actions only after identity is established.

Synthetic malformed/truncated/version/DTD/depth tests prove parser behavior. Real
positive and negative saves prove host semantics. Both are needed. The provided
positive fixtures unlock research; they do not satisfy the negative-control matrix.

## Checkpoint

Four-host actual last-used remains unimplemented. First admitted implementation scope
is the missing Live 12 direct-track VST3 descriptor candidate, with adversarial tests
and private real-fixture replay. No Kontakt, Logic binary, CPR or PTX support is
claimed from string inspection. Follow the active four-host-evidence plan for review
and verification results.


## Execution checkpoint: clean Cubase controls and diagnostic implementation

The user subsequently supplied clean Cubase 15.0.30 empty, baseline and Diva-removed
sessions. Independent replay found 10, 123 and 100 typed descriptors respectively.
The baseline contains one descriptor each for Pro-Q 4, Kontakt 8 and Diva; the removed
file excludes Diva descriptors while retaining four Diva track/routing labels. These
numbers are descriptor records, not instance counts. The prior template ambiguity
is not resolved by this result for other projects.

The next scoped implementation is CubaseDiagnostics and the explicit
`--inspect-cubase-descriptors FILE` command. It follows the author reader pinned to
[c324cdc82548cc05e9453cd12a30ccae7551768f](https://github.com/fgimian/cubase-project-plugins/blob/c324cdc82548cc05e9453cd12a30ccae7551768f/src/reader.rs)
with MIT attribution, strict metadata/version gating, 32 MiB input and 4,096 record
limits, failure without partial output, offsets and an input digest. This author
source is not a vendor specification. Steinberg has documented a
[project-format change in 13.0.30](https://helpcenter.steinberg.de/hc/en-us/articles/31885407408018-Cubase-Nuendo-Invalid-project-after-saving),
so signatures alone do not imply general compatibility.

The diagnostic type is deliberately outside ProjectReport and catalog persistence.
Complete typed descriptors embedded in opaque state still appear as unresolved
candidates; a regression test documents that limitation. Normal CPR scanning remains
unsupported. Neither current membership, exact instrument identity nor a usage clock
has been admitted. The detailed staged delivery plan is
[usage-evidence-delivery](../../.work/active/usage-evidence-delivery.md).
