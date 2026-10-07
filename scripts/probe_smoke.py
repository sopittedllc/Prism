#!/usr/bin/env python3
"""Exercise the built CLI against disposable synthetic inputs; never user projects."""
import gzip
import hashlib
import json
import plistlib
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
    # CPR diagnostic is deliberately separate from ordinary project evidence.
    def token(value):
        raw = value.encode() + b'\0'
        return bytes([len(raw)]) + raw
    metadata = b'PAppVersion\0' + bytes(13) + token('Cubase') + bytes(3) + token('Version 15.0.30')
    descriptor = (b'Plugin UID\0' + bytes(22) + token('A' * 32) + bytes(3)
                  + token('Plugin Name') + bytes(5) + token('Example') + bytes(3) + token('Next'))
    cpr = root / 'diagnostic.cpr'
    cpr.write_bytes(b'RIF2' + metadata + descriptor)
    diagnostic_before = snapshot(root)
    result = run('--inspect-cubase-descriptors', cpr)
    assert result.returncode == 0, result.stderr
    diagnostic = json.loads(result.stdout)
    assert diagnostic['coverage'] == 'diagnostic-only'
    assert [r['name'] for r in diagnostic['descriptors']] == ['Example']
    assert diagnostic['inputSHA256'] == hashlib.sha256(cpr.read_bytes()).hexdigest()
    assert 'references' not in diagnostic
    # These diagnostic marker bytes are not a valid typed CPR container. The
    # saved-project reader must fail closed, never promote the descriptor to use.
    ordinary_result = run('--inspect-project', cpr)
    ordinary = json.loads(ordinary_result.stdout)
    assert ordinary_result.returncode == 2
    assert ordinary['coverage'] == 'failed' and ordinary['references'] == []
    assert not ordinary.get('pluginClasses') and not ordinary.get('sourceSHA256')
    assert snapshot(root) == diagnostic_before
    assert run('--inspect-cubase-descriptors').returncode == 64
    assert run('--inspect-cubase-descriptors', '--help').returncode == 64
    assert run('--inspect-cubase-descriptors', cpr, 'extra').returncode == 64
    bad_cpr = root / 'truncated.cpr'
    bad_cpr.write_bytes(cpr.read_bytes() + b'Plugin UID\0')
    failed = run('--inspect-cubase-descriptors', bad_cpr)
    assert failed.returncode == 2 and failed.stdout == ''
    assert run('--inspect-cubase-descriptors', root / 'missing.cpr').returncode == 2
    archive = root / 'export.xml'
    archive.write_text('<tracklist2><list name="track" type="obj">'
                       '<obj class="MInstrumentTrackEvent"><obj class="MListNode" name="Node">'
                       '<string name="Name" value="Renamed track"/></obj>'
                       '<obj class="MInstrumentTrack" name="Track Device"><member name="DeviceAttributes">'
                       '<member name="Synth Slot"><member name="Plugin">'
                       '<string name="Plugin Name" value="Renamed track"/>'
                       '<string name="Original Plugin Name" value="Example synth"/>'
                       '<member name="Plugin UID"><string name="GUID" value="' + 'A' * 32 + '"/>'
                       '</member></member></member></member></obj></obj></list></tracklist2>')
    archive_before = snapshot(root)
    result = run('--inspect-cubase-archive', archive)
    assert result.returncode == 0, result.stderr
    export = json.loads(result.stdout)
    assert export['coverage'] == 'partial-export'
    assert export['tracks'][0]['plugins'][0]['name'] == 'Example synth'
    assert 'projectModifiedAt' not in export and 'lastUsed' not in export
    assert snapshot(root) == archive_before
    assert json.loads(run('--inspect-project', archive).stdout)['coverage'] == 'unsupported'
    for args in [[], ['--help'], [archive, 'extra']]:
        assert run('--inspect-cubase-archive', *args).returncode == 64
    archive.write_text('<tracklist2>')
    bad = run('--inspect-cubase-archive', archive)
    assert bad.returncode == 2 and not bad.stdout
    pt = root / 'session.txt'
    pt.write_text('SESSION NAME:\tExample\nSAMPLE RATE:\t48000.000000\nBIT DEPTH:\t24-bit\n'
                  'SESSION START TIMECODE:\t04:00:00:00\nTIMECODE FORMAT:\t24 Frame\n'
                  '# OF AUDIO TRACKS:\t1\n# OF AUDIO CLIPS:\t0\n# OF AUDIO FILES:\t0\n\n'
                  'P L U G - I N S  L I S T I N G\n'
                  'MANUFACTURER\tPLUG-IN NAME\tVERSION\tFORMAT\tSTEMS\tNUMBER OF INSTANCES\n'
                  'Maker\tSynth\t1.0\tAAX Native\tStereo / Stereo\t1 active\n')
    pt_before = snapshot(root)
    result = run('--inspect-pro-tools-text', pt)
    assert result.returncode == 0, result.stderr
    report = json.loads(result.stdout)
    assert report['coverage'] == 'partial-export' and report['includedSections'] == ['plugins']
    assert report['plugins'][0]['name'] == 'Synth'
    assert report['inputSHA256'] == hashlib.sha256(pt.read_bytes()).hexdigest()
    assert 'lastUsed' not in report and 'projectModifiedAt' not in report
    ordinary = run('--inspect-project', pt)
    assert ordinary.returncode == 2 and not json.loads(ordinary.stdout)['references']
    assert snapshot(root) == pt_before
    for args in [[], ['--help'], [pt, 'extra']]:
        assert run('--inspect-pro-tools-text', *args).returncode == 64
    for path in [root / 'missing.txt', root]:
        failed = run('--inspect-pro-tools-text', path)
        assert failed.returncode == 2 and not failed.stdout
    pt.write_text(pt.read_text() + '\nT R A C K  L I S T I N G\n'
                  'TRACK NAME:\tAudio 1\nCOMMENTS:\t\nUSER DELAY:\t0 Samples\nSTATE: \n'
                  'PLUG-INS: \t\nCHANNEL\tEVENT\tCLIP NAME\tSTART TIME\tEND TIME\tDURATION\tSTATE\n'
                  '1\t1\tUnresolved clip\t04:00:00:00\t04:00:01:00\t00:00:01:00\tMuted\n')
    with_tracks = run('--inspect-pro-tools-text', pt)
    assert with_tracks.returncode == 0, with_tracks.stderr
    event = json.loads(with_tracks.stdout)['tracks'][0]['events'][0]
    assert event['state'] == 'Muted' and event['bindingStatus'] == 'clip-list-omitted'
    assert 'filePoolOrdinal' not in event
    pt.write_text('SESSION NAME:\tTruncated')
    failed = run('--inspect-pro-tools-text', pt)
    assert failed.returncode == 2 and not failed.stdout
    for args in [[], ['id'], ['id', '--bad'], ['id', root, 'extra']]:
        assert run('--inspect-plugin-receipt', *args).returncode == 64
    unavailable = run('--inspect-plugin-receipt', 'dev.prism.fixture.missing', root / 'Absent.component')
    assert unavailable.returncode == 2 and not unavailable.stdout
    receipt_bundle = root / 'Receipt.component'
    receipt_binary = receipt_bundle / 'Contents/MacOS/Fixture'
    receipt_binary.parent.mkdir(parents=True)
    receipt_binary.write_bytes(b'synthetic non-executable content')
    (receipt_bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'dev.prism.fixture', 'CFBundleExecutable': 'Fixture', 'CFBundleVersion': '1.0'}))
    unknown_receipt = run('--inspect-plugin-receipt', 'dev.prism.fixture.missing', receipt_bundle)
    assert unknown_receipt.returncode == 2 and not unknown_receipt.stdout
    assert 'nonzeroExit' in unknown_receipt.stderr, unknown_receipt.stderr
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
