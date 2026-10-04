# Settings and appearance

Codex implementer; tier 2 reversible UI/state change, scoped under cleanup-essentials.
Outcome: Settings replaces Manage locations; appearance Light(default), Dark, Match
system preference persists locally. No usage tracking, metadata or removal changes.

Current: compact locations draft sheet, setup-v1 registry, semantic AppKit colors,
no explicit app appearance. All consumers: browser, inspector, pills, native sheets,
popovers and scan detail window. Sidebar and app-menu Settings share one entry.

Use the existing sheet for Settings with an Appearance popup and folder list. Preview
choice live, Cancel restores accepted appearance. Save accepts without starting scan;
changed locations show existing Scan-to-update status. First-run setup retains Scan.
No extra setup step. Save failure keeps draft/preview, offers session-only Apply;
Cancel always restores accepted mode. Appearance-only save cannot dirty scan scope.

State ID appearance (enumeration light/dark/system), default/reset light; persisted via
registry-selected setup-v1 fields. Missing old field defaults light. Invalid type/value
rejects preserved file; no schema shape migration required. No presets, automation,
clipboard, sync, analytics or structured export/import (app preference, not audio
state). Cancel reverses draft; no document Undo. Accessible native named popup. Local
preference only, no network. Preserve roots/online-tags on save.

Apple NSApplication.appearance docs: nil automatically follows system across windows,
views, panels, popovers; aqua/darkAqua override globally. Use this native mechanism,
not polling. Reference https://developer.apple.com/documentation/appkit/nsapplication/appearance
Existing settings/list design research remains applicable; familiar native picker.

Files: CatalogModel/SetupStore/SetupWindow/CatalogWindow, app menu/runtime smoke,
state registry/policy docs, CatalogTests. Risks: preview not reverting, stale draft
persisting online-tag settings, theme failing in sheets, defaults changing roots.

Steps: independent spec critique; registry/model/load/reset changes; settings control
and app-level preview; tests+docs; configured gates; independent review; demo rebuild.
Acceptance: all three values roundtrip; missing=light; malformed preserved; Cancel
reverts preview; failed save retains draft; session apply works; appearance-only Save
does not scan/dirty locations; real popup and Cmd-, work; light/dark captures.
Exact gates via scripts/run_check.py --task cleanup-essentials:
automated_tests build-debug unit-tests integration-tests catalog-state template-integrity
adapter-integrity build-release app-package; runtime_tests catalog-runtime.
Native hooks unavailable; deterministic commands used. Cross-client unavailable;
independent read-only Codex critics/reviewers used. Parent tracking scope stays open.
Resume: specification in review; root sole writer.

Added user scope: public app name Prism and supplied black-on-white burst logo.
Copy original artwork unchanged to Resources/PrismLogo.jpg; standard packaging scales
it for sidebar/Dock without reconstructing the shape. Native UI, app bundle/display
name, executable inside bundle, icon resource, and Quit menu use Prism. Internal Swift
module names, bundle identifier and Application Support/Simplify stay stable to retain
saved collections/settings. Packaging/runtime commands target build/Prism.app.
Verify source artwork, packaged mark, real Dock, and renamed isolated demo.
