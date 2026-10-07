#!/usr/bin/env python3
"""Ensure a beta package rebuild discards files left by an older app bundle."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "release-build"


def main() -> None:
    OUTPUT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="prism-package-rebuild-", dir=OUTPUT) as temporary:
        app = Path(temporary) / "Prism.app"
        command = [
            sys.executable, str(ROOT / "scripts/build_app.py"),
            "--output", str(app), "--scratch-path", "release-build/clean-scratch",
            "--version", "2026.10.07", "--build-number", "20261007.1",
            "--bundle-id", "llc.sopitted.Prism",
        ]
        subprocess.run(command, cwd=ROOT, check=True)
        stale = [
            app / "Contents/Resources/Simplify_SimplifyCore.bundle/obsolete.json",
            app / "Contents/Resources/obsolete.txt",
            app / "Contents/MacOS/obsolete",
        ]
        for path in stale:
            path.write_text("stale package content", encoding="utf-8")
        subprocess.run(command, cwd=ROOT, check=True)
        if any(path.exists() for path in stale):
            raise SystemExit("A beta package rebuild retained stale content")
        contents = app / "Contents"
        if {path.name for path in contents.iterdir()} != {"Info.plist", "MacOS", "Resources", "_CodeSignature"}:
            raise SystemExit("A beta package rebuild has unexpected bundle content")
        notice = (contents / "Resources/THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
        fastlz_license = (ROOT / "Sources/CFastLZ/LICENSE.MIT").read_text(encoding="utf-8").strip()
        if fastlz_license not in notice:
            raise SystemExit("The packaged notice omits the statically linked FastLZ license")
    print("Beta package rebuild: PASS")


if __name__ == "__main__":
    main()
