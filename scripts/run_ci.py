#!/usr/bin/env python3
"""Execute the exact checks designated for CI in the toolchain configuration."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    config = json.loads((ROOT / ".workflow" / "toolchain.json").read_text(encoding="utf-8"))
    names = config.get("ci_checks", [])
    if not names:
        print("CI configuration is incomplete: ci_checks is empty", file=sys.stderr)
        return 2
    checks = config.get("checks", {})
    if "state-coverage" in checks and "state-coverage" not in names:
        names = ["state-coverage", *names]
    for name in names:
        check = checks.get(name, {})
        argv = check.get("argv")
        if not isinstance(argv, list) or not argv:
            print(f"CI configuration is incomplete: {name} has no argv", file=sys.stderr)
            return 2
        print(f"::group::{name}")
        result = subprocess.run(argv, cwd=ROOT, timeout=int(check.get("timeout_seconds", 1200)), check=False)
        print("::endgroup::")
        if result.returncode != 0:
            return result.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
