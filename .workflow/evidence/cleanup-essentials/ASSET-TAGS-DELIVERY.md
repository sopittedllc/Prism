# Asset presentation and automatic product tags

This is a scoped increment within cleanup-essentials, not completion of the parent
cleanup or four-host usage requirement. Driver: Codex. Independent design/research,
specification critique and source review: Codex agents. Claude cross-client fallback
was unavailable because the CLI was not logged in. Native hooks were unavailable;
deterministic repository checks ran directly.

## Changes
- Plugin/library/instrument names show tag summaries. The main inspector leads with
  tags, Last used, Installed, Size and formats/player; full paths/raw evidence are in
  Technical details. Plugin formats are visible in the list. Compact library lists
  retain size and Last used; player identity stays in the inspector.
- Optional Fetch product tags online setting, persisted locally and off by default.
  Exact recognized products fetch official sources automatically after scans/restores.
  Current sources: Spitfire Symphony Orchestra, BBC Symphony Orchestra Core, Berlin
  Strings, Cinematic Studio Strings, Cinematic Strings2, FabFilter Pro-Q4.
- Reviewed product-description fingerprints admit reviewed taxonomy fields. This is
  limited coverage, not arbitrary website understanding. Changed text fails closed;
  unrelated/negated/store-administrative terms are not guessed into tags.
- Seven-day local source cache, source URLs/fetch dates, retry/failure status, no
  cookies/credentials or local paths sent. Explicit user edits and empty suppression
  win; product tags never propagate to individual patches. Plugin Function added.
- Last used dropdown supports All/Unknown. Date ranges remain disabled because no
  host adapter has been admitted. Installed dates remain Unknown; First found/indexed
  stays separately named. No website or file timestamps become installation/use dates.

## Verification and review
85 deterministic tests passed, including 25-source queue progression after failure,
cache version/descriptor upgrades, cancelled late-error exclusion, edit precedence,
no patch promotion, identity mismatches and changed-content rejection. All six sources
passed the actual client network probe. Exact state registry, CLI integration, template
and adapter checks, debug/release builds and packaging passed before final layout repair.
Fresh final revision evidence is recorded in adjacent automated_tests/runtime_tests JSON.

Source review PASS after stale-error and obsolete-cache fixes. Visual findings led to
retaining library breadcrumbs and metadata-only guidance, suppressing impossible empty
expansion guidance and fitting compact table columns using rendered extents.
Native runtime PASS with 42 captures, including online-tag fetch/disable, technical details, plugin lifecycle facts and compact column geometry. Independent visual review PASS for the light/compact-dark slice; no remaining blocker in reviewed states.

## Remaining requirements
Actual last-used tracking across Logic Pro, Pro Tools, Live and Cubase is unimplemented.
Reliable installation dates, plugin/library measured storage and streamlined removal
remain parent work. Last-used history cannot currently drive an age-based cleanup.
Manual VoiceOver, high contrast/zoom, macOS13 and Intel are unverified.

The isolated demo contains only fake installations, including six recognizable product
names for actual online metadata requests; no commercial audio/plugin payloads are
included. Its title explicitly identifies fake installations. Real library drives
remain unnecessary for this demo. No real audio was removed and no release published.

Final artifact verification: automated_tests, runtime_tests and scoped source/UX review all PASS at content:008e7bfe8037b8306b6b75976d678531995249a25189426a3674f5bc21e2c903. The demo was rebuilt, ad-hoc signed and launched with online tags enabled. Parent check-complete remains FAIL because real usage, measured storage and removal requirements/gates remain pending; no parent completion claim.
