---
name: verify
description: Run the documented verification appropriate to the active change
disable-model-invocation: true
---

Read `TOOLCHAIN.md`, the active plan, installed profile, and current diff. Run the
smallest complete applicable verification set. Report commands, exit status, failures,
skips, and required real-target checks. Never turn an undocumented guessed command
into project policy; propose a `TOOLCHAIN.md` update instead.
