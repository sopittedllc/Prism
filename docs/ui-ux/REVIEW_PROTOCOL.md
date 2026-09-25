# UI/UX Review Protocol

Review the assembled workflow, not only changed lines.

## Blockers

- Primary workflow cannot be completed or loses user work.
- Control has no clear result, feedback, or recovery.
- Keyboard, screen reader, scaling, localization, or required host/device layout makes
  the workflow inoperable.
- A destructive action is easy to trigger accidentally or misstates its consequence.
- UI mutates real-time/DSP state outside the approved parameter contract.
- Error, empty, loading, permission, offline, or interrupted state is missing where
  reachable.
- Text overlaps, clips critical information, becomes unreadable, or creates inaccessible
  contrast in a required configuration.
- Runtime behavior was inferred from code or a single screenshot.

## Review passes

1. **Workflow:** Can the intended user discover, complete, verify, undo, and resume?
2. **Composition:** Is anything redundant, contradictory, misplaced, or competing?
3. **Hierarchy:** Is the next action and current state obvious at a glance?
4. **State completeness:** Exercise every reachable state and transition.
5. **Input equivalence:** Pointer/touch, keyboard, assistive tech, and domain inputs.
6. **Adaptation:** Minimum/maximum size, scale, text size, locale, RTL, theme, host.
7. **Accessibility:** Semantics, traversal, targets, contrast, motion, audio equivalents.
8. **Copy:** Specific, concise, consistent, actionable, non-blaming, localized.
9. **Performance:** Response, scroll/resize, meter repaint, launch/editor-open behavior.
10. **Regression:** Neighboring flows and visual references remain correct.

## Evidence grades

- **E0 — assertion:** no evidence; cannot pass.
- **E1 — static:** code inspection or a single image; useful but insufficient.
- **E2 — automated:** structural test, accessibility audit, screenshot matrix.
- **E3 — runtime:** representative device/host interaction with reproducible steps.
- **E4 — measured:** performance, perceptual, usability, or hardware data against a
  numeric threshold.

User-facing completion requires E2 plus E3. Performance or real-time claims require E4.
