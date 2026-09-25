#!/usr/bin/env python3
"""Block high-risk shell actions unless the user authorized them before launch."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path(__file__).resolve().parents[1]))

RULES = [
    ("history-rewrite", r"\bgit\s+(?:reset\s+--hard|rebase|filter-branch|filter-repo|push\b[^\n]*--force)"),
    ("git-push", r"\bgit\s+push\b"),
    ("release", r"\b(?:gh\s+release|fastlane\s+(?:release|deliver)|xcrun\s+(?:altool|notarytool).*--upload|transporter)\b"),
    ("upload", r"\b(?:xcrun\s+altool\s+--upload|iTMSTransporter|notarytool\s+submit)\b"),
    ("flash-hardware", r"\b(?:dfu-util|openocd|make\s+(?:program|program-dfu|flash)|west\s+flash|esptool(?:\.py)?)\b"),
    ("erase-hardware", r"\b(?:st-flash\s+erase|openocd\b[^\n]*mass_erase|esptool(?:\.py)?\s+erase_flash)\b"),
    ("install-system-software", r"\b(?:sudo\b|brew\s+(?:install|uninstall|upgrade)|apt(?:-get)?\s+(?:install|remove)|installer\s+-pkg)\b"),
    ("publish", r"\b(?:npm\s+publish|cargo\s+publish|twine\s+upload)\b"),
]


def decision(reason: str) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        decision("Safety hook could not parse tool input.")
        return 0
    command = str(payload.get("tool_input", {}).get("command", ""))
    authorization = os.environ.get("AGENT_USER_AUTHORIZED_ACTIONS", os.environ.get("CLAUDE_USER_AUTHORIZED_ACTIONS", ""))
    authorized = {item.strip() for item in authorization.split(",") if item.strip()}

    if re.search(r"\bgit\s+commit\b", command):
        gate = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "workflow_gate.py"), "check-commit"],
            cwd=ROOT, text=True, capture_output=True, check=False,
        )
        if gate.returncode != 0 and "git-commit-without-gates" not in authorized:
            decision("Commit blocked: automated tests and independent review need current evidence. " + gate.stderr.strip())
            return 0

    for action, pattern in RULES:
        if re.search(pattern, command, flags=re.IGNORECASE) and action not in authorized:
            decision(
                f"Blocked tier-3 action '{action}'. The user must start the client with "
                f"AGENT_USER_AUTHORIZED_ACTIONS including '{action}'."
            )
            return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
