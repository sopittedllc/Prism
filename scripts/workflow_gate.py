#!/usr/bin/env python3
"""Deterministic workflow-state validator with no third-party dependencies."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
POLICY_PATH = ROOT / ".workflow" / "policy.json"
ACTIVE_PATH = ROOT / ".workflow" / "active-task.json"
VALID_STATES = {"framing", "research", "planning", "implementation", "verification", "repair", "blocked", "complete"}
VALID_STATUSES = {"pending", "passed", "failed", "blocked", "not_applicable"}


class GateError(ValueError):
    pass


def load_json(path: Path) -> dict[str, Any]:
    try:
        display_path = path.relative_to(ROOT)
    except ValueError:
        display_path = path
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise GateError(f"missing file: {display_path}") from exc
    except json.JSONDecodeError as exc:
        raise GateError(f"invalid JSON in {display_path}: {exc}") from exc
    if not isinstance(value, dict):
        raise GateError(f"expected JSON object: {display_path}")
    return value


def current_revision() -> str:
    """Fingerprint version-controlled product content, independent of commit metadata."""
    digest = hashlib.sha256()
    listed = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT, capture_output=True, check=False,
    )
    if listed.returncode != 0:
        return "UNBORN"
    for raw_path in sorted(path for path in listed.stdout.split(b"\0") if path):
        if raw_path.startswith(b".workflow/evidence/") or raw_path == b".workflow/active-task.json":
            continue
        digest.update(raw_path)
        path = ROOT / raw_path.decode("utf-8", errors="surrogateescape")
        if path.is_file():
            digest.update(path.read_bytes())
        else:
            digest.update(b"<missing>")
    return f"content:{digest.hexdigest()}"


def validate_task(task: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    required = ["schema_version", "task_id", "title", "risk_tier", "state", "base_revision", "acceptance_criteria", "gates"]
    for key in required:
        if key not in task:
            errors.append(f"missing task field: {key}")
    if task.get("schema_version") != 1:
        errors.append("schema_version must be 1")
    if task.get("state") not in VALID_STATES:
        errors.append(f"invalid state: {task.get('state')}")
    tier = task.get("risk_tier")
    if not isinstance(tier, int) or isinstance(tier, bool) or tier not in range(4):
        errors.append("risk_tier must be an integer from 0 through 3")
    criteria = task.get("acceptance_criteria")
    if not isinstance(criteria, list) or not criteria:
        errors.append("acceptance_criteria must contain at least one criterion")
    else:
        seen: set[str] = set()
        for index, criterion in enumerate(criteria):
            if not isinstance(criterion, dict):
                errors.append(f"acceptance criterion {index} is not an object")
                continue
            criterion_id = criterion.get("id")
            if not criterion_id or criterion_id in seen:
                errors.append(f"acceptance criterion {index} has missing/duplicate id")
            seen.add(str(criterion_id))
            if criterion.get("status") not in VALID_STATUSES:
                errors.append(f"acceptance criterion {criterion_id} has invalid status")
    gates = task.get("gates")
    if not isinstance(gates, dict):
        errors.append("gates must be an object")
    else:
        for name, gate in gates.items():
            if not isinstance(gate, dict) or gate.get("status") not in VALID_STATUSES:
                errors.append(f"gate {name} has invalid or missing status")
    domains = task.get("domains", [])
    if not isinstance(domains, list) or not all(isinstance(item, str) for item in domains):
        errors.append("domains must be an array of strings")
    return errors


def completion_errors(task: dict[str, Any]) -> list[str]:
    errors = validate_task(task)
    if errors:
        return errors
    policy = load_json(POLICY_PATH)
    tier = str(task["risk_tier"])
    required_gates = policy.get("required_gates", {}).get(tier, [])
    for domain in task.get("domains", []):
        required_gates = list(dict.fromkeys(required_gates + policy.get("domain_gates", {}).get(domain, [])))
    gates = task["gates"]
    revision = current_revision()
    for name in required_gates:
        gate = gates.get(name, {})
        if gate.get("status") != "passed":
            errors.append(f"required gate not passed: {name}")
            continue
        if gate.get("revision") not in {revision, "UNBORN" if revision == "UNBORN" else None}:
            errors.append(f"gate {name} was not run against current revision {revision}")
        evidence_paths = gate.get("evidence", [])
        if not evidence_paths:
            errors.append(f"gate {name} has no evidence")
        for relative in evidence_paths:
            evidence_path = ROOT / relative
            try:
                evidence = load_json(evidence_path)
            except GateError as exc:
                errors.append(str(exc))
                continue
            if evidence.get("task_id") != task.get("task_id"):
                errors.append(f"evidence task mismatch: {relative}")
            if evidence.get("gate") != name or evidence.get("status") != "passed":
                errors.append(f"evidence does not pass gate {name}: {relative}")
            if evidence.get("revision") != gate.get("revision"):
                errors.append(f"evidence revision mismatch: {relative}")
    for criterion in task["acceptance_criteria"]:
        if criterion.get("status") != "passed":
            errors.append(f"acceptance criterion not passed: {criterion.get('id')}")
        if not criterion.get("evidence"):
            errors.append(f"acceptance criterion has no evidence: {criterion.get('id')}")
    if task.get("product_decisions_needed"):
        errors.append("unresolved product decisions remain")
    return errors


def commit_errors(task: dict[str, Any]) -> list[str]:
    errors = validate_task(task)
    if errors:
        return errors
    required = ["implementation", "automated_tests"]
    if task["risk_tier"] >= 1:
        required.append("code_review")
    for name in required:
        gate = task["gates"].get(name, {})
        if gate.get("status") != "passed" or not gate.get("evidence"):
            errors.append(f"commit requires passed gate with evidence: {name}")
    return errors


def print_errors(errors: list[str]) -> int:
    if not errors:
        print("workflow gate: PASS")
        return 0
    print("workflow gate: FAIL", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["validate", "check-complete", "check-complete-if-active", "check-if-marked-complete", "check-commit", "status"])
    parser.add_argument("path", nargs="?", type=Path, default=ACTIVE_PATH)
    args = parser.parse_args()

    if args.command == "check-complete-if-active" and not args.path.exists():
        return 0
    try:
        task = load_json(args.path)
        if args.command == "validate":
            return print_errors(validate_task(task))
        if args.command in {"check-complete", "check-complete-if-active"}:
            return print_errors(completion_errors(task))
        if args.command == "check-if-marked-complete":
            return print_errors(completion_errors(task)) if task.get("state") == "complete" else 0
        if args.command == "check-commit":
            return print_errors(commit_errors(task))
        print(json.dumps({
            "task_id": task.get("task_id"),
            "state": task.get("state"),
            "risk_tier": task.get("risk_tier"),
            "revision": current_revision(),
            "completion_errors": completion_errors(task),
        }, indent=2))
        return 0
    except GateError as exc:
        print(f"workflow gate: FAIL\n- {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
