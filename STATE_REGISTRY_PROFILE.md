# Generic State Registry Reference Architecture

Create one native typed registry containing stable IDs, types, defaults, constraints,
scope, and every cross-cutting policy. UI, preset/project serialization, reset,
automation, accessibility, sync, and export consume the registry or prove exact ID
coverage against it. Do not maintain parallel handwritten lists.

Expose deterministic test-only exports of all runtime registry IDs and all IDs emitted
by the preset serializer. Compare them with `scripts/feature_coverage.py compare`.
Round-trip unique non-default values, migrate frozen fixtures from every released schema,
validate before atomic apply, and test unknown/corrupt/wrong-type data according to the
declared policy.
