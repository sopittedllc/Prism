# Simplify — Codex Instructions

Before doing any work, read and follow `AGENT_GUIDE.md`. It is the canonical operating
contract shared by Codex and Claude Code. Then read `.workflow/collaboration.json` to
learn the configured coordinator and cross-client review policy.

Codex-native workflows are available in `.agents/skills/`. Shared role definitions
live in `.agents/roles/`; use them as independent lenses and preserve the role
separation required by `AGENT_GUIDE.md`.

Repository hooks are additional enforcement, not a replacement for the deterministic
commands under `scripts/`. If a native hook is unavailable, run the corresponding
workflow gate directly and report that native enforcement was unavailable.
