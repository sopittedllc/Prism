#!/usr/bin/env python3
"""Package the already built native preview locally. Local ad-hoc signing only; no credentials, install, or upload."""
import argparse
import plistlib
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--configuration', choices=['debug', 'release'], default='release')
configuration = parser.parse_args().configuration
root = Path(__file__).resolve().parent.parent
app = root / 'build/Simplify.app/Contents'
(app / 'MacOS').mkdir(parents=True, exist_ok=True)
(app / 'Resources').mkdir(parents=True, exist_ok=True)
iconset = root / 'build/Simplify.iconset'
iconset.mkdir(parents=True, exist_ok=True)
subprocess.run(['swift', str(root / 'scripts/prepare_icon.swift'), str(root / 'Resources/AppIcon.jpg'), str(app / 'Resources')], check=True)
subprocess.run(['sips', '-z', '512', '512', str(app / 'Resources/AppMark.png'), '--out', str(app / 'Resources/AppMark.png')], check=True, capture_output=True)
for size in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        suffix = '@2x' if scale == 2 else ''
        subprocess.run(['sips', '-z', str(size * scale), str(size * scale),
                        str(app / 'Resources/IconMaster.png'), '--out',
                        str(iconset / f'icon_{size}x{size}{suffix}.png')], check=True, capture_output=True)
subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(app / 'Resources/Simplify.icns')], check=True)
# Replace the executable inode to avoid stale macOS code-signature cache entries.
executable = app / 'MacOS/Simplify'
shutil.copy2(root / f'.build/{configuration}/Simplify', executable.with_suffix('.new'))
executable.with_suffix('.new').replace(executable)
(app / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'llc.sopitted.Simplify.preview',
    'CFBundleExecutable': 'Simplify', 'CFBundleName': 'Simplify',
    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.1',
    'CFBundleVersion': '3', 'LSMinimumSystemVersion': '13.0',
    'CFBundleIconFile': 'Simplify.icns',
    'NSHighResolutionCapable': True,
}))
subprocess.run(['codesign', '--force', '--sign', '-', str(app.parent)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(app.parent)], check=True)
print('Packaged local preview: build/Simplify.app')
