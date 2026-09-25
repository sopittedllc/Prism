# DAW activity and instrument-level inclusion

Research date: 2026-09-25. Required primary hosts: Logic Pro, Ableton Live,
Cubase, Pro Tools. Findings below are research, not implemented adapter coverage.
User requires inclusion, even if never played, for plugins, loose samples and
individual library instruments. REAPER is supplemental coverage.

## History sources

There is no dependable documented universal last-plugin-use database established
by this investigation. File timestamps do not attribute access to a DAW or distinguish
validation, preview, loading and project inclusion. Future observation cannot recover
events that predate monitoring. Rotated logs and disabled logging leave gaps.

| Host | Evidence route | Limit |
| --- | --- | --- |
| Pro Tools | Plaintext launch logs; local logs contain host-plugin instantiation events associated with tracks | Validate clock anchoring and successful completion; exclude startup scans and internal mixer events |
| Ableton Live | Chronological Log.txt, including AU restoration attempts | Restoration may fail; attempts are not successful loads or proof of current saved inclusion |
| Cubase | Optional usage logging includes plugins used | Disabled by default; no local usage-log directory found; do not enable silently |
| Logic Pro | Saved project state and potential future host-aware observation | No reliable documented per-plugin historical usage log established; AU validation cache is not usage |

Official sources:
- [Avid log export](https://kb.avid.com/pkb/articles/Troubleshooting/Exporting-Log-files-from-a-Pro-Tools-System)
- [Ableton chronological logs](https://help.ableton.com/hc/en-us/articles/5301568366354-Reading-Ableton-Live-Crash-Reports)
- [Steinberg usage logging](https://helpcenter.steinberg.de/hc/en-us/articles/32371744743826-Usage-Logging)
- [Apple plugin validation](https://support.apple.com/en-asia/guide/logicpro/lgcp9e26ef17/mac)

Read-only local aggregate inspection: four Pro Tools logs contained 22 explicit host
plugin instantiation events. Seven Ableton logs contained 95 restore attempts and
95 restore failures. No raw log content, project names, tracks, or private paths
were copied into the repository. These counts establish available signals, not a
complete history or working adapters.

## Samples and library instruments

The Libraries view needs library → instrument/preset detail. Treat logical player
instruments separately from their physical files: not every player has one NKI-like
file per instrument. A player load alone never marks every library/instrument used.

| Content | Verified representation / research route | Unresolved validation |
| --- | --- | --- |
| Loose samples including local Splice files | Saved media references and project-local copies | Resolve exact path versus content-equivalent copy; filename alone is insufficient; preview access is not inclusion |
| Kontakt | NKI instruments reference samples; multis and host state also matter | Identify exact instrument in saved host state or validated player events; no comprehensive NKI usage log established |
| SINE | Player preset contains loaded instruments/articulations; host saves player state in project; OT metadata describes instruments | Decode instrument IDs and map to collection/content without treating all downloaded content as included |
| Decent Sampler | DSPRESET XML describes sample assets | Validate preset-to-sample dependencies and embedded host state; installed preset alone is not usage |
| VSL Synchron | Official preset workflow exposes patch IDs/folders in copied preset structure | Validate host-state/preset mapping to installed instruments; no complete historical usage log established |
| Soundpaint | Programs and sample mapping documented | Establish program/instrument identity and host-state evidence before claiming support |

Sources:
- [Ableton file references and collection](https://www.ableton.com/en/manual/managing-files-and-sets/)
- [Logic project consolidation](https://support.apple.com/en-sg/guide/logicpro/lgcpce09b9d8/12.3/mac/15.6)
- [Kontakt instruments and sample references](https://docs.native-instruments.com/ni-tech-manuals/kontakt-manual/en/classic-view)
- [SINE saved state](https://orchestraltools.helpscoutdocs.com/article/300-header-toolbar)
- [SINE instrument metadata](https://orchestraltools.helpscoutdocs.com/article/335-using-direct-downloads)
- [Decent Sampler developer format guide](https://decentsampler-developers-guide.readthedocs.io/_/downloads/en/1.13.0.1/pdf/)
- [Synchron preset structure](https://www.vsl.co.at/manuals/synchron-player/custom-preset-creation)
- [Soundpaint programs and mapping](https://soundpaint.com/a/faqs)

## Proposed evidence contract and acceptance

Record asset/instrument identity, host, source kind, source version, timestamp meaning,
project identity where known, outcome (attempt/success/failure), and coverage window.
Show Included in projects separately from Last observed loading. Project modification
date is a labeled proxy, not the time an asset was added. Unknown never means unused.
Library summary may aggregate identified child instruments, without marking siblings.
Shared sample containers are dependencies, not individually removable instrument files.

For each mandatory host, create controlled saved projects with a plugin, loose sample,
and library instrument; include muted/unplayed instances. Compare open/save/reopen,
remove-before-save, failed plugin restore, browser preview, validation scan, collected
sample copies, missing drives, and log rotation. Establish false-positive boundaries
before shipping usage sorting. Inventory remains fast; history and dependency work
runs incrementally in the background. This validation and adapters remain outstanding.
