---
name: design-feature
description: Research and specify a systemic, accessible UI/UX improvement before implementation.
argument-hint: <workflow or UI improvement>
disable-model-invocation: true
---

Use the ux-architect for `$ARGUMENTS`. Mark the active task with domain `ui-ux`.
Inventory the entire semantic family and existing routes before proposing a change.
For unknowns, require current official guidance and at least three comparable use
cases. Have the specification critic review the result. Proceed autonomously unless a
material creative choice lacks a safe reversible default.

If any designed control introduces or edits state, also mark domain `stateful-feature`
and specify its complete cross-cutting policy before implementation.
