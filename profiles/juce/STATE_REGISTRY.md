# JUCE Parameter and State Registry Reference Architecture

Use the processor's authoritative parameter layout/state model as executable truth.
Attach cross-cutting metadata to stable parameter/setting IDs and test exact coverage.

- `AudioProcessorValueTreeState` parameters naturally participate in processor state
  when the complete state tree is serialized. Do not separately copy a selected list of
  parameter values into presets.
- Non-parameter state still needs a registered stable ID, type/default, scope, and every
  policy from `.workflow/cross-cutting-policy.json`.
- UI attachments connect controls to parameters; their lifetime order is explicit. The
  editor is never required for preset save/load or correct processing.
- Host automation identity, normalization, range, default, units, display/parsing, and
  preset identity refer to the same parameter definition.
- A UI-only preference, device choice, oversampling mode, random seed, file reference,
  or hidden compatibility field is not automatically a preset parameter: declare its
  scope and reason.

Serialize a versioned root state with stable child/property identifiers. Validate and
migrate a copy before replacing live state. Define unknown property/child handling and
preserve forward-compatible data when policy requires it. Never apply half a corrupt
preset or mutate audio-thread state directly from deserialization/UI.

Required tests export all native parameter/non-parameter state IDs and every ID emitted
by the preset serializer, compare exact sets with `scripts/feature_coverage.py compare`,
round-trip unique non-default values, migrate every released fixture, open/close the
editor, restore sessions in representative hosts, and verify automation after recall.
