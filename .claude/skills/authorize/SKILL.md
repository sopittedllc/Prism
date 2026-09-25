---
name: authorize
description: Explain how the user can authorize one explicit tier-3 action for a newly launched Claude Code session.
argument-hint: <action>
disable-model-invocation: true
---

Do not perform the action. Confirm `$ARGUMENTS` is listed in
`.workflow/policy.json`. Show the user how to restart the session with
`CLAUDE_USER_AUTHORIZED_ACTIONS=<action> claude`. Explain the exact effect and risk.
Authorization is narrow to the named action and does not waive verification gates.
