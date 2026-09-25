# Claude + Codex Collaboration

This project installs first-class adapters for both Claude Code and Codex. The
configured primary client coordinates work; it does not own the project or exclude the
other client. `.workflow/collaboration.json` is the machine-readable source of truth.

## Default sequence

```text
primary client frames and plans
          ↓
other client critiques the specification
          ↓
primary client implements
          ↓
other client performs a fresh read-only review
          ↓
shared deterministic gates verify the result
```

For `balanced`, choose either client as the driver for each task and record that choice
in the active plan. The other client should critique or review whenever it is
available. Cross-client review improves independence but never replaces tests,
runtime validation, or deterministic gates.

## Single-writer rule

Never let Claude and Codex edit the same worktree concurrently. A handoff must leave
the worktree coherent, update the active plan's resume notes, and identify uncommitted
files. Parallel read-only research or review is allowed. Use separate Git worktrees if
two clients must implement independent alternatives.

## Provenance

Plans, critiques, reviews, and manually recorded evidence identify the acting role and
client (`claude-code`, `codex`, `human`, or `automation`). Record a model identifier
when the client exposes one reliably. Client opinion never satisfies an objective gate.

## Native enforcement boundary

Claude and Codex have different sandbox, permission, and hook systems. Native adapters
invoke the same shared scripts, but their guarantees are not assumed equivalent. If a
hook or sandbox is disabled, say so explicitly and run the underlying deterministic
gate directly. See `docs/SECURITY.md` and `docs/RELIABILITY.md`.
