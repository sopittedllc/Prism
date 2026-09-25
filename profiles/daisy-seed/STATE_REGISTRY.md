# Daisy Seed State Registry Reference Architecture

Keep one compile-time/static registry for every controllable and persistent state ID:
type, default, range/units, preset scope, nonvolatile/project scope, migration, control
mapping, and every cross-cutting policy. DSP, control scanning, preset storage, default
reset, host tests, display/UI, MIDI mapping, and serialization consume this authority or
prove exact ID coverage.

Preset save enumerates included registry definitions into a versioned bounded format;
it does not copy an independent field list. Loading validates size, checksum/version,
IDs, types/ranges, and migration into a temporary snapshot before an atomic handoff to
runtime state. Power loss must leave either the old or new valid preset, never a partial
one. Define wear-leveling and unknown/newer-schema behavior when nonvolatile storage is
used.

Host tests export runtime and preset IDs for `scripts/feature_coverage.py compare`,
round-trip distinct non-default values, migrate released binary/JSON fixtures, fuzz
corrupt/truncated storage, and verify safe defaults and audio behavior on target.
