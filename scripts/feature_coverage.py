#!/usr/bin/env python3
"""Validate cross-cutting state policy and compare runtime/preset ID exports."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_REGISTRY = ROOT / "docs" / "architecture" / "feature-registry.json"
POLICY = ROOT / ".workflow" / "cross-cutting-policy.json"


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read valid JSON from {path}: {exc}") from exc


def decision(value: Any) -> tuple[str | None, str]:
    if isinstance(value, str):
        return value, ""
    if isinstance(value, dict):
        return value.get("decision"), str(value.get("reason", "")).strip()
    return None, ""


def validate_registry(registry: dict[str, Any], policy: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for field in ("registry_version", "preset_schema_version", "unknown_field_policy", "settings"):
        if field not in registry:
            errors.append(f"missing registry field: {field}")
    if registry.get("unknown_field_policy") not in {"preserve", "reject", "ignore_with_warning"}:
        errors.append("invalid or missing unknown_field_policy")
    settings = registry.get("settings", [])
    if not isinstance(settings, list):
        return errors + ["settings must be an array"]
    required_concerns = policy.get("required_concerns", [])
    allowed = set(policy.get("allowed_decisions", []))
    seen: set[str] = set()
    for index, setting in enumerate(settings):
        if not isinstance(setting, dict):
            errors.append(f"setting {index} is not an object")
            continue
        setting_id = setting.get("id")
        if not isinstance(setting_id, str) or not setting_id:
            errors.append(f"setting {index} has no stable id")
            setting_id = f"#{index}"
        elif setting_id in seen:
            errors.append(f"duplicate setting id: {setting_id}")
        seen.add(setting_id)
        for field in ("value_type", "default", "introduced_in", "policies"):
            if field not in setting:
                errors.append(f"{setting_id}: missing {field}")
        policies = setting.get("policies", {})
        if not isinstance(policies, dict):
            errors.append(f"{setting_id}: policies must be an object")
            continue
        for concern in required_concerns:
            if concern not in policies:
                errors.append(f"{setting_id}: no explicit policy for {concern}")
                continue
            selected, reason = decision(policies[concern])
            if selected not in allowed:
                errors.append(f"{setting_id}: invalid {concern} decision {selected!r}")
            if selected in {"excluded", "not_applicable"} and not reason:
                errors.append(f"{setting_id}: {concern} {selected} requires a reason")
    return errors


def ids_from_export(path: Path) -> set[str]:
    value = load(path)
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return set(value)
    if isinstance(value, dict) and isinstance(value.get("ids"), list):
        return set(value["ids"])
    raise ValueError(f"{path} must be a string array or an object containing ids")


def compare_ids(registry: dict[str, Any], runtime_path: Path, preset_path: Path) -> list[str]:
    registry_ids = {setting["id"] for setting in registry.get("settings", []) if isinstance(setting, dict) and "id" in setting}
    preset_expected = {
        setting["id"] for setting in registry.get("settings", [])
        if isinstance(setting, dict) and decision(setting.get("policies", {}).get("preset"))[0] == "included"
    }
    runtime = ids_from_export(runtime_path)
    preset = ids_from_export(preset_path)
    errors = []
    for label, expected, actual in (
        ("runtime registry", registry_ids, runtime),
        ("preset serializer", preset_expected, preset),
    ):
        missing = sorted(expected - actual)
        unexpected = sorted(actual - expected)
        if missing:
            errors.append(f"{label} missing IDs: {', '.join(missing)}")
        if unexpected:
            errors.append(f"{label} unexpected IDs: {', '.join(unexpected)}")
    return errors


def report(errors: list[str]) -> int:
    if not errors:
        print("feature coverage: PASS")
        return 0
    print("feature coverage: FAIL", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["validate", "compare"])
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument("--runtime-ids", type=Path)
    parser.add_argument("--preset-ids", type=Path)
    args = parser.parse_args()
    try:
        registry = load(args.registry)
        policy = load(POLICY)
        errors = validate_registry(registry, policy)
        if args.command == "compare":
            if not args.runtime_ids or not args.preset_ids:
                parser.error("compare requires --runtime-ids and --preset-ids")
            errors.extend(compare_ids(registry, args.runtime_ids, args.preset_ids))
        return report(errors)
    except ValueError as exc:
        return report([str(exc)])


if __name__ == "__main__":
    raise SystemExit(main())
