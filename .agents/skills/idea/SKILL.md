---
name: idea
description: Turn a creative product idea into a risk-classified, testable task and run it autonomously through the reliability workflow.
argument-hint: <creative idea or improvement>
disable-model-invocation: true
---

Use the orchestrator agent for `$ARGUMENTS`. Preserve the user's creative intent.
Generate objective acceptance criteria, classify the risk tier, and proceed without
asking about implementation mechanics. Ask only when a material product choice has no
safe reversible default or when tier-3 authority is required. Continue through repair
and regression gates until verified completion or the bounded-repair limit.

If the idea adds or changes settings, parameters, preferences, editable fields,
presets, project/document state, or syncable/session state, add domain
`stateful-feature` and apply `docs/architecture/STATE_COMPLETENESS.md` automatically.
