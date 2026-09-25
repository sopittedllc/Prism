#!/usr/bin/env python3
"""Exercise the built CLI against disposable synthetic inputs; never user projects."""
import gzip
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / '.build/debug/simplify-probe'


def run(*args):
    return subprocess.run([str(BIN), *map(str, args)], capture_output=True, text=True, timeout=30)


def snapshot(root):
    return {str(p.relative_to(root)): (hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mtime_ns)
            for p in root.rglob('*') if p.is_file()}


assert run().returncode == 0
assert 'Usage:' in run('--help').stdout
assert run('--samples').returncode == 64
assert run('--bad').returncode == 64
scratch = ROOT / '.work/scratch'
scratch.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='simplify-fixture-', dir=scratch) as directory:
    root = Path(directory).resolve()
    samples, projects = root / 'Samples', root / 'Projects'
    samples.mkdir()
    projects.mkdir()
    (samples / 'kick.wav').write_bytes(b'synthetic audio candidate')
    (projects / 'song.rpp').write_text('<REAPER_PROJECT\n<TRACK\n<ITEM\n<SOURCE WAVE\nFILE "../Samples/kick.wav"\n>\n>\n>\n>\n')
    xml = b'<Ableton><LiveSet><SampleRef><FileRef><Path Value="/unresolved/kick.wav"/></FileRef></SampleRef></LiveSet></Ableton>'
    (projects / 'song.als').write_bytes(gzip.compress(xml))
    before = snapshot(root)
    result = run('--samples', samples, '--projects', projects)
    assert result.returncode == 0, result.stderr
    report = json.loads(result.stdout)
    assert len(report['projects']) == 2
    assert report['sampleInclusions'][0]['status'] == 'referenced'
    assert snapshot(root) == before, 'Input content or modification time changed'
    result = run('--samples', root / 'missing')
    assert result.returncode == 2 and json.loads(result.stdout)['issues']
    # A tiny compressed input must not be allowed to expand without a bound.
    (projects / 'bomb.als').write_bytes(gzip.compress(b' ' * (65 * 1024 * 1024)))
    report = json.loads(run('--projects', projects).stdout)
    assert next(p for p in report['projects'] if p['path'].endswith('bomb.als'))['coverage'] == 'failed'
print('CLI smoke: PASS (arguments, gzip, bounded expansion, inclusion, input immutability, missing roots)')
