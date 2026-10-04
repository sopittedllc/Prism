# Live Last used: completed restores with source-local dates
Status: APPROVED — independent Codex spec critic group_source_review passed after identity/replay/lifecycle corrections. Codex root sole writer.
Tier2, cleanup-essentials active goal; not a stopping milestone or four-host completion.

## Outcome and evidence
Expose real historical positive use for exactly identified VST3 classes/products from
Live12.4.5/12.4.6 completed document restores, automatically collected, persisted,
sortable and explained in Last used. Include muted/unplayed instances. Do not treat
browserpreview, scans, attempts, failure, old mappings, or filename guesses as use.

Native controls now show complete baseline→3 plugin restores, removed→2. Missing-UID
synthetic copy crashes after Going to restore Diva without completion; no Diva use.
Source .als UIDmatcheslog CID. Live-plugins-1.db schema(version1,platform2) maps exact
CID→modulepath, including currentQ4/K8/Diva; one duplicateCID in fullcatalog establishes
need for ambiguity rejection. Private evidence build/date-evidence/live-*-clock.json.
Native log grammar uses `cid`, not `uid`:
Loading document "path.als" → Going to restore:name → processor successfully loaded:
vendor 'name' vVERSION (cid:{GUID}) → Restored:name → Loaded document was created by
Ableton Live VERSION → Begin/End ExchangeDocument. Exact fences require nativecontrols.
Outside that fence, events do not establish project use. Initial scope only restorations;
new unsaved insertions remain uncovered until qualified independently.

## Clock contract
Success and identity independent of precision. Log ISOlocal timestamps have no offset.
Store strict Gregorian components incl microseconds, timezone unknown; display date
with DAW local qualifier. Never append Z/currentzone or fabricate AssetDateEvidence
absolute eventDate. Preserve existing confirmedUse.eventDate semantics. No UTC envelope
or definite age cutoff admitted from unknown-zone events. Sort latest REPORTED local
calendar date with explanatory help, not absolute chronology acrosshosts/zones.
Independent critic group_source_review endorsed civildate preservation. Research:
https://www.rfc-editor.org/info/rfc5545/
https://www.rfc-editor.org/info/rfc9557/
https://www.iana.org/time-zones/theory
https://help.ableton.com/hc/en-us/articles/5301568366354-Reading-Ableton-Live-Crash-Reports
https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical%2BDocumentation/VST%2BModule%2BArchitecture/ModuleInfo-JSON.html

## Interfaces and admission
1. SourceLocalTime strict Gregorian year/month/day/hour/minute/second/microsecond,
roundtrip component validation, comparison explicitly civil. Unknowntimezone persisted.
HostUsageProvenance optional Codable in existing evidence payload: pinned source ID,
hostversion, exactCID, log record identity, sourceLocalTime, completed-document-restore
qualification and stable source run/record hashes. Cache schema/snapshotdigest are
transient association diagnostics, excluded from immutable evidence equality. Kind confirmedUse and eventDate=nil.
Source/provenance validation rejects contradictory or malformed combinations.
2. Pure bounded LiveUsageLog parser, wholefile<=32MiB, max4096 completed events,
line<=32KiB, documentwindow<=120seconds/localmonotonic timestamps, no embedded newline
identity guessing. Multiple explicit Init Version records resetrun parser context;
unsupported versions reject/skip source with explicit coverage, no crossrun pairing.
Require one matching Going→loadedCID→Restored sequence and successful documentfence.
Interleaved matching operations, failures, malformed lines, truncated document, changed
names/UID resetpending operation; never salvage attempt as success. Unrelated known
UI-warning lines do not imply restorefailure. Duplicate restoreinstances preserved in
source parser but collapse only by stable immutable eventID inledger.
3. Installed association via static moduleinfo CID where available or Live cache1/2:
readonly SQLite transaction, boundedrows/UTF8, exact dev_identifier regex and schema;
all matchingCID rows inspected, current conflicting modulesreject. Enabled/scanned
values1 observed; unknownvalues unsupported. Cache module fingerprint size/mtime is
staleness screen, not cryptographic evidence. Verify exact currentbundle root/executable
physical identity, cache/current executable fingerprint consistency; source logversion retained separately; no genericversionnormalization or
plugin execution. Unique node binding mirrors receipt binding pre/postvalidation and
latest catalog header match. Historical subject is the VST3 class, NOT physical bytes. Provenance explicitly stores
classID and subjectScope=pluginClass. Ledger attaches an immutable class-history
association to a current node only after exact current class membership verification;
UI says product history, not proof that this installation/format was used. Version
is preserved as source metadata, not a same-version continuity proof. Replacements
may show the same class history; no claim of physical installation lineage is made.
4. Collector enumerates only known local Live log roots andcache, boundedfilecounts/
bytes/runtime/cancellation, no projects or sample content uploaded. Source event identity
includes run fingerprint and line identity/position, stable across append/replay;
never use entire growingfilehash for eventID. Canonical identity is SHA256 of JSON
UTF8 array [sourceID, exact Init Version line, relative byte offset from that Init
line to completed Restored line, exact Restored line, exact CID, current nodeID].
Require explicit Init line; byte-identical copied/rotated log events replay. Append
does not alter IDs. Truncated prefix lacks Init and is unadmitted; repeated identical
Init lines with identical relative records conservatively deduplicate rather than
invent additional use. Wholefile hash is observational diagnostics, excluded from
immutable payload (which retains stable run/record hashes). Rename has no influence.
Cache: max10000 rows, 4096 bytes per field, 8MiB text, schema1/platform2 only; logs:
max16 known version dirs, 32MiB each, 64MiB cumulative, 4096 events each/8192 total,
30second total monotonic deadline. Collector checks cancellation perfile/perrow/event
and at queued store entry and precommit. Corrupt/unsupported sources yield coverage
issues and never delete previously valid historical evidence.
5. Catalog/model reads typed usage projection atomically, retains oldhistory across
reopen/move/offline, rejects corrupt data. Last used cells/inspector qualify DAW-local
clock and partialcoverage; plugin groups never imply allformats used. Select latest civil tuple then stable
sourceID/eventID byte order, retain source qualifier and coveredclass/format counts.
Absolute records get separately derived display civil date in explicitly chosen
user timezone for date-only sorting; no tie breaks pretend precise chronology between
clock domains. EventDate reducer remains separate and unchanged. Library/sample
children remainunknown untiltheir ownqualified source. Unknownnevermeansunused.
Automatic collection after successfulplugin scan and lightweight changed-source checks
every60seconds while app running, only size/mtime/inode-changed sources trigger parse.
One pass at a time; scan changes cancel old pass, coalesce to latest snapshot.
Changed-source skip keys include inventory node IDs and class-mapping/cache identity;
new/replaced nodes or cache changes force reparse/rebinding even if log is unchanged. Stop
poll task on model shutdown/reset; weak model capture avoids retention. No
backgroundservice or intrusive hostautomation. Reset/scope/removal
cancelpendingwork; latecallbacks cannotbind replacednodes. Existing history remains.

