# Stateful Feature Completeness

When adding or changing a setting, parameter, preference, editable model field, preset,
project/document state, session state, or synchronized value:

1. Mark the active task domain `stateful-feature`.
2. Read `docs/architecture/STATE_COMPLETENESS.md`.
3. Update the native authoritative registry and
   `docs/architecture/feature-registry.json`.
4. Declare every cross-cutting decision from `.workflow/cross-cutting-policy.json`.
5. Never create an independent handwritten preset field list.
6. Add exact runtime-registry and preset-serializer ID comparison tests.
7. Add non-default round-trip, defaults/reset, old-schema migration, corruption, and
   UI/processor integration tests as applicable.
8. Do not complete while any stateful-feature domain gate lacks current evidence.

An excluded or not-applicable concern requires a reason. A new setting whose policy is
unspecified is a build/gate failure, not future documentation work.
