#!/usr/bin/env python3
"""Synchronize Claude adapter content from the client-neutral .agents source."""

from __future__ import annotations

import argparse
import filecmp
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAPPINGS = (
    (ROOT / ".agents" / "skills", ROOT / ".claude" / "skills"),
    (ROOT / ".agents" / "roles", ROOT / ".claude" / "agents"),
    (ROOT / ".agents" / "rules", ROOT / ".claude" / "rules"),
)


def directories_equal(source: Path, target: Path) -> bool:
    if not source.is_dir() or not target.is_dir():
        return False
    comparison = filecmp.dircmp(source, target)
    if comparison.left_only or comparison.right_only or comparison.diff_files or comparison.funny_files:
        return False
    return all(directories_equal(source / name, target / name) for name in comparison.common_dirs)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail when adapters have drifted")
    args = parser.parse_args()
    drifted = [(source, target) for source, target in MAPPINGS if not directories_equal(source, target)]
    if args.check:
        for source, target in drifted:
            print(f"adapter drift: {target.relative_to(ROOT)} != {source.relative_to(ROOT)}")
        return 1 if drifted else 0
    for source, target in drifted:
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(source, target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
