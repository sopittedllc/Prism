# Systemic UI Change Protocol

A visible defect is evidence about a system until proven local. “Fix this header” means
“determine why this semantic header differs, inventory every equivalent header, repair
the governing rule, and verify all consumers.” It does not mean blind global search and
replace: visually similar elements may have different semantic roles.

## Required sequence

1. **Name the semantic role.** Example: primary screen title, inspector section header,
   dialog title, parameter group label—not merely “text at 16 pt.”
2. **Locate the authority.** Identify the design token, component, modifier/look-and-
   feel method, asset, theme, layout primitive, or missing abstraction that should own it.
3. **Inventory every consumer.** Search code, previews, storyboards/resources, tests,
   screenshots, docs, and host/platform variants. Record included and excluded instances
   with reasons.
4. **Sample the compositions.** Read parent and sibling layouts for representative
   consumers. A token change can break hierarchy even when it creates consistency.
5. **Research unknowns.** Use the current official platform guidance and at least three
   materially comparable use cases. Compare context, user, density, input, and failure
   modes; do not copy aesthetics without mechanism.
6. **Choose the systemic level.** Fix the token/component/contract when consumers share
   semantics. Split an overloaded token when they do not. Use a local override only when
   the exception is explicit, documented, and regression-tested.
7. **Update the system.** Change implementation, design-system inventory, examples,
   specification, and tests in one task.
8. **Verify blast radius.** Capture every affected representative composition across
   the state/size/accessibility matrix, not only the reported screen.
9. **Prevent recurrence.** Add lint, snapshot, unit, accessibility, or architecture
   enforcement appropriate to the failure mechanism.
10. **Learn.** Add an evidence-backed knowledge entry when the rule will matter again.

## Systemic impact report

Every UI task produces a report containing:

- reported symptom and semantic role;
- root design-system mechanism;
- searches performed and inventory counts;
- consumers changed;
- consumers intentionally excluded and why;
- new/split/deprecated tokens or components;
- representative compositions tested;
- regression enforcement added;
- remaining exceptions and expiry/removal plan.

## Prohibited patches

- Hardcoded font, color, spacing, radius, or size added to imitate a nearby component.
- A one-screen override when the same semantic role exists elsewhere.
- A global token change without reviewing all semantic consumers.
- Screenshot-reference updates without a reviewed design decision.
- Adding another button/banner/menu item before inventorying existing routes.
- “Looks fixed” based on one state, size, appearance, or host.
