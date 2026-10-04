# Controlled host checkpoint — 2026-09-26

Driver: Codex. Private experiments only; no production source edits in this increment.
Accessibility is now available following the user's system-settings change. No source
project was opened for editing: all hosts opened isolated, checksum-verified copies.
The original 14 fixture files remained byte-identical after the controls.

## Observed controls

| Host | Baseline | Removal / other control | Defensible result |
| --- | --- | --- | --- |
| Ableton Live 12.4.6 | Unchanged save from supplied Live 12.4.5 fixture | Diva device removed; Diva bypassed; Kontakt emptied | Reader returns 3/2/3 plugin candidates respectively. Removed Diva's track remains. Bypassed Diva has On/Manual=false. Kontakt remains with empty rack. |
| Logic Pro | Unchanged Save As | Diva removed using No Plug-in; saved another copy | Exploratory embedded AU tuples change from expected 3 to 2; no active-record framing support claimed. |
| Cubase 15 | Unchanged Save As of template-derived fixture | Added Diva01 track removed and saved | Diva identifier occurrences decrease but remain. Other template instances and retained state are not distinguishable by global scan. |
| Pro Tools | Unchanged Save Session As plus official all-track text export | Diva removed via no insert; save and export | Baseline export has Q4/Kontakt8/Diva, each 1 active AAX instance; removal export retains only Q4/Kontakt8. WAV listed with file location. |

The user confirmed only Cubase used a template and is preparing new Empty/Loaded/
Diva Removed Cubase projects. These were not present at the last file inventory.
No clean Cubase baseline is inferred from deleting records in its existing template.

Official workflows: [Ableton saving](https://help.ableton.com/hc/en-us/articles/115000915804-Saving-Projects),
[Ableton devices](https://www.ableton.com/en/manual/working-with-instruments-and-effects/),
[Avid session text export](https://resources.avid.com/SupportFiles/PT/Pro_Tools_Reference_Guide_12.8.2.pdf).

## Kontakt research result

Root visually verified the loaded Wineglass program and the separate empty rack.
Independent researcher `kontakt_controls` validated NIS outer framing, then authored
and replayed a bounded experimental FastLZ decoder. The loaded state contains:
bank -> occupied slot -> program container -> one named program. The empty control
has no occupied slot. Its unrelated browser strings remain, confirming that global
text search is not suitable for program membership.

[Original FastLZ source](https://github.com/ariya/FastLZ/blob/b1342dabcf5257ab303743c9332fe75e9147a011/fastlz.c),
[pinned ni-file research](https://github.com/Ma5onic/ni-file/tree/1b7a518243125857fddec8217167b47a35cb58fa/src/kontakt/objects).
This is reverse-engineered research, not a vendor-supported Kontakt schema.

Saved Program and Bank versions are newer than those documented by the author.
The filename table is v3; both [ni-file](https://github.com/Ma5onic/ni-file/blob/1b7a518243125857fddec8217167b47a35cb58fa/src/kontakt/objects/filename_table.rs)
and the [HexFiend author template](https://github.com/monomadic/hexfiend-templates/blob/master/Kontakt/FNTableImpl.tcl)
accept only v2. V3 decoding is explicitly rejected. An unexplained eight-byte tail
is retained as unknown. Program name does not identify the installed NKI.

NI's documented [get_zone_sample](https://docs.native-instruments.com/ni-tech-manuals/kontakt-api-reference-manual/en/zone)
provides a possible independent runtime sample-path ground truth. Shared samples
are not unique NKI identity; no library or patch match follows automatically.

## Reproducibility and limits

Private workspace and generated-file SHA-256s are in build/usage-controls/current.json
and its referenced manifest. The ignored kontakt-research-probe.py records source
pins, bounded decoding, exact-size assertions and unsupported-version handling.
The probe's input offsets come from separately checked enclosing framing; it is not
a general production parser. Raw sessions, state and screenshots stay outside Git.

An initial Pro Tools text export used a remembered destination outside the working
folder. Its creation time and byte equality were checked; it was moved into the
isolated workspace. No export remains at that destination. Originals were rehashed
subsequently. No plugin installation or original audio was removed.

No exact historical timestamp, four-host compatibility, or cleanup recommendation
is admitted. Actual clocks, failed loads, source/identity resolution, same-name NKI,
replacement/multiple-program controls, template ownership and parser version support
remain open. Earlier 98 unit tests cover the shipped Live descriptor increment;
these experiments do not add production code or waive any release gate. The earlier
native Prism screenshot failure remains a separate gate; host-window captures here
succeeded and do not substitute for that complete smoke test.
