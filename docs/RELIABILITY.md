# Reliability Architecture

The system separates model judgment from mechanical proof.

```text
creative idea
    ↓
orchestrator → research → specification critique
    ↓
implementation → exact executable checks → independent review
    ↓                         failure
artifact-only product test ← diagnose → bounded repair
    ↓
schema-valid, content-bound evidence
    ↓
deterministic completion hook
```

UI/UX tasks add mandatory research, systemic design audit, accessibility, visual
regression, independent UX review, and runtime interaction gates. See `docs/ui-ux/`.

## Trust boundaries

- `AGENT_GUIDE.md`, client entry points, rules, skills, and role prompts improve behavior but are not security
  boundaries.
- The sandbox, permission system, external artifact-only tester, CI, deterministic
  scripts, and blocking hooks are enforcement boundaries.
- Compiler/test/validator output outranks model confidence.
- Evidence is bound to a product-content fingerprint. Any product edit makes prior
  gate evidence stale.
- Policy and hook changes are protected because a workflow must not weaken its own
  judge.
- Native Claude and Codex hooks invoke shared deterministic gates, but enforcement
  strength depends on the active client's sandbox and configuration. Disabled native
  enforcement must be reported rather than silently treated as equivalent.

## Failure policy

Failures automatically enter reproduce → diagnose → falsify → bounded repair → rerun.
The same stable failure signature receives at most the configured number of repair
attempts. An escalation is acceptable only when it requires creative intent, physical
access that has no harness, external authority, or a genuinely unavailable dependency.
It contains evidence and never asks the user to troubleshoot blindly.

## Limits

No agentic workflow proves that requirements capture every human preference or that
external platforms will never change. Reliability comes from reducing unverified
claims, isolating capabilities, testing observable behavior, and failing closed when
evidence is unavailable—not from claiming infallibility.
