#!/usr/bin/env python3
"""Package the built Prism app locally, with ad-hoc or explicit Developer ID signing."""
import argparse
import plistlib
import re
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--configuration', choices=['debug', 'release'], default='release')
parser.add_argument('--output', default='build/Prism.app', help='Output bundle inside this repository')
parser.add_argument('--version', default='0.1', help='Numeric marketing version')
parser.add_argument('--build-number', default='3', help='Numeric build version')
parser.add_argument('--bundle-id', default='llc.sopitted.Simplify.preview')
parser.add_argument('--signing-identity', default='-', help='Developer ID Application identity, or - for local ad-hoc')
parser.add_argument('--scratch-path', default='.build', help='SwiftPM build directory inside this repository')
args = parser.parse_args()
configuration = args.configuration
root = Path(__file__).resolve().parent.parent
bundle = (root / args.output).resolve()
if bundle.name != 'Prism.app' or root not in bundle.parents:
    parser.error('--output must name a Prism.app bundle inside this repository')
preview_bundle = (root / 'build/Prism.app').resolve()
release_dir = (root / 'release-build').resolve()
if bundle != preview_bundle and release_dir not in bundle.parents:
    parser.error('--output must be the preview app or a bundle under release-build')
scratch = (root / args.scratch_path).resolve()
if root not in scratch.parents:
    parser.error('--scratch-path must name a directory inside this repository')
if scratch == bundle or bundle in scratch.parents:
    parser.error('--scratch-path cannot be inside the output bundle')
if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', args.version):
    parser.error('--version must contain one to three numeric components')
if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', args.build_number):
    parser.error('--build-number must contain one to three numeric components')
if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', args.bundle_id):
    parser.error('--bundle-id must be a reverse-DNS identifier')
if args.signing_identity != '-' and args.version.count('.') != 2:
    parser.error('Developer ID bundles require a three-component marketing version')
# Release outputs are disposable. Recreate them so a previous package cannot
# leave unlisted files inside an otherwise valid new signature.
if bundle != preview_bundle or args.signing_identity != '-':
    if bundle.exists():
        shutil.rmtree(bundle)
app = bundle / 'Contents'
(app / 'MacOS').mkdir(parents=True, exist_ok=True)
(app / 'Resources').mkdir(parents=True, exist_ok=True)
shutil.copy2(root / 'THIRD_PARTY_NOTICES.md', app / 'Resources/THIRD_PARTY_NOTICES.md')
iconset = root / 'build/Prism.iconset'
iconset.mkdir(parents=True, exist_ok=True)
subprocess.run(['swift', str(root / 'scripts/prepare_icon.swift'), str(root / 'Resources/PrismLogo.jpg'), str(app / 'Resources')], check=True)
subprocess.run(['sips', '-z', '512', '512', str(app / 'Resources/AppMark.png'), '--out', str(app / 'Resources/AppMark.png')], check=True, capture_output=True)
for size in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        suffix = '@2x' if scale == 2 else ''
        subprocess.run(['sips', '-z', str(size * scale), str(size * scale),
                        str(app / 'Resources/IconMaster.png'), '--out',
                        str(iconset / f'icon_{size}x{size}{suffix}.png')], check=True, capture_output=True)
subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(app / 'Resources/Prism.icns')], check=True)
# Replace the executable inode to avoid stale macOS code-signature cache entries.
executable = app / 'MacOS/Prism'
shutil.copy2(scratch / configuration / 'Simplify', executable.with_suffix('.new'))
executable.with_suffix('.new').replace(executable)
# Keep the SwiftPM resource bundle inside the signed app's Resources directory.
resource_bundle = app / 'Resources/Simplify_SimplifyCore.bundle'
if resource_bundle.exists():
    shutil.rmtree(resource_bundle)
shutil.copytree(scratch / configuration / 'Simplify_SimplifyCore.bundle', resource_bundle)
# Remove the bundle-root copy from earlier package attempts; app bundles may only
# contain the signed Contents directory at their root.
stale_resource_bundle = app.parent / 'Simplify_SimplifyCore.bundle'
if stale_resource_bundle.exists():
    shutil.rmtree(stale_resource_bundle)
metadata = {
    'CFBundleIdentifier': args.bundle_id,
    'CFBundleExecutable': 'Prism', 'CFBundleName': 'Prism', 'CFBundleDisplayName': 'Prism',
    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': args.version,
    'CFBundleVersion': args.build_number, 'LSMinimumSystemVersion': '13.0',
    'CFBundleIconFile': 'Prism.icns',
    'NSHighResolutionCapable': True,
}
(app / 'Info.plist').write_bytes(plistlib.dumps(metadata))
signing = ['codesign', '--force', '--sign', args.signing_identity]
if args.signing_identity != '-':
    signing += ['--options', 'runtime', '--timestamp']
subprocess.run(signing + [str(bundle)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(bundle)], check=True)
print(f'Packaged local app: {bundle.relative_to(root)}')
