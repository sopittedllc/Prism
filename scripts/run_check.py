#!/usr/bin/env python3
"""Run exact argv-based checks and emit revision-bound workflow evidence."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import workflow_gate  # noqa: E402


def atomic_json(path: Path, value: dict) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=path.name, dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--task", required=True)
    parser.add_argument("--gate", required=True)
    parser.add_argument("checks", nargs="+")
    args = parser.parse_args()

    config = workflow_gate.load_json(ROOT / ".workflow" / "toolchain.json")
    available = config.get("checks", {})
    revision = workflow_gate.current_revision()
    evidence_dir = ROOT / ".workflow" / "evidence" / args.task
    evidence_dir.mkdir(parents=True, exist_ok=True)
    log_dir = evidence_dir / "logs"
    log_dir.mkdir(exist_ok=True)
    results = []
    overall = "passed"

    for name in args.checks:
        check = available.get(name)
        argv = check.get("argv") if isinstance(check, dict) else None
        if not isinstance(argv, list) or not argv or not all(isinstance(item, str) for item in argv):
            results.append({"name": name, "status": "blocked", "log": "No exact argv configured"})
            overall = "blocked"
            continue
        timeout = int(check.get("timeout_seconds", 1200))
        log_path = log_dir / f"{name}.log"
        try:
            process = subprocess.run(argv, cwd=ROOT, text=True, capture_output=True, timeout=timeout, check=False)
            log_path.write_text(process.stdout + process.stderr, encoding="utf-8")
            status = "passed" if process.returncode == 0 else "failed"
            if status == "failed":
                overall = "failed"
            results.append({
                "name": name,
                "status": status,
                "command": json.dumps(argv),
                "exit_code": process.returncode,
                "log": str(log_path.relative_to(ROOT)),
            })
        except subprocess.TimeoutExpired as exc:
            log_path.write_text((exc.stdout or "") + (exc.stderr or ""), encoding="utf-8")
            results.append({"name": name, "status": "failed", "command": json.dumps(argv), "exit_code": 124, "log": str(log_path.relative_to(ROOT))})
            overall = "failed"

    evidence = {
        "$schema": "../../schemas/evidence.schema.json",
        "schema_version": 1,
        "task_id": args.task,
        "gate": args.gate,
        "status": overall,
        "revision": revision,
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
        "producer": "scripts/run_check.py",
        "client": os.environ.get("AGENT_CLIENT", "automation"),
        "checks": results,
    }
    evidence_path = evidence_dir / f"{args.gate}.json"
    atomic_json(evidence_path, evidence)
    active_path = ROOT / ".workflow" / "active-task.json"
    if active_path.exists():
        task = workflow_gate.load_json(active_path)
        if task.get("task_id") == args.task and args.gate in task.get("gates", {}):
            task["current_revision"] = revision
            task["gates"][args.gate] = {
                "status": overall,
                "evidence": [str(evidence_path.relative_to(ROOT))],
                "revision": revision,
                "agent": "scripts/run_check.py",
            }
            atomic_json(active_path, task)
    print(evidence_path.relative_to(ROOT))
    return 0 if overall == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
