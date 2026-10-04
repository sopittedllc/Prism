#!/usr/bin/env python3
"""Reproduce metadata discovery audit findings using synthetic, disposable files.

Run from any directory after the documented debug build. No real audio is read.
The repository-local fixture avoids macOS /tmp symlink rejection by the scanner.
"""
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone

REPO = pathlib.Path(__file__).resolve().parents[3]
EXE = REPO / ".build/debug/simplify-probe"
OUTPUT = pathlib.Path(__file__).with_suffix(".json")
CACHE = REPO / ".cache"
CACHE.mkdir(exist_ok=True)
fixture = pathlib.Path(tempfile.mkdtemp(prefix="audit-metadata-", dir=CACHE))


def write(relative, payload=b""):
    path = fixture / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def scan(name, relative):
    command = [str(EXE), "--libraries", str(fixture / relative)]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    # Retain the complete CLI output while omitting machine-specific fixture paths.
    stdout = result.stdout.replace(str(fixture), "<synthetic-fixture>")
    stderr = result.stderr.replace(str(fixture), "<synthetic-fixture>")
    report = json.loads(stdout)
    return {
        "case": name,
        "argv": [".build/debug/simplify-probe", "--libraries", "<synthetic-fixture>/" + relative],
        "exit_code": result.returncode,
        "stdout": report,
        "stderr": stderr,
    }


record = {
    "producer": "independent metadata/discovery reviewer",
    "client": "codex",
    "evidence_grade": "E2",
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
    "executable_sha256": hashlib.sha256(EXE.read_bytes()).hexdigest(),
    "source_sha256": {
        name: hashlib.sha256((REPO / name).read_bytes()).hexdigest()
        for name in ["Sources/SimplifyCore/LibraryDiscovery.swift", "Sources/SimplifyCore/LibraryMetadata.swift"]
    },
    "limitations": ["Synthetic fixtures only; no vendor installation compatibility certification.",
                    "These assertions reproduce current defects, not desired regression expectations."],
    "cases": [],
}
try:
    write("Mixed/Accordion.nki")
    write("Mixed/Banjo.dspreset")
    write("Mixed/Cello.dspreset")
    mixed = scan("mixed_player_folder_fragmentation", "Mixed")
    assets = mixed["stdout"]["assets"]
    groups = [(asset["name"], asset["format"], len(asset["libraryMetadata"]["instruments"])) for asset in assets]
    mixed["observed_groups"] = groups
    mixed["defect_reproduced"] = (
        mixed["exit_code"] == 0 and not mixed["stdout"]["issues"]
        and sorted(groups) == sorted([("Mixed", "Kontakt", 1), ("Mixed", "Decent Sampler", 1), ("Mixed", "Decent Sampler", 1)])
    )
    mixed["expected_behavior"] = "Two unresolved groups, one per player, with same-player siblings consolidated."
    record["cases"].append(mixed)

    write("Soundpaint/libraryInfo.lib")
    write("Soundpaint/Parts/Broken/info.json", b"{invalid")
    malformed = scan("malformed_soundpaint_metadata_silently_omitted", "Soundpaint")
    assets = malformed["stdout"]["assets"]
    malformed["defect_reproduced"] = (
        malformed["exit_code"] == 0 and not malformed["stdout"]["issues"]
        and len(assets) == 1 and assets[0]["libraryMetadata"]["instruments"] == []
    )
    malformed["expected_behavior"] = "Recognized invalid part metadata produces a scoped coverage issue."
    record["cases"].append(malformed)
finally:
    shutil.rmtree(fixture)
    record["synthetic_fixture_removed"] = not fixture.exists()

record["all_defects_reproduced"] = all(case["defect_reproduced"] for case in record["cases"])
OUTPUT.write_text(json.dumps(record, indent=2) + "\n")
print(json.dumps({"output": str(OUTPUT.relative_to(REPO)), "all_defects_reproduced": record["all_defects_reproduced"], "synthetic_fixture_removed": record["synthetic_fixture_removed"]}))
raise SystemExit(0 if record["all_defects_reproduced"] else 1)
