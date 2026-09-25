---
name: ui-audit
description: Run a systemic UI/UX audit across composition, consistency, states, accessibility, responsiveness, and runtime evidence.
argument-hint: <scope or workflow>
disable-model-invocation: true
---

Inventory `$ARGUMENTS` by semantic role across the complete codebase and design system.
Dispatch ux-reviewer, accessibility-tester, and visual-regression-tester as applicable.
Use the installed platform rule and `docs/ui-ux/REVIEW_PROTOCOL.md`. Return findings by
severity, system-level root mechanism, every affected consumer, proposed governing fix,
required evidence, and regression prevention. Do not fix issues during the audit.
