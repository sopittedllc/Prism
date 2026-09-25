# Library identification from installed content
Research and local schema inspection: 2026-09-25. No account/license records copied.

Kontakt NICNT files embed ProductHints XML (Name/Company); NKI instrument names
provide a useful searchable catalog. Older/non-Player libraries can lack NICNT;
instrument-folder inference remains labeled, not presented as a verified product name.
[NI folder structure](https://support.native-instruments.com/support/solutions/articles/69000879770-can-i-change-the-folder-structure-of-my-kontakt-based-library-)
[NI formats](https://docs.native-instruments.com/ni-tech-manuals/kontakt-manual/en/file-formats)

SINE distributes OT metadata and sample archives together; one instrument can have
multiple microphone positions. The local SINELibrary database joins collections,
instruments and installed mic paths. Paths include virtual OTMF children inside
physical OTMETA files. We read this catalog read-only and require a physical regular
metadata file and matching sample archive inside selected roots; catalog/store entries alone are excluded. Archive integrity/content completeness remain unknown; presence is not playability.
[OT installation](https://orchestraltools.helpscoutdocs.com/article/329-installing-instruments-on-offline-systems)
[OT contents](https://orchestraltools.helpscoutdocs.com/article/335-using-direct-downloads)

Soundpaint programs combine parts. Observed local libraryInfo.lib plus Parts/info.json
provides names and instrument/genre/technique tags. Binary libraryInfo is not decoded;
collection title derives from the folder and provenance discloses that inference.
[Soundpaint](https://soundpaint.com/a/faqs)

Decent Sampler DSPRESET filenames identify presets; current discovery does not parse
all XML mappings/archives. Spectrasonics STEAM product structure identifies Omnisphere,
Keyscape and Trilian, but their factory instrument metadata remains unparsed.
[Spectrasonics](https://www.spectrasonics.net/support/knowledgebase/article/view/27/21)
[Decent format](https://decentsampler-developers-guide.readthedocs.io/_/downloads/en/1.13.0.1/pdf/)

VSL has independent volume scan paths and preset folders. Spitfire has player-specific
library structure. Neither has a verified dedicated adapter in this implementation;
Kontakt-based Spitfire libraries can use the Kontakt adapter. Do not call all players
supported because a folder exists.
[VSL](https://www.vsl.co.at/manuals/synchron-player/database)
[Spitfire](https://support.spitfireaudio.com/en/articles/11816038-standard-folder-structure-for-spitfire-libraries)

Observed local read-only result: 455 library/instrument groups, 9,871 instrument labels
in 4.05 seconds, with one unreadable Kontakt manifest and one root hitting its entry
budget. Includes 20 SINE collections, 7 Soundpaint, 3 STEAM products, 3 Decent groups,
and 422 Kontakt groups (some inferred instrument folders, not 422 verified products).
Accordion matched four groups; Banjo five. No private paths/content included here.

Metadata is generated from local evidence on scan. Keyword tags inferred from names
are explicitly distinguished from vendor tags. No web enrichment or persistent user
tags yet. Next: validated product catalog mappings, editable sourced tags, and optional
web suggestions using product names only; do not silently upload filesystem paths.
