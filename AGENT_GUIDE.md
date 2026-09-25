# Simplify — Shared Agent Guide

## North star

Build the user's real workflow, not the fastest visible approximation. Read
`PROJECT.md` before significant work. A compiling artifact is evidence of syntax
and linkage; it is not evidence that the product works.

**Proven, systemic UI/UX is a project tentpole.** User-facing work follows
`docs/ui-ux/`. Treat visible defects as potential system defects: inventory every
semantic peer, repair the governing token/component/pattern, verify all consumers, and
update the design system and regression suite. When knowledge is missing, research
current authoritative guidance and at least three comparable use cases before deciding.

**Cross-cutting completeness is a project tentpole.** New settings and stateful
features follow `docs/architecture/STATE_COMPLETENESS.md`. Every state field has one
stable registry definition and an explicit policy for presets, persistence, defaults,
migration, undo, automation, sync, accessibility, privacy, analytics, and export.
Unspecified participation fails; parallel handwritten preset lists are prohibited.

## Source of truth

Read these in order, as relevant:

1. `PROJECT.md` — intent, users, constraints, definition of done.
2. `PROJECT_PROFILE.md` — domain constraints, if installed.
3. `TOOLCHAIN.md` — commands; do not invent commands when it is incomplete.
4. `.work/active/<feature>.md` — approved scope and acceptance criteria.
5. `KNOWLEDGE_BASE.md` and `docs/learnings/` — validated local knowledge.
6. Official documentation for external APIs and hardware.

If sources disagree, stop and surface the conflict. Product intent outranks an old
plan; verified tool output outranks prose that has become stale.

## Default workflow

Use the smallest workflow proportionate to the risk. Do not perform ceremony for a
typo, but do not skip a gate for behavior changes.

1. **Frame** — restate the user outcome and inspect adjacent code/configuration.
2. **Research** — for unfamiliar domains or third-party APIs, use authoritative
   sources and record consequential findings in the plan.
3. **Plan** — for non-trivial work, create `.work/active/<feature>.md` and
   `.workflow/active-task.json`. A specification critic must pass it. Tiers 0–1
   proceed autonomously; ask only about unresolved tier-2 product intent.
4. **Implement** — make the smallest coherent change that meets the approved
   acceptance criteria. Record discoveries without expanding scope.
5. **Verify** — run the commands in `TOOLCHAIN.md`; test failure paths and boundaries.
6. **Review** — use a fresh read-only review pass. Findings cite file and line.
7. **Runtime validate** — run on the real target for UI, audio, hardware, timing, or
   integration changes. Ask the user for checks only an available client cannot perform.
8. **Repair** — a failed gate goes through diagnosis, bounded repair, and downstream
   regression reruns without asking the user to troubleshoot.
9. **Close** — `scripts/workflow_gate.py check-complete` must pass. Update durable
   documents only when warranted. Tier-3 actions still require explicit authority.

## Authority and autonomy

The user supplies creative intent, product judgment, and authority for consequential
external actions. Agents own implementation mechanics and ordinary troubleshooting.
Use `.workflow/policy.json`:

- Tier 0: trivial, reversible changes; autonomous verification.
- Tier 1: reversible internal behavior; autonomous after research, critique, tests,
  and independent review.
- Tier 2: user-facing, architectural, compatibility, privacy, or real-target behavior;
  ask only if product intent is materially ambiguous, then verify all applicable gates.
- Tier 3: publishing, release, upload, credentials, spending, destructive history,
  system installation, or hardware flashing/erasure; explicit user authorization.

Do not ask the user to diagnose logs, select routine fixes, rerun commands, or notice
obvious regressions. Escalate after the bounded repair limit only with evidence and the
smallest decision or physical action that cannot be automated safely.

## Evidence contract

- Model statements never satisfy a gate.
- Every gate emits schema-valid JSON under `.workflow/evidence/<task-id>/`.
- Evidence identifies a SHA-256 fingerprint of all tracked and non-ignored product
  content, so committing identical content does not invalidate the evidence.
