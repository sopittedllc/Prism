# Prism

A free macOS audio collection manager supporting Altadena Girls, currently a
native browser preview. The implemented collection has Plugins, Samples and
Libraries views, local catalog persistence, measured sizes where available,
editable tags/metadata, partial host usage evidence and reviewed plugin
removal. The required four-host Last used coverage for individual samples and
library instruments is unfinished. See the [portable handoff](docs/HANDOFF.md)
for exact coverage, limits and offline setup.

Build with `swift build`, then package with `swift build -c release` and
`python3 scripts/build_app.py`; open `build/Prism.app`. Follow setup to add
sample/library/project locations, then Scan.
Standard plugin folders are enabled by default. Command-F focuses search; Command-R scans.
Accepted folder setup and inventory are stored on this Mac; filters are
session-only. Plugin formats can be moved to Trash after review. Sample and
library removal are not implemented.

The CLI remains available: `.build/debug/simplify-probe --help`.

```sh
.build/debug/simplify-probe --standard-plugins
.build/debug/simplify-probe --samples "$HOME/Music/Samples" --libraries "$HOME/Music/Libraries" --projects "$HOME/Music/Projects"
```

Only specify folders you intend to inspect. Reports contain local paths. The scanner
never loads plugins, changes scanned files, or deletes content. Exit 2 means issues
were reported; exit 0 still does not imply complete project dependency coverage.

Project readers remain partial. REAPER, Ableton and Logic saved references,
Pro Tools text exports and Cubase diagnostics have distinct coverage limits.
Live/Cubase/Pro Tools positive plugin-load adapters and Logic current mixer
observation have qualified narrow routes; no one adapter proves universal
history or an individual sample/instrument load.

"Latest referencing project modified" is a file-date proxy, not the date an asset was
added or played. No references found only describes this scan. Copied samples, opaque
player state, unsupported DAWs, and unscanned projects may conceal dependencies.

See [product scope](PROJECT.md), [toolchain](TOOLCHAIN.md),
[project-reference findings](docs/research/project-references.md), and
[ecosystem research](docs/research/audio-ecosystems.md).

Packaging derives the app icon from the supplied Prism JPG and places it on
a rounded Dock tile.
Visual guidance comes from Projector: compact headings, rounded panels, pink primary
actions, and system typography/colors. Projector source was inspected, not modified.


The collection browser now uses sidebar navigation and a contextual inspector. First launch offers four-step setup; **Manage locations…** reopens it. Setup can be saved locally or used for one session. See [collection and setup design](docs/ui-ux/COLLECTION_AND_SETUP.md) for research, persistence and preview limits.

Scan feedback includes the current stage, live entry count, current item, elapsed time, and per-stage percentages once totals are known.

Plugins group by normalized name and compatible complete bundle identifiers; only
explicit separated format suffixes are normalized. Unknown or incompatible identities
stay separate. Manage formats lists each installation; unchecked formats are kept.
Remove all formats means all listed installations, not shared presets, licenses or
libraries. Review exact paths before moving to macOS Trash. Permission failures and
changed files stay listed; no permanent-deletion fallback or privileged helper exists.
Restore through Finder Trash and rescan. Close DAWs before removing plugins.

Samples and Libraries accept repeated, multi-selection folder additions, including
separate Kontakt and Orchestral Tools roots. A more-specific sample root overrides a
broad library root; more-specific library roots still protect library interiors.
The preview limit is 100,000 entries per category, with explicit partial-scan status;
a large sample tree no longer prevents project discovery. Inventory persists
locally, with stale labels for entries not observed on a later scan.


Library discovery now reads Kontakt manifests/instrument names, installed SINE
catalog entries, Soundpaint part tags and recognized STEAM product structure. It
excludes arbitrary folders. Search includes instrument names and derived tags; inferred
identity and partial scans remain labeled. This is not complete player or usage coverage.
Plugins show Name and Last used (Unknown without qualified activity evidence); format
installations and reviewed Trash remain in details. Latest branding source is the exact
user-supplied JPG. See docs/research/library-identification.md for source/coverage limits.
