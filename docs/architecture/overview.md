# Architecture overview

The first slice is a dependency-free macOS Swift package. SimplifyCore provides
immutable scan results, read-only inventory, bounded project parsing, and explicit
reference provenance. SimplifyProbe is a thin CLI consumer producing local JSON.
CZlib exposes the system zlib solely for bounded ALS gzip decoding.

Scanner is synchronous and belongs off the UI thread. Each call owns its state.
It skips symlinks, packages, and hidden descendants; library roots suppress loose-sample
enumeration. Assets are location candidates, not safe deletion units. Results report
unavailable roots and truncated scans. Metadata reads reject nonregular files through
descriptor validation. Filesystem races and malicious concurrent directory replacement
are not fully isolated by this prototype; scans have no mutation capability.

ProjectReader supports experimental RPP and ALS subsets. It preserves unresolved
candidates and never loads plugins. Matching uses explicit resolved paths, not names.
A matched reference yields saved-project recency, never exact use time. Unsupported
formats remain visible. No catalog database exists; accepted folder setup has a separate local versioned store.

Future catalog persistence, user tags, folder bookmarks, background reconciliation, and removal
must follow the state-completeness contract before implementation. No vendor uninstaller integration exists.

The native AppKit browser uses a MainActor CatalogModel, immutable background scan
snapshots, and one in-flight operation. CatalogStateRegistry and feature-registry.json
define view controls and setup persistence participation. SetupStore atomically stores only roots, the standard-plugin toggle and onboarding completion in version 1. Other view state is session-only. Bounded reads reject corrupt, oversized, nonregular and unsupported-version files; the wizard can use a draft for one session if saving fails. There is no preset serializer.
The launcher can preselect an explicitly supplied --project-root without scanning it.
CatalogTheme adapts Projector typography/spacing/panel/accent roles.
