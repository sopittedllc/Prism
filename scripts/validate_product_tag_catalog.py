#!/usr/bin/env python3
"""Validate offline product-tag identities and reviewed function vocabulary."""
import argparse
import json
import re
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / 'Sources/SimplifyCore/Resources/product-tag-catalog-v2.json'
UNAMBIGUOUS = {
    'equalizer': 'eq', 'synthesis': 'synthesizer',
    'pitch shifting': 'pitch shift/harmonizer', 'vocal': 'vocal processing',
}
REVIEW_REQUIRED = {'saturation', 'distortion', 'mixing'}


def identity(value):
    return ''.join(re.findall(r'[a-z0-9]+', value.casefold()))


def validate(records):
    problems = []
    owners = {}
    for record in records:
        for maker in record['makers']:
            for name in record['names']:
                key = record['kind'], identity(maker), identity(name)
                previous = owners.setdefault(key, record['id'])
                if previous != record['id']:
                    problems.append(f"duplicate identity {previous} / {record['id']}")
        for tag in record['metadata'].get('function', []):
            if tag in UNAMBIGUOUS or tag in REVIEW_REQUIRED:
                problems.append(f"noncanonical function {record['id']}: {tag}")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--normalize', action='store_true', help='rewrite only unambiguous function synonyms')
    args = parser.parse_args()
    catalog = json.loads(CATALOG.read_text())
    if args.normalize:
        for record in catalog['records']:
            values = record['metadata'].get('function')
            if values:
                record['metadata']['function'] = list(dict.fromkeys(UNAMBIGUOUS.get(value, value) for value in values))
        CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    problems = validate(catalog['records'])
    if problems:
        print('\n'.join(problems[:20]))
        raise SystemExit(f'catalog tags: {len(problems)} issue(s)')
    print(f"Catalog tags: PASS ({len(catalog['records'])} records; kind/maker identities and function vocabulary)")


if __name__ == '__main__':
    main()
