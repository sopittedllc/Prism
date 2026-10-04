# Simplify — Shared Agent Guide

## North star

Build the user's real workflow, not the fastest visible approximation. Read
`PROJECT.md` before significant work. A compiling artifact is evidence of syntax
and linkage; it is not evidence that the product works.

**Proven, systemic UI/UX is a project tentpole.** User-facing work follows
`docs/ui-ux/`. For a bounded fix, inspect the affected semantic peers and verify
the shared behavior; update design guidance only when its contract changes. Use the
full UI research and visual matrix for new or materially changed interaction/design
systems. When that design knowledge is missing, research current authoritative
guidance and three comparable use cases before deciding.

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

Use one bounded path through the work. A trivial reversible edit (tier 0) needs a
brief task note, the relevant check, and a self-review. An understood internal
behavior change (tier 1) needs concise acceptance criteria, focused tests, and one
fresh read-only code review; do not commission separate research and specification
critique without a real unknown. A user-facing, architectural, compatibility, or
real-target change (tier 2) keeps its plan critique, independent review, and
applicable runtime gate. Tier 3 keeps explicit authority and release review.

Frame the outcome, inspect only adjacent code and relevant guidance, implement the
smallest complete change, then run focused tests during development. Run the required
configured gates once after source and prose are final. Focused repair checks cover
the failed and affected behavior first; the repository-wide evidence fingerprint may
still require final gate reruns after any subsequent edit. Diagnose repeated failures
or scope growth before adding
agents or expanding the plan. `scripts/workflow_gate.py check-complete` remains the
final completion check. Ask the user for real GUI checks when only they can perform
them; use existing smoke coverage and do not build a new GUI harness for one fix.

Use standard speed by default; change speed only when a specific task warrants it.
Aim to halve elapsed time and account usage on the next three comparable tasks.
Record only each task's start/end weekly usage-meter reading and elapsed time in its
handoff, noting that other account activity may affect the meter. This is a target,
not a promised saving or a new tracking system.

## Authority and autonomy

The user supplies creative intent, product judgment, and authority for consequential
external actions. Agents own implementation mechanics and ordinary troubleshooting.
Use `.workflow/policy.json`:

- Tier 0: trivial, reversible changes; autonomous verification.
- Tier 1: understood reversible internal behavior; autonomous after focused tests
  and one independent read-only review.
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

For tier 0, a task note can be one sentence. For tier 1, use a short plan only when
needed to hold acceptance criteria or resume state. The full plan contract applies
to tier 2–3 and genuinely unfamiliar work. Do not make a plan merely to satisfy
process.

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

Read `.workflow/collaboration.json` and `docs/CROSS_CLIENT_WORKFLOW.md`. One Sol
driver handles routine coding by default. Use Luna for simple bounded tasks and
Astra for brief architecture decisions or escalation; do not keep Astra in the
routine tool and gate loop. Keep one writer per worktree. Delegate only when the
task benefits from it or a required independent gate needs it. Give a delegate a
short task-specific handoff: outcome, relevant paths, constraints, current evidence,
and next action. Do not forward full conversation history by default. Use a single
concise return handoff. Both Claude Code and Codex remain supported.

Record the acting client and role in plans, critiques, reviews, and manual evidence.
Cross-client agreement is still model judgment and never substitutes for an objective
gate.
