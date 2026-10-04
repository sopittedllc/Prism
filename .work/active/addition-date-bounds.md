# Addition dates with honest precision

Status: APPROVED — independent Codex group_source_review. Codex root sole writer, tier2.
Parent cleanup-essentials; user explicitly requires both dates finished, no intermediate
milestone is closure. No unresolved product intent: never invent historical dates.

## Outcome
Date added for plugins, samples and libraries gives useful, sortable evidence with its
precision visible: exact qualified/user-confirmed date if available; observed arrival
interval inside monitored locations; otherwise `By <date>` for known presence.
This is presence/addition to tracked storage, not license purchase. Initial inventory
never looks newly acquired. Existing installer record remains distinct in details.

## Research/current state
Existing schema3 nodes retain exact physical identity, first_seen, last_seen, baseline.
root_baselines retains completeness, not trustworthy scan clock/volume/policy continuity.
Apple addedToDirectoryDate includes renames; creationDate is writable. Neither confirms
original acquisition. FSEvents is advisory and can drop events; use scans as evidence.
NI relocation, SINE database reconstruction and Splice redownload invalidate vendor-db
insertion-as-acquisition assumptions. Independent research: group_source_review.
Sources:
https://developer.apple.com/documentation/foundation/urlresourcekey/addedtodirectorydatekey
https://developer.apple.com/documentation/foundation/urlresourcekey/creationdatekey
https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html
https://support.native-instruments.com/support/solutions/articles/69000879243-using-the-repair-relocate-function-in-native-access
https://orchestraltools.helpscoutdocs.com/article/333-deleting-your-sinelibrary-db
https://support.splice.com/en/articles/9792288-how-do-i-re-download-sounds-i-previously-licensed
No production original-addition provider is currently qualified. By-bound is not an
exact addition date and must remain distinguishable in cells/AX/sorting.

## Contract/interfaces
1. Immutable AdditionDateEvidence value with exact / observedArrival(lower,upper) /
presentBy(upper) / unknown, source and exact subject. Bounds finite/ordered; no change
to confirmedAddition reducer semantics. Exact qualification remains separately sourced.
2. Schema4 adds scan_coverage(kind,root,exclusions,policy,volume,root_identity,started,finished) and
node_addition_bounds(node_id,lower,upper,basis). Existing nodes migrate to presentBy
first_seen. Backup before v3 migration, preserve ledger and metadata, rollback failure.
3. Capture scan start and root physical/volume identity before inventory and verify
same root identity after scan. Persist root inode/birth/volume identity and compare
previous/current records, not merely their path or volume. Pass explicit immutable scan context into ingest; no
`date-duration` inference. Direct old ingest callers lacking context produce presentBy
only. Clock rollback or invalid duration prevents intervals and clears continuity.
4. New exact physical identity gets interval only when a previous complete, compatible
root scan proved it absent, both root identities match, exclusions and scanner policy
match, and current scan completes without relevant inventory issues. Lower bound is
previous scan START, upper current finish. Existing identities retain their earliest
bounds; moving within/among known scopes, updates preserving identity and reconnects
do not reset. A new path matching prior node path (replacement) is presentBy; historical
old physical identity returning retains its old bounds. Exclusions/adapter policy/new
root/volume changes are baseline. Intervals describe arrival within monitored locations,
not globally new acquisition; do not badge as newly purchased.
5. Coverage persisted atomically with final inventory. Partial/failed roots break
continuity for that root; project-reference-only issues do not. Overlapping roots pick
compatible most conservative lower bound; no invented absence from unscanned sections.
Library identity is whole library node; instrument-specific dates stay unknown unless
independently qualified (no player/library propagation).
6. Model cached CatalogObservation exposes typed bounds from snapshot. Shared Date
added presentation supplies short exact/By/range text and detailed basis. Plugin group
uses interval arithmetic over actual formats: upper=min known uppers; lower only
when EVERY installation has a finite lower, then min lowers. Any unknown/presentBy
sibling makes the group presentBy (or unknown if no upper); never advertise an exact
or interval group from partial evidence. State partial coverage.
Sort help explicitly says latest known bound first, not newest acquisition.
Sort compares upper bound then lower/precision then stable identity; both directions
unknown-last. Sorting and filters visibly say Date added, details explain bounds.
Plugin receipt remains inspector/per-format secondary evidence; user can inspect it.
7. No manual editor, new settings, background service or collection badge this increment.
UI follows existing column/header/inspector system; don't redesign navigation. No new added-date filters in this increment; sorting only.

## State completeness and risks
Register derived value and two persisted tables under catalog.date_evidence; backup/
migration included; no presets/undo/automation/sync/network. Reset clears derivedcache,
not evidence; deleting local catalog is existing reset policy. AX announces precision.
Privacy stays local; source paths are not uploaded. Versions changing require policy
bump and rebaseline. Synthetic clocks/rootidentity control tests, not installed-content
changes. Risk: 'By' date misleading as acquisition — explicit cell prefix/details;
interval excludes all unsupported histories. Equal path is not exact physicalidentity.

## Implementation sequence
Critic → domain+bounds schema/migration → scan coverage acquisition/ingest → model/table
and inspector/sorting → unit/integration/nativeallcategories fixtures → independent
source/state and UX review. Repair failures before moving on. Continue Last used work
in same parent; this is not a stopping point.

## Acceptance and verification
All3 asset categories × baseline/newarrival/rescan/update/move/offline/replacement;
new roots/exclusions/policy/volume changes; clock rollback; incomplete coverage;
same-volume root replacement; mixed exact/interval/presentBy/unknown groups; all
supported schema migrations with backup, ledgerpreservation, reopen, corruption, atomicrollback.
Actual native clicks sort both directions; bound prefixes visible light/dark1040/1220;
unknown last, no false new-acquisition display, AX details include basis.
Exact commands:
python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package
python3 scripts/run_check.py --task cleanup-essentials --gate addition_bounds_runtime catalog-runtime
python3 scripts/workflow_gate.py check-complete
Parent remains open until actual Lastused matrix and full release criteria satisfied.

## Files/resume
Core new AdditionDateEvidence.swift; CatalogStore.swift; scanner context/model bridge;
CatalogModel/Window; tests/core/catalog; native smoke; schema frozenfixture; feature
registry/statecompleteness/designsystem/matrix. Current next: independent critique.
Alternate ClaudeOAuth unavailable previously; independent Codex fallback recorded.

## Reviewed continuity correction
Independent critic group_source_review approved retaining a prior absence bound through
A→B→A settings changes with no intermediate scan/load. Continuous selection/monitoring
is not claimed or required: a compatible historical absence and current presence bound
an arrival or return. Root physical identity/policy/exclusions/clock must still match.
Existing node history wins. Clearing omitted roots at load/scan is conservative policy,
not a mathematical requirement. No setup epoch is introduced. Test no-scan roundtrips.
