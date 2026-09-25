# Evidence

Each task stores immutable gate evidence under `.workflow/evidence/<task-id>/`.
Evidence is tied to an exact revision and follows `schemas/evidence.schema.json`.
Logs may be referenced from evidence but a prose claim alone never satisfies a gate.
