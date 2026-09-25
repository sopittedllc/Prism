#!/usr/bin/env python3
"""Record a report-backed gate result and update the active task atomically."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import workflow_gate  # noqa: E402


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=path.name, dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def validate_ui_report(gate: str, report: Path) -> None:
    if gate not in {"ui_research", "design_system_audit"}:
        return
    try:
        value = json.loads(report.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"{gate} requires a structured JSON report: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{gate} report must be a JSON object")
    if gate == "ui_research":
        official = value.get("official_sources", [])
        cases = value.get("comparable_cases", [])
        if not isinstance(official, list) or len(official) < 1:
            raise ValueError("ui_research requires at least one authoritative source")
        if not isinstance(cases, list) or len(cases) < 3:
            raise ValueError("ui_research requires at least three comparable use cases")
        required_case_fields = {"name", "user_context", "task", "pattern", "success", "failure", "transferability"}
        for index, case in enumerate(cases):
            if not isinstance(case, dict) or not required_case_fields.issubset(case):
                raise ValueError(f"comparable case {index + 1} is incomplete")
        synthesis = value.get("synthesis", {})
        if not isinstance(synthesis, dict) or not {"requirements", "recurring_patterns", "project_inferences", "hypotheses"}.issubset(synthesis):
            raise ValueError("ui_research synthesis is incomplete")
        if not value.get("decision") or not value.get("validation"):
            raise ValueError("ui_research requires a decision and validation plan")
    else:
        required = {
            "symptom", "semantic_role", "authority", "searches", "included_consumers",
            "excluded_consumers", "system_changes", "representative_tests", "regression_prevention",
        }
        missing = sorted(field for field in required if field not in value)
        if missing:
            raise ValueError("systemic impact report missing: " + ", ".join(missing))
        for field in ("searches", "system_changes", "representative_tests", "regression_prevention"):
            if not isinstance(value[field], list) or not value[field]:
                raise ValueError(f"systemic impact report requires nonempty {field}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gate", required=True)
    parser.add_argument("--status", choices=["passed", "failed", "blocked", "not_applicable"], required=True)
    parser.add_argument("--producer", required=True)
    parser.add_argument("--client", choices=["claude-code", "codex", "human", "automation", "unknown"], default=os.environ.get("AGENT_CLIENT", "unknown"))
    parser.add_argument("--model", default=os.environ.get("AGENT_MODEL"))
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--task-file", type=Path, default=ROOT / ".workflow" / "active-task.json")
    args = parser.parse_args()

    report = args.report.resolve()
    if not report.is_file() or ROOT not in report.parents:
        parser.error("report must be an existing file inside the project")
    try:
        validate_ui_report(args.gate, report)
    except ValueError as exc:
        parser.error(str(exc))
    task = workflow_gate.load_json(args.task_file)
    errors = workflow_gate.validate_task(task)
    if errors:
        parser.error("; ".join(errors))
    if args.gate not in task["gates"]:
        parser.error(f"unknown gate: {args.gate}")

    revision = workflow_gate.current_revision()
    relative_report = str(report.relative_to(ROOT))
    report_hash = hashlib.sha256(report.read_bytes()).hexdigest()
    evidence_dir = ROOT / ".workflow" / "evidence" / task["task_id"]
    evidence_path = evidence_dir / f"{args.gate}.json"
    evidence = {
        "$schema": "../../schemas/evidence.schema.json",
        "schema_version": 1,
        "task_id": task["task_id"],
        "gate": args.gate,
        "status": args.status,
        "revision": revision,
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
        "producer": args.producer,
        "client": args.client,
        "checks": [{
            "name": f"{args.gate}-report",
            "status": args.status,
            "measurement": {"report": relative_report, "sha256": report_hash},
        }],
    }
    if args.model:
        evidence["model"] = args.model
    atomic_json(evidence_path, evidence)
    task["current_revision"] = revision
    task["gates"][args.gate] = {
        "status": args.status,
        "evidence": [str(evidence_path.relative_to(ROOT))],
        "revision": revision,
        "agent": args.producer,
    }
    atomic_json(args.task_file, task)
    print(evidence_path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
