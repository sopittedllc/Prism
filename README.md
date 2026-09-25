# Simplify

A free macOS audio collection manager supporting Altadena Girls, currently available as a
native browser preview with reviewed plugin removal. The intended app has Plugins, Samples, and
Libraries views with classification, project-reference recency, and reviewed removal.

Build with `swift build`, package with `swift build -c release
python3 scripts/build_app.py`, then open
`build/Simplify.app`. Follow setup to add sample/library/project locations, then Scan.
Standard plugin folders are enabled by default. Command-F focuses search; Command-R scans.
Accepted folder setup is remembered on this Mac; filters and results last for this session. Plugin formats can be moved to Trash after exact-path confirmation. No sample/library removal or tag editing yet.

The CLI remains available: `.build/debug/simplify-probe --help`.

```sh
.build/debug/simplify-probe --standard-plugins
.build/debug/simplify-probe --samples "$HOME/Music/Samples" --libraries "$HOME/Music/Libraries" --projects "$HOME/Music/Projects"
```

Only specify folders you intend to inspect. Reports contain local paths. The scanner
never loads plugins, changes scanned files, or deletes content. Exit 2 means issues
were reported; exit 0 still does not imply complete project dependency coverage.

Implemented: plugin bundle candidates, audio-file candidates, immediate library-folder
candidates, bounded experimental REAPER, Ableton, and Logic metadata readers, provenance, and
exact-path sample matching for the supported REAPER subset. Ableton and Logic paths remain
unresolved candidates. REAPER plugin declarations can produce explicitly labeled, unambiguous name-match candidates. Other DAW plugin references remain unsupported; these are not verified installation dependencies.

"Latest referencing project modified" is a file-date proxy, not the date an asset was
added or played. No references found only describes this scan. Copied samples, opaque
player state, unsupported DAWs, and unscanned projects may conceal dependencies.

See [product scope](PROJECT.md), [toolchain](TOOLCHAIN.md),
[project-reference findings](docs/research/project-references.md), and
[ecosystem research](docs/research/audio-ecosystems.md).

The supplied icon is used with its original transparency intact. Packaging only resizes it and places it on a white rounded Dock tile.
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
The preview limit is100,000 entries per category, with explicit partial-scan status;
a large sample tree no longer prevents project discovery. Scan results are session-only.


Library discovery now reads Kontakt manifests/instrument names, installed SINE
catalog entries, Soundpaint part tags and recognized STEAM product structure. It
excludes arbitrary folders. Search includes instrument names and derived tags; inferred
identity and partial scans remain labeled. This is not complete player or usage coverage.
Plugins show Name and Last used (Unknown without reliable activity evidence); format
installations and reviewed Trash remain in details. Latest branding source is the exact
user-supplied JPG. See docs/research/library-identification.md for source/coverage limits.
