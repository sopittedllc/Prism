# UI/UX Operating System

UI work is not complete when it compiles or resembles a screenshot at one size. It is
complete when the intended workflow remains understandable, operable, accessible, and
visually coherent across its declared states, inputs, sizes, and hosts.

## Required lifecycle

```text
workflow evidence
  → composition inventory
  → design specification
  → specification critique
  → implementation
  → automated structural/accessibility checks
  → screenshot matrix and visual comparison
  → real interaction test
  → UX review against the original user outcome
```

No user-facing component is designed in isolation. Inspect its parent, siblings,
navigation context, competing actions, empty/loading/error states, and the workflow
before adding or moving controls.

## Governing principles

1. **Workflow before surface.** Optimize the complete user job, not the requested
   control in isolation.
2. **Hierarchy before decoration.** Importance, sequence, grouping, and status must be
   legible without relying on color, animation, or explanation.
3. **One clear primary action.** Multiple entry points are allowed only when their
   contexts serve different user intentions.
4. **Recognition over recall.** Keep necessary state, units, constraints, and next
   actions visible at the decision point.
5. **Immediate, truthful feedback.** Distinguish accepted, pending, completed, failed,
   disabled, unavailable, and destructive states.
6. **Reversible by default.** Preserve work, support undo/cancel, and confirm only
   consequential actions.
7. **Accessible by construction.** Semantics, focus, keyboard, contrast, scaling,
   motion, and nonvisual equivalents are part of the design contract.
8. **Platform-native unless evidence justifies custom.** Familiar behavior reduces
   learning cost and accessibility defects.
9. **Progressive disclosure.** Keep the primary path clear while making advanced
   control discoverable and persistent.
10. **Measured density.** Professional does not mean cramped; compact interfaces still
    need readable grouping and reliable targets.
11. **No silent loss.** User input, edits, presets, sessions, and selection survive
    predictable interruptions or fail with recovery.
12. **Test the composition.** Component correctness cannot prove the assembled screen.

## Sources of truth

- `PROJECT.md` and the primary workflow.
- `docs/ui-ux/DESIGN_SPEC_TEMPLATE.md` for each meaningful change.
- Installed profile UI rule for platform behavior.
- Current official platform guidance for claims likely to change.
- Runtime evidence, not designer or model confidence.

Use `OFFICIAL_REFERENCES.md` as the initial authoritative route list, then verify the
current source and pinned framework version for the task.
