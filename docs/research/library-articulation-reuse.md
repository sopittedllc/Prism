# Reusing articulation metadata

Research in progress, 2026-10-04. Acting client: Codex; coordinator: Astra;
independent collection/source researcher: Sol. User explicitly requested research
before bespoke extraction. This finding does not close Libraries acceptance.

## Preferred sources

| Source | Verified capability | Decision |
| --- | --- | --- |
| Installed SINE SQLite catalog | Exact collection/patch/articulation IDs and visible names. The installed subset has 543 patches and 2,999 visible articulations, including three poly articulations. | Reuse native relational metadata; do not restrict to `kind='single'`. Physical mic/archive membership qualifies installed patches. |
| [Reaticulate](https://github.com/jtackaberry/reaticulate) factory/user banks | Existing structured articulation maps across vendors; Chamber Strings has separate section and patch-family banks. | Strong reuse candidate. Parse its established format and bind banks to identified installed patches; do not derive membership from fuzzy name similarity. |
| [ni-file](https://github.com/Ma5onic/ni-file) | Existing Rust readers for modern Kontakt containers, program metadata, file tables and zones; README states partial format coverage. | Evaluate against real patches before adopting. Reading sample groups is not automatically equivalent to recovering available scripted techniques. |
| [ConvertWithMoss](https://github.com/git-moss/ConvertWithMoss) | Current source includes Kontakt 5+ Program/Group/Zone readers. Group parser reads names; program parser skips script chunks; container reader rejects encrypted subtrees. Source headers specify LGPLv3. | Reuse candidate for unprotected structural metadata, not yet proven as an articulation extractor. Do not assume its older format limitations still apply. |
| [Kontakt Lua API](https://docs.native-instruments.com/ni-tech-manuals/kontakt-api-reference-manual/en/instrument) | Official instrument/group queries and command-line script execution. | Test supported metadata queries when needed. No documented universal articulation-list API was found in the reviewed interface. No script unprotection or sample export needed for inventory. |
| [PresetMagician NKS research](https://presetmagician.gitbook.io/help/faq/nks) | Existing RIFF preset metadata readers; preset name, bank, types, modes and controller assignments. | Useful discovery/tagging source; does not establish all techniques inside a scripted patch. |
| [Art Conductor](https://github.com/babylonwaves/art-conductor) | Established curated maps for many libraries. Public repository exposes supported-library lists and a demo; full maps are a commercial product. | Evaluate existing user-owned maps or separately licensed data. A supported-library list is not the articulation dataset; no purchase is authorized. |
| [nkitool](https://www.linuxsampler.org/nkitool/) | XML extraction for old Kontakt versions; upstream explicitly excludes format introduced in 4.2.2. | Not a solution for the modern collection. |
| [kontakt2mpce](https://github.com/AdamJablonski/kontakt2mpce) | README explicitly says converter is not implemented. | Reject as an existing implementation despite planned-feature checkmarks. |

## Concrete Reaticulate check

Inspected revision `3760589894808c03fac4b07aa0d3a63812484350`,
`banks/64-01-Spitfire-Chamber_Strings.reabank`, bank 64/15, UUID
`00000000-6a09-4d09-a76e-87623be09ec5`, **SCS - Vc Core**.
Its 15 choices correspond to the 15 available techniques independently observed
in the installed primary Celli Core patch in Kontakt 8.13.1. Its names use shorter
musical aliases; e.g. con sord corresponds to Long CS. It excludes the two disabled
choices visible in the player (Spiccato Feathered and Staccato Dig).

This is evidence for reusing the map, not for copying violin or decorative banks
onto cello. Maps may describe multis, custom routing or customized patches; binding
must preserve that distinction. Source UUID and pinned revision allow provenance
and update review. Reaticulate's LICENSE.md applies Apache 2.0 to these files;
notation-icon restrictions are separate and no icons are needed for metadata.

## Full inventory reconciliation

The complete scan indexes all visible installed candidate paths across the two
configured roots: 28,291 NKI, 1,178 NKM, 17,427 NKSN, 10 DSPRESET, plus 543 SINE
catalog patches. The raw extension census additionally found 68 AppleDouble
`._` sidecars and one NKI in a synchronization service's Trash. These are excluded
from installed patch counts, not silently lost to scan limits. All 47,449 returned
patch records have a qualified filesystem directory-addition date. The scan took
33.2 seconds on this collection; library footprint still hit the old plugin-size
budgets and remains unfinished.

## Implementation decision still to qualify

Prefer native vendor metadata, then existing licensed patch-specific maps, then
proven structural readers. Keep a small source adapter boundary and explicit
patch binding; avoid a new binary parser or a growing handwritten articulation
list. Test reusable extraction against Core plus contrasting libraries before
committing to broad integration. GUI inspection is a validation control, not the
production indexing strategy. Unmapped required articulations remain unfinished
work; a label does not satisfy the parent acceptance contract.
