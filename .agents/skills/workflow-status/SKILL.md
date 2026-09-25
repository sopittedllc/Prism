---
name: workflow-status
description: Show the active task, risk, gates, evidence, failures, repair attempts, and next autonomous action.
disable-model-invocation: true
---

Run `python3 scripts/workflow_gate.py status`. Summarize the result without changing
state. If no task is active, say so. Do not convert missing evidence into a pass.
