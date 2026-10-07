#!/usr/bin/env python3
"""Read standard plugin roots and factory Ableton projects; print aggregates only."""
import collections
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / '.build/debug/simplify-probe'
command = [str(BIN), '--standard-plugins']
factory_override = os.environ.get('PRISM_ABLETON_FACTORY_DEMOS')
factory = Path(factory_override) if factory_override else Path(
    '/Applications/Ableton Live 12 Standard.app/Contents/App-Resources/Core Library/Lessons/Demo Songs')
if factory_override and not factory.is_dir():
    raise SystemExit('PRISM_ABLETON_FACTORY_DEMOS must point to an existing directory')
if factory.is_dir():
    command += ['--projects', str(factory)]
result = subprocess.run(command, capture_output=True, text=True, timeout=120)
assert result.returncode in (0, 2), result.stderr
report = json.loads(result.stdout)
standard_roots = set()
for base in [Path('/Library'), Path.home() / 'Library']:
    standard_roots.update(str(base / 'Audio/Plug-Ins' / name) for name in ['Components', 'VST', 'VST3', 'CLAP'])
    standard_roots.add(str(base / 'Application Support/Avid/Audio/Plug-Ins'))
unexpected = [issue for issue in report['issues'] if not (
    issue['path'] in standard_roots
    and issue['reason'].startswith('Root unavailable:')
    and not Path(issue['path']).exists()
    and not Path(issue['path']).is_symlink()
)]
assert not unexpected, f'Runtime validation incomplete: {len(unexpected)} unexpected scan issues (paths withheld)'
assert report['assets'], 'No real plugin candidates observed'
assert all(a['kind'] == 'plugin' for a in report['assets'])
unmeasured = sum(asset.get('logicalBytes') is None for asset in report['assets'])
assert unmeasured == 0, f'{unmeasured} installed plugin candidates lack a measured bundle size'
assert all(p['coverage'] == 'partial' for p in report['projects'])
if factory.is_dir():
    assert report['projects'] and any(p['references'] for p in report['projects'])
print(json.dumps({
    'status': 'passed',
    'plugin_candidates_by_format': dict(collections.Counter(a['format'] for a in report['assets'])),
    'factory_project_count': len(report['projects']),
    'factory_reference_candidates': sum(len(p['references']) for p in report['projects']),
    'expected_missing_standard_roots': len(report['issues']),
    'unmeasured_plugin_bundles': unmeasured,
    'seconds': round(report['durationSeconds'], 3),
    'limitations': 'Read-only installed-bundle and factory-project discovery only. No DAW-save roundtrip or full dependency coverage claimed.'
}, indent=2))
