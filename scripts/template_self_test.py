#!/usr/bin/env python3
"""Regression tests for the boilerplate itself."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROFILES = ("generic", "daisy-seed", "juce", "apple-app-store")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def run(*argv: str, cwd: Path = ROOT, expected: int = 0) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment.setdefault("PYTHONPYCACHEPREFIX", str(ROOT / ".cache" / "pycache"))
    result = subprocess.run(argv, cwd=cwd, env=environment, text=True, capture_output=True, check=False)
    require(result.returncode == expected, f"{argv} returned {result.returncode}\n{result.stdout}\n{result.stderr}")
    return result


def validate_json_files(root: Path) -> None:
    if (root / ".git").exists():
        listed = subprocess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.json"],
            cwd=root, capture_output=True, check=True,
        )
        paths = (root / os.fsdecode(raw) for raw in listed.stdout.split(b"\0") if raw)
    else:
        paths = root.rglob("*.json")
    for path in paths:
        if not path.is_file():
            continue
        json.loads(path.read_text(encoding="utf-8"))


def validate_structure(root: Path) -> None:
    required = [
        "AGENT_GUIDE.md", "AGENTS.md", "CLAUDE.md", "PROJECT.md",
        ".claude/settings.json", ".codex/hooks.json", ".workflow/policy.json",
        ".workflow/collaboration.json",
        ".workflow/toolchain.json", ".workflow/cross-cutting-policy.json",
        "scripts/workflow_gate.py", "scripts/run_check.py", "scripts/record_gate.py",
        "scripts/feature_coverage.py",
        ".claude/agents/orchestrator.md", ".claude/agents/specification-critic.md",
        ".agents/roles/orchestrator.md", ".agents/roles/specification-critic.md",
        ".agents/skills/idea/SKILL.md", "scripts/sync_agent_adapters.py",
    ]
    for relative in required:
        require((root / relative).exists(), f"missing {relative}")
    settings = json.loads((root / ".claude/settings.json").read_text())
    require(settings.get("sandbox", {}).get("enabled") is True, "sandbox must be enabled")
    require(settings.get("sandbox", {}).get("failIfUnavailable") is True, "sandbox must fail closed")
    require("Bash" not in (root / ".claude/skills/verify/SKILL.md").read_text().split("---", 2)[1], "verify skill must not preapprove Bash")
    collaboration = json.loads((root / ".workflow/collaboration.json").read_text())
    require(collaboration["allow_simultaneous_writers"] is False, "simultaneous writers must be disabled")
    run(sys.executable, "scripts/sync_agent_adapters.py", "--check", cwd=root)


def exercise_initializers() -> None:
    if "{{PROJECT_NAME}}" not in (ROOT / "AGENT_GUIDE.md").read_text(encoding="utf-8"):
        return
    clients = ("balanced", "claude", "codex")
    for index, profile in enumerate(PROFILES):
        primary = clients[index % len(clients)]
        with tempfile.TemporaryDirectory(prefix="agent-template-test-") as temp:
            copy = Path(temp) / "project"
            shutil.copytree(ROOT, copy)
            result = run(
                str(copy / "scripts/init-project.sh"), "Test \\ & | Project", profile, "Owner & Co", "--primary", primary,
                cwd=copy,
            )
            require("Initialized" in result.stdout, f"initializer did not report success for {profile}")
            for instructions in ("AGENT_GUIDE.md", "AGENTS.md", "CLAUDE.md", "PROJECT.md"):
                require("{{" not in (copy / instructions).read_text(), f"tokens remain in {instructions} for {profile}")
            collaboration = json.loads((copy / ".workflow/collaboration.json").read_text())
            require(collaboration["primary_client"] == primary, f"wrong primary client for {profile}")
            require(profile.split("-")[0].lower() in (copy / "PROJECT_PROFILE.md").read_text().lower() or profile == "generic", f"wrong profile installed: {profile}")
            if profile in {"juce", "apple-app-store"}:
                require(any((copy / ".agents/rules/profile").glob("*.md")), f"shared UI profile rule not installed: {profile}")
                require(any((copy / ".claude/rules/profile").glob("*.md")), f"Claude UI profile adapter not installed: {profile}")
            require((copy / "STATE_REGISTRY_PROFILE.md").is_file(), f"state registry reference not installed: {profile}")
            run(str(copy / "scripts/init-project.sh"), "Again", profile, cwd=copy, expected=2)


def exercise_gate() -> None:
    run(sys.executable, "scripts/workflow_gate.py", "validate", ".workflow/task.template.json")
    run(sys.executable, "scripts/workflow_gate.py", "check-complete", ".workflow/task.template.json", expected=1)
    task_path = ROOT / ".workflow" / "task.template.json"
    task = json.loads(task_path.read_text())
    task["domains"] = ["ui-ux"]
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
        json.dump(task, handle)
        ui_task_path = Path(handle.name)
    try:
        result = run(sys.executable, "scripts/workflow_gate.py", "check-complete", str(ui_task_path), expected=1)
        require("design_system_audit" in result.stderr and "visual_regression" in result.stderr, "UI domain gates were not enforced")
    finally:
        ui_task_path.unlink()
    task["domains"] = ["stateful-feature"]
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
        json.dump(task, handle)
        state_task_path = Path(handle.name)
    try:
        result = run(sys.executable, "scripts/workflow_gate.py", "check-complete", str(state_task_path), expected=1)
        require("preset_roundtrip" in result.stderr and "state_migration" in result.stderr, "stateful domain gates were not enforced")
    finally:
        state_task_path.unlink()


def exercise_revision_bound_evidence() -> None:
    with tempfile.TemporaryDirectory(prefix="claude-evidence-test-") as temp:
        copy = Path(temp) / "project"
        # Revision tests need product sources and .git, not generated binaries or
        # native captures. Copying those can exhaust a developer's temp volume.
        shutil.copytree(ROOT, copy, ignore=shutil.ignore_patterns(".build", "build", "captures", ".cache"))
        toolchain_path = copy / ".workflow" / "toolchain.json"
        toolchain = json.loads(toolchain_path.read_text())
        toolchain["checks"]["unit-tests"]["argv"] = [sys.executable, "-c", "raise SystemExit(0)"]
        toolchain_path.write_text(json.dumps(toolchain, indent=2) + "\n")
        task = json.loads((copy / ".workflow" / "task.template.json").read_text())
        task["task_id"] = "evidence-test"
        task["title"] = "Evidence stability test"
        (copy / ".workflow" / "active-task.json").write_text(json.dumps(task, indent=2) + "\n")
        run(sys.executable, "scripts/run_check.py", "--task", "evidence-test", "--gate", "automated_tests", "unit-tests", cwd=copy)
        status = json.loads(run(sys.executable, "scripts/workflow_gate.py", "status", cwd=copy).stdout)
        updated = json.loads((copy / ".workflow" / "active-task.json").read_text())
        require(updated["gates"]["automated_tests"]["revision"] == status["revision"], "writing evidence changed the tested revision")


def exercise_ui_report_enforcement() -> None:
    sys.path.insert(0, str(ROOT / "scripts"))
    import record_gate
    with tempfile.TemporaryDirectory(prefix="claude-ui-report-") as temp:
        report = Path(temp) / "research.json"
        report.write_text(json.dumps({"official_sources": [{}], "comparable_cases": []}))
        try:
            record_gate.validate_ui_report("ui_research", report)
        except ValueError as exc:
            require("three comparable" in str(exc), "wrong UI research failure")
        else:
            raise AssertionError("incomplete UI research was accepted")
        complete_case = {
            "name": "case", "user_context": "context", "task": "task", "pattern": "pattern",
            "success": "success", "failure": "failure", "transferability": "transferability",
        }
        report.write_text(json.dumps({
            "official_sources": [{"title": "official", "url": "https://example.invalid", "finding": "finding"}],
            "comparable_cases": [complete_case, complete_case, complete_case],
            "synthesis": {"requirements": [], "recurring_patterns": [], "project_inferences": [], "hypotheses": []},
            "decision": "decision", "validation": ["test"],
        }))
        record_gate.validate_ui_report("ui_research", report)


def exercise_feature_coverage() -> None:
    run(sys.executable, "scripts/feature_coverage.py", "validate")
    policy = json.loads((ROOT / ".workflow" / "cross-cutting-policy.json").read_text())
    policies = {name: {"decision": "excluded", "reason": "test"} for name in policy["required_concerns"]}
    policies["preset"] = {"decision": "included"}
    registry = {
        "registry_version": 1,
        "preset_schema_version": 1,
        "unknown_field_policy": "preserve",
        "settings": [{"id": "tone.amount", "value_type": "number", "default": 0.5, "introduced_in": 1, "policies": policies}],
    }
    with tempfile.TemporaryDirectory(prefix="claude-feature-coverage-") as temp:
        temp_path = Path(temp)
        registry_path = temp_path / "registry.json"
        runtime_path = temp_path / "runtime.json"
        preset_path = temp_path / "preset.json"
        registry_path.write_text(json.dumps(registry))
        runtime_path.write_text(json.dumps(["tone.amount"]))
        preset_path.write_text(json.dumps(["tone.amount"]))
        run(sys.executable, "scripts/feature_coverage.py", "compare", "--registry", str(registry_path), "--runtime-ids", str(runtime_path), "--preset-ids", str(preset_path))
        preset_path.write_text(json.dumps([]))
        result = run(sys.executable, "scripts/feature_coverage.py", "compare", "--registry", str(registry_path), "--runtime-ids", str(runtime_path), "--preset-ids", str(preset_path), expected=1)
        require("preset serializer missing IDs: tone.amount" in result.stderr, "missing preset integration was not detected")


def main() -> int:
    validate_json_files(ROOT)
    validate_structure(ROOT)
    run("sh", "-n", "scripts/init-project.sh")
    run("sh", "-n", ".claude/hooks/completion_gate.sh")
    run("sh", "-n", "scripts/client_completion_gate.sh")
    for script in ("scripts/workflow_gate.py", "scripts/run_check.py", "scripts/record_gate.py", "scripts/feature_coverage.py", "scripts/run_ci.py", "scripts/prepare_product_test.py", "scripts/sync_agent_adapters.py", "scripts/pretool_guard.py", ".claude/hooks/pretool_guard.py"):
        run(sys.executable, "-m", "py_compile", script)
    exercise_gate()
    exercise_revision_bound_evidence()
    exercise_ui_report_enforcement()
    exercise_feature_coverage()
    exercise_initializers()
    print("template self-test: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
