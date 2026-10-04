# Samples drive snapshot — 2026-09-26

User requested an offline structure capture, then narrowed scope to Samples only.
Complete local snapshot is retained privately under the current user's
`Library/Application Support/Prism/Research Snapshots/` directory. The
portable, path-free aggregate is `tests/fixtures/samples-drive-aggregate.json`.

2,150,069 files, 162,992 directories, 83 symlinks. Zero read errors; five system-maintenance directories excluded. SQLite integrity and directory rollups passed. inventory.sqlite, README.md, FOLDER-TREE.txt, query.py and volume metadata retained on internal storage. No payloads copied, no Last used/install time inferred, no drive mutation. Backups excluded. Root notified user that drive reads are finished and Samples can be ejected through Finder. Future work can query this snapshot without reconnecting; actual sample playback or instrument binary parsing still requires source files.

Follow-up offline analysis: DISCOVERY-FINDINGS.md beside the snapshot records collection nesting and scale gaps. Scoped library-container-traversal.md fixes unowned Samples-container traversal; exact identity, complete indexing and Last used remain separate outstanding work. No drive reconnection was needed.
