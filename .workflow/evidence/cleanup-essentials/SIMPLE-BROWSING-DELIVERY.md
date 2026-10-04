# Simple browsing delivery — Codex

Scoped UI implemented and isolated fake-data demo rebuilt/launched. Single name/tag
search, reversible native column-header sorts, no recent/facet/usage toolbar or Technical
details sheet, concise inspector and adjacent Location/Finder. Existing online opt-in,
source provenance, tag editor, Undo and format management remain reachable.

Verification: automated_tests.json and runtime_tests.json pass at content:079b6dc8dc0e7e53c4b343e1797d6a9cbcc5fa7fe3acbf5d57511823b4bc88e0.
86 tests; native actual header clicks in both directions, selection retention, compact
columns, editing/Undo, tag settings, light/dark views and synthetic removal regression.
Read-only source and seven-image visual review: /root/simple_review; final smoke-label
and tag-settings image follow-up recorded separately. Claude cross-client unavailable;
independent Codex roles used. VoiceOver user testing not performed.

API reference: https://developer.apple.com/documentation/appkit/nsoutlineviewdatasource/outlineview(_:sortdescriptorsdidchange:)
Specification: .work/active/simple-browsing.md; independent /root/simplify_spec PASS.
Native client hooks unavailable; deterministic scripts/run_check.py gates executed.

Parent cleanup-essentials stays unfinished: real four-host usage, reliable installed
dates, measured plugin/library sizes and broader removal remain pending. Unknown dates
are not inferred from scans; unknown-only date sorts therefore keep stable name order.
workflow_gate.py check-complete correctly fails on pending parent criteria/gates, so this
is a scoped UI delivery, not project/release completion. No commits or publication.

Resume: demo title Simplify Demo — Simple browsing (fake data). User testing can continue.
