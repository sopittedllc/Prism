# Boilerplate Reliability Audit and v2 Resolution

**Audit date:** 2026-08-08
**Scope:** Generic Claude Code boilerplate, Daisy Seed, JUCE, and Apple App Store profiles

## Objective

The user should contribute creative ideas and product judgment, not diagnose build
failures, hallucinated APIs, regressions, or incomplete QA. Absolute infallibility is
not possible; the practical objective is to make unsupported claims difficult, detect
failures before handoff, repair routine failures autonomously, and fail closed when
proof is unavailable.

## Original findings

1. Most workflow gates were prose and could be skipped by the model.
2. Blind tests lived beside source and were protected only by instructions.
3. `Read` denials did not protect secrets from shell subprocesses.
4. The verification skill broadly preapproved Bash.
5. Markdown plans and reports were not machine-verifiable or revision-bound.
6. There was no deterministic completion gate or bounded repair loop.
7. Every implementation plan required user approval, making the user a process manager.
8. Reviewer and implementer errors could be correlated because they used similar model
   context; executable invariants and independent artifacts were missing.
9. Toolchain placeholders created false confidence or a bootstrap deadlock.
10. JUCE and Daisy lacked several target-specific regression, sanitizer, migration,
    performance, and recovery gates.
11. Initializer replacement and profile-switching behavior had edge cases.
12. App Store distribution was not covered.

## Resolutions implemented

- Risk tiers separate autonomous work from creative ambiguity and tier-3 authority.
- `.workflow/` contains policy, task state, schemas, exact argv commands, and evidence.
- Evidence is bound to a content fingerprint rather than a model assertion.
- Claude Code hooks block dangerous actions, unverified commits, and false completion.
- Sandboxing fails closed, denies sensitive paths at OS level, restricts network access,
  and disables unsandboxed retries.
- Blind product testing runs in a generated artifact-only workspace outside the repo.
- An orchestrator delegates research, specification critique, implementation, review,
  QA, diagnosis, repair, security, and release checks.
- Repeated failures use stable signatures and a bounded repair loop.
- CI exercises boilerplate integrity and project-defined exact commands.
- Dedicated Daisy, JUCE, and Apple App Store profiles define target evidence.
- Boilerplate self-tests cover all profiles, initialization, state validation, safety
  hooks, fail-closed completion, and evidence fingerprint stability.

## Remaining non-automatable boundaries

- Product taste and genuinely ambiguous creative direction.
- Physical-device or perceptual observations without a hardware/UI test harness.
- Credentials, purchases, publication, store submission, destructive history, and
  other externally consequential authority.
- Changes in host/store policies until authoritative documentation is rechecked.
- Unknown requirements that no specification, test, reviewer, or user has expressed.

## Next reliability frontier

The highest remaining user cost was UI/UX. The UI/UX protocol added after this audit
requires composition-first design, explicit state and responsive matrices, platform
accessibility, visual evidence, interaction testing, and separate Swift/App Store and
JUCE VST/AU standards. See `docs/ui-ux/`.

## Later scenario: preset drift

The user identified a six-month failure mode: presets initially serialize two settings,
later features introduce new settings, and nobody remembers to integrate them. This is
now prevented by `docs/architecture/STATE_COMPLETENESS.md`, the feature registry,
explicit cross-cutting policy, exact runtime/preset ID comparison, domain completion
gates, and migration/round-trip requirements. Omission fails deterministically rather
than relying on model memory.
