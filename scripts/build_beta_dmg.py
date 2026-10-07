#!/usr/bin/env python3
"""Create and inspect a local Prism beta DMG; signing/notarization stay separate."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RELEASE = json.loads((ROOT / "release/beta.json").read_text(encoding="utf-8"))


def run(*argv: str) -> str:
    return subprocess.check_output(argv, text=True).strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", default="release-build/Prism.app")
    args = parser.parse_args()
    app = (ROOT / args.app).resolve()
    if app.name != "Prism.app" or ROOT not in app.parents or not app.is_dir():
        parser.error("--app must name an existing Prism.app inside this repository")
    contents = app / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    expected = {
        "CFBundleIdentifier": RELEASE["bundle_identifier"],
        "CFBundleShortVersionString": RELEASE["marketing_version"],
        "LSMinimumSystemVersion": RELEASE["minimum_macos"],
        "CFBundleExecutable": "Prism",
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise SystemExit(f"Beta app has incorrect {key}: {info.get(key)!r}")
    if not str(info.get("CFBundleVersion", "")).replace(".", "").isdigit():
        raise SystemExit("Beta app has no numeric build number")
    binary = contents / "MacOS/Prism"
    if run("lipo", "-archs", str(binary)) != RELEASE["architecture"]:
        raise SystemExit("Beta app architecture does not match its release label")
    allowed = {"Info.plist", "MacOS", "Resources", "_CodeSignature"}
    if {item.name for item in contents.iterdir()} != allowed:
        raise SystemExit("Beta app contains unexpected top-level content")
    if {item.name for item in (contents / "MacOS").iterdir()} != {"Prism"}:
        raise SystemExit("Beta app contains unexpected executable content")
    resources = {item.name for item in (contents / "Resources").iterdir()}
    if resources != {"Prism.icns", "IconMaster.png", "AppMark.png", "THIRD_PARTY_NOTICES.md", "Simplify_SimplifyCore.bundle"}:
        raise SystemExit("Beta app contains unexpected resources")
    if (contents / "Resources/THIRD_PARTY_NOTICES.md").read_bytes() != (ROOT / "THIRD_PARTY_NOTICES.md").read_bytes():
        raise SystemExit("Beta app has stale or missing third-party notices")
    subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)

    out_dir = ROOT / "release-build"
    out_dir.mkdir(exist_ok=True)
    name = f"Prism-{RELEASE['marketing_version']}-{RELEASE['channel']}-macos-{RELEASE['architecture']}.dmg"
    dmg = out_dir / name
    tool = Path("/opt/homebrew/bin/create-dmg")
    if not tool.is_file():
        raise SystemExit("create-dmg is required; see TOOLCHAIN.md")
    with tempfile.TemporaryDirectory(prefix="prism-beta-staging-", dir=out_dir) as temporary:
        staging = Path(temporary)
        # Preserve the stapled app's resource forks and extended attributes.
        subprocess.run(["ditto", "--rsrc", "--extattr", str(app), str(staging / "Prism.app")], check=True)
        subprocess.run([
            str(tool), "--overwrite", "--skip-jenkins", "--volname", "Prism Beta",
            "--volicon", str(contents / "Resources/Prism.icns"),
            "--window-size", "660", "400", "--icon-size", "128",
            "--icon", "Prism.app", "180", "200", "--app-drop-link", "480", "200",
            str(dmg), str(staging),
        ], check=True)
    subprocess.run(["hdiutil", "verify", str(dmg)], check=True, stdout=subprocess.DEVNULL)
    with tempfile.TemporaryDirectory(prefix="prism-beta-mounted-", dir=out_dir) as temporary:
        mount = Path(temporary)
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-quiet", "-mountpoint", str(mount), str(dmg)], check=True)
        try:
            visible = {item.name for item in mount.iterdir() if not item.name.startswith(".")}
            if visible != {"Prism.app", "Applications"}:
                raise SystemExit(f"Unexpected DMG contents: {sorted(visible)}")
            if not (mount / "Applications").is_symlink() or (mount / "Applications").resolve() != Path("/Applications"):
                raise SystemExit("DMG Applications link has the wrong target")
            if not (mount / "Prism.app/Contents/Info.plist").is_file():
                raise SystemExit("DMG application or Applications link is unavailable")
            mounted_info = plistlib.loads((mount / "Prism.app/Contents/Info.plist").read_bytes())
            if mounted_info != info:
                raise SystemExit("Mounted app metadata differs from the source app")
            subprocess.run(["codesign", "--verify", "--strict", str(mount / "Prism.app")], check=True)
        finally:
            subprocess.run(["hdiutil", "detach", "-quiet", str(mount)], check=True)
    digest_state = hashlib.sha256()
    with dmg.open("rb") as image:
        for block in iter(lambda: image.read(1024 * 1024), b""):
            digest_state.update(block)
    digest = digest_state.hexdigest()
    print(f"Local DMG: {dmg.relative_to(ROOT)}")
    print(f"SHA-256 before notarization/stapling: {digest}")
    print("This script does not sign, notarize, staple, install, or publish.")


if __name__ == "__main__":
    main()
