#!/usr/bin/env python3
"""Create a source-free Claude or Codex workspace for blind product testing."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def copy_item(source: Path, destination: Path) -> None:
    if source.is_dir():
        shutil.copytree(source, destination)
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def hash_item(path: Path) -> str:
    digest = hashlib.sha256()
    if path.is_file():
        digest.update(path.read_bytes())
    else:
        for item in sorted(candidate for candidate in path.rglob("*") if candidate.is_file()):
            digest.update(str(item.relative_to(path)).encode())
            digest.update(item.read_bytes())
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--holdout", type=Path, required=True, help="User-owned criteria stored outside the source repository")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--client", choices=["claude", "codex"], default="claude")
    args = parser.parse_args()

    artifact = args.artifact.resolve()
    holdout = args.holdout.resolve()
    output = args.output.resolve()
    if not artifact.exists() or not holdout.is_file():
        parser.error("artifact and holdout criteria must exist")
    if ROOT in holdout.parents:
        parser.error("holdout criteria must live outside the development repository")
    if output.exists():
        parser.error("output must not already exist")

    copy_item(artifact, output / "artifact" / artifact.name)
    copy_item(holdout, output / ".qa-criteria" / "holdout-scenarios.md")
    instruction = (
        "# Artifact-only product test\n\n"
        "This workspace intentionally contains no source. Act only as the product tester. "
        "Test only `artifact/` against `.qa-criteria/holdout-scenarios.md`. Do not access "
        "the development repository or explain implementation causes.\n"
    )
    if args.client == "claude":
        (output / ".claude" / "agents").mkdir(parents=True)
        copy_item(ROOT / ".agents" / "roles" / "product-tester.md", output / ".claude" / "agents" / "product-tester.md")
        (output / "CLAUDE.md").write_text(instruction, encoding="utf-8")
        run_command = f"cd {output} && claude --agent product-tester"
    else:
        (output / ".agents" / "roles").mkdir(parents=True)
        copy_item(ROOT / ".agents" / "roles" / "product-tester.md", output / ".agents" / "roles" / "product-tester.md")
        (output / "AGENTS.md").write_text(instruction + "Read `.agents/roles/product-tester.md` before testing.\n", encoding="utf-8")
        run_command = f"cd {output} && codex"
    manifest = {
        "artifact": f"artifact/{artifact.name}",
        "artifact_sha256": hash_item(output / "artifact" / artifact.name),
        "holdout": ".qa-criteria/holdout-scenarios.md",
        "source_present": False,
        "client": args.client,
    }
    (output / "TEST_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(output)
    print(f"Run: {run_command}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
