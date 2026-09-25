# Simplify — Claude Code Instructions

Before doing any work, read and follow `AGENT_GUIDE.md`. It is the canonical operating
contract shared by Claude Code and Codex. Then read `.workflow/collaboration.json` to
learn the configured coordinator and cross-client review policy.

Claude-native agents, skills, rules, permissions, and hooks live under `.claude/`.
Use them as adapters to the shared contract; client-specific behavior must not weaken
the deterministic policy and evidence gates under `.workflow/` and `scripts/`.

When handing work to Codex, update the active plan and its resume notes first. Do not
edit the same worktree concurrently with another client.
