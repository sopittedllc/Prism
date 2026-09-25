#!/usr/bin/env python3
"""Inspect a bounded sample of an explicitly chosen project root; output aggregates only."""
import argparse
import collections
import json
import os
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('root', type=Path)
parser.add_argument('--per-format', type=int, default=5)
args = parser.parse_args()
if not args.root.is_dir() or args.root.is_symlink():
    parser.error('Choose an available non-symlink project directory')
if not 1 <= args.per_format <= 20:
    parser.error('per-format must be between 1 and 20')
binary = Path(__file__).resolve().parent.parent / '.build/debug/simplify-probe'
selected = collections.defaultdict(list)
counts = collections.Counter()
errors = []
entries = 0
extensions = {'.als', '.logicx', '.rpp', '.ptx', '.cpr', '.band', '.npr', '.song', '.flp', '.bwproject', '.reason', '.dpdoc'}
pending = [(args.root, 0)]
depth_truncated = False
while pending and entries < 100000:
    parent, depth = pending.pop()
    if depth > 64:
        depth_truncated = True
        continue
    try:
        with os.scandir(parent) as children:
            for child in children:
                if entries >= 100000:
                    break
                entries += 1
                if child.name.startswith('.') or child.is_symlink():
                    continue
                path = Path(child.path)
                ext = path.suffix.lower()
                if ext in extensions:
                    counts[ext] += 1
                    if len(selected[ext]) < args.per_format:
                        selected[ext].append(path)
                elif child.is_dir(follow_symlinks=False):
                    pending.append((path, depth + 1))
    except OSError as error:
        errors.append(type(error).__name__)
coverage = collections.Counter()
references = collections.Counter()
changed_inputs = 0
for ext, paths in selected.items():
    for path in paths:
        content = path / 'Alternatives/000/MetaData.plist' if ext == '.logicx' else path
        before = content.stat().st_mtime_ns if content.exists() else None
        try:
            result = subprocess.run([str(binary), '--inspect-project', str(path)], capture_output=True, text=True, timeout=30)
            report = json.loads(result.stdout)
            coverage[ext + ':' + report['coverage']] += 1
            references[ext] += len(report['references'])
        except (subprocess.TimeoutExpired, json.JSONDecodeError):
            coverage[ext + ':failed'] += 1
        after = content.stat().st_mtime_ns if content.exists() else None
        changed_inputs += before != after
summary = dict(entries_considered=entries, enumeration_truncated=entries >= 100000 or depth_truncated,
               formats_found=dict(counts), sampled_project_coverage=dict(coverage),
               reference_candidates=dict(references), enumeration_errors=errors,
               changed_project_modification_times=changed_inputs,
               limitations='Bounded convenience sample; no full-catalog or host-oracle validation. No project names, paths, or reference values retained.')
print(json.dumps(summary, indent=2, sort_keys=True))
raise SystemExit(1 if changed_inputs or errors else 0)
