# Required-host usage validation matrix

2026-09-25. This is an acceptance protocol, not a compatibility announcement.
The identity work is independent of usage: installed content does not establish use.
Sources and known local signals: [activity research](daw-activity-history.md).

## Current capability, by evidence

| Host | Plugins | Loose samples | Kontakt / SINE instruments | Historical date |
| --- | --- | --- | --- | --- |
| Logic Pro | No validated saved-state identity adapter | Project metadata candidates; active-alternative and path semantics unvalidated | No validated adapter | Unknown; AU validation is not use |
| Ableton Live | Partial saved descriptor name candidates; not installation identity | Saved path candidates; resolution and collected-copy semantics incomplete | No validated adapter | Project modification proxy only; restore attempts can fail |
| Cubase | No implemented adapter; optional usage logging is a research route | No validated adapter | No validated adapter | Unknown; absence of optional logs means no evidence |
| Pro Tools | No implemented adapter; host-instantiation logs are a research route | No validated adapter | No validated adapter | Clock anchor/outcome not validated |

All four require controlled host-generated fixtures. REAPER test coverage cannot
satisfy a row here. Synthetic parser inputs prove parser boundaries, not host support.
No per-host row currently qualifies for an “unused” cleanup recommendation.

## Fixture record

For each host/version and format (Logic AU; Live AU/VST3; Cubase VST3;
Pro Tools AAX), record: OS version, host version, plugin/player version, source kind,
local fixture identifier, logical asset ID, installation locator, project identity,
expected reference/outcome, observed fields, timestamp meaning, observation window,
and pass/fail/unavailable with reason. Keep raw projects/logs in private local test
storage; only redacted synthetic fixtures and aggregate verdicts enter Git.

Each fixture contains one loose audio file, one plugin, one Kontakt instrument and
one SINE instrument with a known library parent. Include two similarly named patches
from different products so filename-only matching fails. Use a second microphone
position for SINE to test that content files do not become extra instruments.

| Scenario | Saved inclusion expectation | Load history expectation | False-positive guard |
| --- | --- | --- | --- |
| Save without transport playback, including muted/disabled tracks | Included when serialized | Only if successful load observed | Playback is not required |
| Open, save, quit, reopen | Same asset identities and project | Distinct observed sessions, not every log line | Deduplicate repeated events |
| Load then remove before saving | Not in final saved state | A past successful load may remain | Keep evidence kinds separate |
| Missing plugin / failed restore | Unresolved saved reference if present | Attempt/failure, not success | Never count failed restore as use |
| Plugin validation scan only | None | Validation, excluded | Startup enumeration is not loading in a project |
| Browser audition / preview only | None | Preview, excluded | Player process alone is insufficient |
| Collect/consolidate/copy samples | Included local copy | Do not attribute original automatically | Exact path or validated equivalence required |
| Freeze / flatten / render | Host-specific; inspect serialized retained state | Do not infer original from rendered audio name | Record retained vs removed source |
| Alternative/version/backup | Inclusion belongs to specific saved version | No current-project claim for stale versions | Validate active-version semantics |
| Relocate library / unplug drive | Retain reference, availability separately | No new load inferred | Absence is not deletion or unused |
| Rotate/delete log / disable logging | Saved evidence unaffected | Coverage becomes incomplete | No invented historical zero |
| Load one Kontakt/SINE patch | Only that patch and owning library aggregate | Same exact identity requirement | Do not mark siblings/all player libraries used |

## Adapter admission

An adapter is admitted per evidence kind and asset type, never by host name alone.
Require positive and negative fixtures above; stable identifiers or explicit candidate
status; bounded parsing; cancellation; version/schema rejection; exact timestamp
semantics; and preservation of unknown coverage. A failure does not downgrade to
filename matching presented as verified use. Project-modified dates are labeled
“Project updated”, not exact “Last used”. Never-used cannot be established from a
finite or incomplete scan.

Next work: inventory available host versions read-only, generate controlled projects
where automation is available, and validate one evidence kind at a time. No host
logging changes, plugin execution, or privileged monitoring are part of this scan.
