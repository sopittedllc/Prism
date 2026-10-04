#!/usr/bin/env python3
"""Create a small, disposable Prism catalog fixture with no licensed audio."""
import argparse
import plistlib
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=PROJECT / "build/offline-demo")
args = parser.parse_args()
root = args.output.expanduser().resolve()
if root.exists():
    parser.error(f"output already exists: {root}; choose a fresh --output directory")


def write(relative: str, data: bytes) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


for extension in ("component", "vst3", "aaxplugin"):
    info = plistlib.dumps({
        "CFBundleIdentifier": f"org.example.prism.offline.{extension}",
        "CFBundleName": "Fixture Synth",
        "CFBundleVersion": "1.0",
    })
    write(f"Plugins/Fixture Synth.{extension}/Contents/Info.plist", info)

write("Samples/Percussion/Kick.wav", b"Synthetic catalog fixture; not playable audio.\n")
write("Samples/Orchestral/Swells.aif", b"Synthetic catalog fixture; not playable audio.\n")
write("Libraries/Example Folk/Example.nicnt", (
    "<ProductHints><Product><Name>Example Folk</Name>"
    "<Company>Example Maker</Company><SNPID>F01</SNPID>"
    "</Product></ProductHints>").encode())
write("Libraries/Example Folk/Instruments/Accordion.nki", b"Synthetic instrument name only.\n")
write("Libraries/Example Folk/Samples/C3.wav", b"Synthetic library payload marker.\n")
write("Projects/Fixture.rpp", (
    '<REAPER_PROJECT\n<TRACK\n<ITEM\n<SOURCE WAVE\n'
    'FILE "../Samples/Percussion/Kick.wav"\n>\n>\n>\n>\n').encode())
write("README.txt", (
    "Prism synthetic offline fixture. No files are playable audio or installed plugins.\n"
    "The project reference demonstrates saved inclusion, not Last used.\n").encode())

print(f"Created {root}")
print("Roots: Plugins, Samples, Libraries, Projects")
print("Use these four generated folders in Prism Setup, or scan with simplify-probe.")
