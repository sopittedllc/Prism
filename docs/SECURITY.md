# Security Model

Autonomous work should run with the active client's strongest checked-in sandbox and
approval configuration. Claude Code is configured here to fail closed. Codex users
must retain its sandbox and approval controls; repository hooks supplement those
controls but do not create an operating-system boundary by themselves.

For Claude Code, tier-3 actions are blocked by `.claude/hooks/pretool_guard.py`. The
user authorizes a narrow action before launching a new session:

```bash
AGENT_USER_AUTHORIZED_ACTIONS=git-push claude
```

Multiple actions are comma-separated. Authorization permits the capability; it does
not waive tests, review, release validation, or the completion gate.

Codex applies its own sandbox and approval system and invokes the same command-policy
guard through `.codex/hooks.json`. Do not infer tier-3 authority if hooks are disabled:
obtain explicit user approval. Both clients invoke the shared completion gate when
their hook system is enabled.

Do not expose personal home directories, signing keys, SSH agents, cloud credentials,
or production tokens to routine development sessions. Prefer a dedicated container or
VM and a separate release runner whose credentials are scoped to the intended action.
Review sandbox domain additions as data-exfiltration boundaries.
