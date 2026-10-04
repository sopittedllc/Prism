# Claude + Codex Collaboration

This project installs first-class adapters for both Claude Code and Codex. The
configured primary client coordinates work; it does not own the project or exclude the
other client. `.workflow/collaboration.json` is the machine-readable source of truth.

## Default sequence

```text
one driver frames and implements
          ↓
focused tests during development
          ↓
one independent read-only review when required
          ↓
final applicable gates and real-target check
```

For `balanced`, use a Sol driver for routine coding, Luna for simple bounded work,
and Astra for brief architecture decisions or escalation. The configured driver may
complete tier-0 work directly. Tier-1 behavior still gets one fresh read-only code
review; tier-2/3 work keeps its plan critique and applicable runtime checks. A
reviewer can be independent without switching clients. Request cross-client review
when the change or uncertainty benefits from it. Cross-client opinion never replaces
tests, runtime validation, or deterministic gates.

## Single-writer rule

Never let Claude and Codex edit the same worktree concurrently. For a transfer, send
one short task-specific handoff with the outcome, affected files, constraints,
verified evidence, and next action; identify uncommitted work. Do not copy the full
conversation into a new agent by default. Parallel read-only review is allowed.
Use separate Git worktrees for truly independent implementation alternatives.

## Provenance

Plans, critiques, reviews, and manually recorded evidence identify the acting role and
client (`claude-code`, `codex`, `human`, or `automation`). Record a model identifier
when the client exposes one reliably. Client opinion never satisfies an objective gate.

## Native enforcement boundary

Claude and Codex have different sandbox, permission, and hook systems. Native adapters
invoke the same shared scripts, but their guarantees are not assumed equivalent. If a
hook or sandbox is disabled, say so explicitly and run the underlying deterministic
gate directly. See `docs/SECURITY.md` and `docs/RELIABILITY.md`.
