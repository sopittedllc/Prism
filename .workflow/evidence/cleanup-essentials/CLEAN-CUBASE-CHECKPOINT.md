# Clean Cubase controls — research checkpoint

Acting client: Codex. Root sole writer; independent read-only reviewer:
/root/clean_cubase_review. No product source changes or host operations.

User supplied three new empty-project controls. All identify Cubase 15.0.30.

| Session | Typed records | Target descriptors |
| --- | ---: | --- |
| Empty | 10 | None |
| Baseline | 123 | Pro-Q 4, Kontakt 8, Diva; one each |
| Diva removed | 100 | Pro-Q 4, Kontakt 8; one each |

Other records are built-in Input Filter, EQ and Standard Panner. Record counts
are not instance counts. Four Diva text labels remain in the removed file,
including track/name and OwnInputBus/RecorderBus contexts. They are not typed
Plugin UID → Plugin Name descriptors. This validates the clean fixture delta;
it does not resolve ownership of records in the older template fixture.

Research layout source (author implementation; not Steinberg documentation):
https://github.com/fgimian/cubase-project-plugins/blob/c324cdc82548cc05e9453cd12a30ccae7551768f/src/reader.rs

Reproducible bounded research probe: build/usage-controls/cubase-record-probe.py.
Private records/hashes: build/usage-controls/new-cubase-replay.json. All three
original hashes matched the initial read after analysis. Independent reviewer
reimplemented extraction and verified all 233 records, offsets, identities and hashes.
No personal session data copied into product source or committed fixtures.

Admission boundary: globally located typed descriptors remain candidates.
This does not prove general current ownership, bypass behavior, successful load,
exact last-used timestamps, sample identity or individual Kontakt library identity.
No CPR production adapter was admitted by this check. Next admission requires
ownership/version/failure-boundary specification and synthetic adversarial tests,
including matching descriptor bytes embedded in unrelated state. The remaining
player identity and timestamp contracts still apply to all four hosts.

Native hooks unavailable; this is a research checkpoint, not product completion.
Prior implementation gates are unchanged; parent completion remains open.