## Coverage and non-goals
This supports tested LiveVST3 documentrestore positives only; no universalnon-useclaim,
AU/VST2, unsaved insertion, other3hosts, loose samples or Kontaktinstrument propagation.
Parentgoal continues those sourcequalifications after this endtoend implementation.
Root sole hostoperator. No installedplugin mutations, originalproject writes, upgrades,
externalservice actions or vendorlibrary execution. Cache/scanner metadata read-only.

## Verification and files
Pureparser tests success/failure/ambiguous/truncation/runreset/unsupportedversion/
wrongdate/leapday/DST-lookingtime/changedmachinetimezone/budgets/duplicates/embeddeddecoys.
Binding tests exactCID/collision/stalecache/version/replacement/physicalrace, replay,
rollback, sourcecorruption, reopenedhistory. Native baseline/removed/missingUID controls
and scanner/browsernegative fence controls; no attemptcredits. UI sort/qualifier/AX,
savedstatus/error and noinstrumentinheritance. Endtoend scan→ledger→Lastused native.
New core reader/time/provenance/collector; CatalogStore + dateResolver optional payload;
CatalogModel/Window; core/model/native tests; state/design/research docs.
Commands:
python3 scripts/run_check.py --task cleanup-essentials --gate automated_tests build-debug unit-tests integration-tests catalog-state template-integrity adapter-integrity build-release app-package
Native check exactargv registered beforeuse; catalog-runtime plus isolated Live source
binding runtime; hostfixtures rehashed. Independent source/state/UI review required.

## Resume
Next independentcritique; resolve fence/identity constraints beforeproductioncoding.
No exactUTCclock precondition blockscivil-date evidence. Parent remainsactive until
allpriorityfeatures genuinely qualified, not until one adapter passes.

## Implementation/native discoveries
- Native Live uses bounded AMidiIO multiline continuation blocks before final document
  commit. Only exact Midi Remote Scripts/Midi Devices headers and observed continuation
  prefixes are allowed; unknown unframed lines invalidate pending document.
- Cache GUIDs use mixed hex case; normalize ASCII hex only before collision checks.
- Native adapter control passed: 3 baseline VST3 classes, 14 historical associations for
  3 installed products, 0 source failures, 1 incomplete/crashed document rejected; repeat
  collection preserves event count and first ingestion. Evidence gate live_usage_native.
- Parser/cache/store/model independent review repaired deadlines, severity/run boundaries,
  byte identity, scan/read/poll races and wrong category status. Full rerun/UI pending.
