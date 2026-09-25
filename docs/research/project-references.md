# Saved-project reference feasibility

2026-09-24. Acting client: Codex; independent Codex researcher and reviewer.
User direction supersedes the earlier playback investigation: inclusion in a project
is sufficient. No playback monitor, Endpoint Security entitlement, or privileged
background observer is needed for this prototype.

## Evidence semantics

References carry original text, project path, adapter, and explicit coverage limits.
The latest modification date among referencing project files is a recency proxy only:
copying, restoring, or touching a project can change it. It is not insertion time.
Unknown/unsupported coverage cannot establish an asset is unused or safe to delete.
Collected/copied samples are different physical assets; no basename matching occurs.
The current prototype cannot identify individual libraries inside opaque plugin state.

## Native format matrix

| Family | Current prototype | Next verification route |
| --- | --- | --- |
| Ableton Live | Experimental direct SampleRef/FileRef candidates from bounded gzip XML; unresolved locations | Verify external, project-relative, relocated, collected, frozen, and sampler media with controlled host-saved sets; plugin descriptors need fixtures |
| REAPER | Experimental bounded text subset: recognized track/item/source paths and FX declarations; synthetic fixtures only | Compare with host-generated sessions and documented ReaScript queries before advertising compatibility |
| Logic / GarageBand | Logic Alternatives/000 metadata candidates; GarageBand unsupported | Controlled projects and supported host/export paths; package-contained audio is not automatically a reference |
| Pro Tools | Recognized as unsupported | Session-info text export / scripting SDK |
| Cubase / Nuendo | Recognized as unsupported | XML track archives; Cubase DAWproject export where supported |
| Studio One / Studio Pro | Recognized as unsupported | DAWproject exchange validation; native reader remains research |
| Bitwig | Recognized as unsupported | Documented DAWproject exchange, distinct from native BWPROJECT |
| FL Studio | Recognized as unsupported | Native/exchange research; ZIP exports omit third-party sampler dependencies |
| Reason | Recognized as unsupported | Controlled external vs self-contained media fixtures |
| Digital Performer | Recognized as unsupported for known extensions | Host exports and native format research; extensionless/other containers may not be detected |

## Factory evidence

Read-only inspection of 26 ALS files bundled with the installed Ableton application
found 3,559 direct SampleRef nodes. RelativePathType values were 5 (3,495) and 7 (64).
No third-party plugin descriptors appeared. One demo had 51 sample references but 343
general FileRef elements, demonstrating why generic path searching overcounts.
Some absolute paths referred to obsolete build machines. Historical OriginalFileRef
nodes occur deeper under SampleRef and must not be counted as current references.
The adapter emits both saved absolute and relative candidates, not two confirmed uses.
It rejects DTDs, non-UTF-8 XML, malformed XML, oversized input, and excessive nesting.

Factory-derived structural observations are not a vendor-supported schema guarantee.
No proprietary fixture or user session was copied into the repository. No real REAPER
session was available; its parser remains experimental and fixture-tested only.

## Official sources

- [Ableton file management](https://www.ableton.com/en/manual/managing-files-and-sets/)
- [Ableton project transfer](https://help.ableton.com/hc/en-us/articles/209071909-Transferring-Projects-to-another-computer)
- [REAPER user guide: text RPP and backup semantics](https://dlz.reaper.fm/userguide/ReaperUserGuide774.pdf)
- [REAPER API: media source and FX queries](https://www.reaper.fm/sdk/reascript/reascripthelp.html)
- [Logic project assets](https://support.apple.com/en-is/guide/logicpro/lgcpce0d70e7/mac)
- [DAWproject specification and supported hosts](https://github.com/bitwig/dawproject)
- [Avid scripting SDK](https://developer.avid.com/scripting/)
- [Pro Tools session export reference](https://resources.avid.com/SupportFiles/PT/Pro_Tools_Reference_Guide_12.8.2.pdf)
- [Nuendo track archives](https://www.steinberg.help/r/nuendo/15.0/en/cubase_nuendo/topics/track_handling/track_handling_exporting_tracks_as_track_archives_t.html)
- [FL Studio project formats](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/fformats_project.htm)
- [Reason reference semantics](https://docs.reasonstudios.com/reason13/sounds-patches-and-the-browser)
- [Digital Performer guide](https://cdn-data.motu.com/manuals/software/Digital%20Performer%20User%20Guide.pdf)

## Next slice

Build controlled host-saved sessions with muted clips, bypassed plugins, nested samplers,
collected media, moved roots, and missing files. Validate every match against a DAW's
own reference listing. Add optional export adapters for closed formats. Then connect
these capabilities to the macOS catalog interface; do not gate generic inventory on
having a native project parser for every DAW.

## User-authorized validation and Logic metadata

A bounded 100,000-entry enumeration was performed on the user-selected project root.
Only aggregate counts are retained under the catalog-browser evidence directory.
The convenience sample includes real ALS and Logic files; no host-oracle confirmation
is claimed. Older ALS files expose direct FileRef/Name rather than Path. Names are now
preserved as unresolved candidates, never matched by basename. Logic reads only
AudioFiles/PlaybackFiles in Alternatives/000/MetaData.plist; missing, linked, malformed,
or differently structured metadata fails explicitly. Alternative 000 is not proven
active; unused/backups/other alternatives are excluded. No scanned project modification
times changed in the bounded sample.