- A later edit invalidates earlier evidence until the affected gates rerun.
- `blocked` and `not_applicable` are never aliases for `passed`.
- Test and build commands come from `.workflow/toolchain.json` as exact argument arrays;
  never execute command text parsed from Markdown.

## Planning contract

A valid implementation plan includes:

- user outcome and explicit non-goals;
- current-state evidence;
- affected interfaces and files;
- risks and failure modes;
- ordered implementation steps;
- objective acceptance criteria;
- exact verification commands;
- runtime/manual checks;
- resume notes.

Do not make a plan merely to satisfy process. Keep small work small.

## Engineering standards

- Establish clear boundaries between product-facing code, domain logic, and
  platform/infrastructure code. Dependencies point inward toward stable contracts.
- Define or update a boundary before coupling distant layers.
- Keep real-time paths bounded: no allocation, locks, blocking I/O, logging, or
  unbounded work unless the platform explicitly guarantees safety.
- Make ownership and concurrency explicit. Shared mutable state needs one owner or a
  documented synchronization strategy.
- Handle errors at the layer that can add useful context or recover.
- Use named domain constants for meaningful values; do not disguise ordinary local
  values as needless abstractions.
- Public interfaces require concise documentation of behavior, units, ownership,
  threading, and failure modes where applicable.
- Tests should exercise observable behavior and critical boundaries, not mirror the
  implementation.
- Never guess a third-party API, ABI, callback guarantee, pin mapping, file format,
  or host behavior. Verify it in official documentation for the pinned version.

## Scope discipline

Do not refactor unrelated code, add speculative features, or silently repair nearby
bugs. Put discoveries under `Out-of-scope findings` in the active plan and ask the
user whether to schedule them.

## Completion language

Report evidence precisely:

- “Build passes” means only the documented build command passed.
- “Tests pass” names the test command and scope.
- “Runtime verified” names the target and behavior exercised.
- “Complete” means every acceptance criterion is met, including required real-target
  validation.

## Safety and repository hygiene

- Never commit credentials, signing material, personal/client content, proprietary
  samples, device identifiers, or machine-specific absolute paths.
- Use synthetic fixtures that preserve the shape of real data without identifying it.
- Do not stage all files blindly. Inspect `git status` and stage intended paths.
- Do not force-push, delete branches, rewrite history, flash hardware, install system
  dependencies, publish, or release without explicit permission.
- Preserve user changes. Do not overwrite or revert work you did not create.

## Role separation

Role definitions exposed through each client's native adapter are lenses, not a
substitute for judgment:

- `researcher` verifies unknowns and cannot implement.
- `implementer` follows an approved plan and cannot expand scope.
- `reviewer` reports evidence and cannot fix its own findings.
- `qa` selects and reports verification gates.
- `product-tester` evaluates only the running artifact against user-owned criteria.
- `ux-architect` researches and specifies complete systemic workflows.
- `ux-reviewer`, `accessibility-tester`, and `visual-regression-tester` independently
  verify composition, interaction, accessibility, and visual evidence.
- `completeness-reviewer` audits every cross-cutting integration for new state.

The development roles must not read `.qa-criteria/holdout-scenarios.md`. Blind tests
run from a separately prepared artifact-only directory; prompt instructions alone are
not isolation.

## Cross-client collaboration

Read `.workflow/collaboration.json` and `docs/CROSS_CLIENT_WORKFLOW.md`. The configured
primary client coordinates by default; both Claude Code and Codex remain supported.
Use the other client for specification critique and fresh read-only review when the
policy requires it. Never allow simultaneous writers in one worktree. A handoff updates
the active plan, resume notes, and affected-file list before the second client begins.

Record the acting client and role in plans, critiques, reviews, and manual evidence.
Cross-client agreement is still model judgment and never substitutes for an objective
gate.
