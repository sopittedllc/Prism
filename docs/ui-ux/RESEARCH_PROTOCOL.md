# UI/UX Research and Self-Update Protocol

When the project lacks a proven answer, research before design. The goal is not a mood
board; it is transferable evidence about a user problem.

## Minimum evidence

- At least one current authoritative platform/framework source.
- At least three materially comparable use cases from shipped products, official sample
  apps, established DAWs/plugins, or well-documented design systems.
- Local evidence: existing workflow, analytics/usability reports if available,
  components, incidents, support feedback, and constraints.

For each case record user/context, task, interaction, hierarchy, states, accessibility,
what succeeds, what fails, and whether its constraints match this project. Avoid copying
brand expression, fashionable surfaces, or behavior optimized for a different user.

## Synthesis

Separate:

- proven platform requirement;
- recurring cross-case pattern;
- project-specific inference;
- unresolved hypothesis requiring a prototype or usability test.

Convert the synthesis into a design decision with measurable acceptance evidence and
counterexamples. A single source or screenshot cannot establish a general rule.

## Thorough self-update

When runtime evidence validates a reusable conclusion, update all applicable artifacts:

1. semantic token/component inventory;
2. platform rule and design specification;
3. interaction/accessibility/visual regression tests;
4. examples or previews demonstrating canonical use;
5. `KNOWLEDGE_BASE.md` with evidence and limits;
6. deprecated exceptions and migration list;
7. incident report if the lesson came from an escaped regression.

Never promote preference or an untested hypothesis to a global standard. Mark it
`Proposed` until representative runtime evidence validates it.

The `ui_research` gate is rejected unless its JSON report contains at least one
authoritative source, three complete comparable cases, synthesis categories, a
decision, and a validation plan. The `design_system_audit` gate is rejected unless its
systemic-impact report inventories searches, consumers, system changes, representative
tests, and recurrence prevention.
