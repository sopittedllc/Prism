#!/usr/bin/env python3
"""Verify the native session registry, defaults, and explicit serialization exclusions."""
import json
import subprocess
from pathlib import Path
from feature_coverage import validate_registry, load, POLICY

root = Path(__file__).resolve().parent.parent
registry = load(root / 'docs/architecture/feature-registry.json')
assert not validate_registry(registry, load(POLICY))
result = subprocess.run([str(root / '.build/debug/Simplify'), '--state-contract'], capture_output=True, text=True, check=True)
native = json.loads(result.stdout)
expected = {s['id']: s for s in registry['settings']}
actual = {s['id']: s for s in native['definitions']}
assert len(actual) == len(native['definitions']), 'Duplicate native IDs'
assert set(expected) == set(actual) == set(native['runtime_ids']) == set(native['defaults'])
for key in expected:
    assert expected[key]['value_type'] == actual[key]['value_type']
    assert expected[key]['default'] == actual[key]['default'] == native['defaults'][key]
assert native['preset_ids'] == [] and native['preset_serialization'] == 'absent'
assert native['persistence'] == 'local-setup-v1' and native['migration'] == 'version 1; reject unsupported versions'
assert set(native['persistence_ids']) == {s['id'] for s in registry['settings'] if s['policies']['project_persistence'] == 'included'}
assert all(s['policies']['preset']['decision'] == 'excluded' for s in registry['settings'])
assert set(native['persistence_ids']) == {'roots', 'standard_plugins', 'onboarding_completed', 'appearance'}
print('Catalog state: PASS (exact IDs/defaults; setup persistence IDs; explicit preset exclusions)')

# Persistent inventory has its own runtime authority, separate from setup settings.
fields = registry['catalog_fields']
assert not validate_registry({**registry, 'settings': fields}, load(POLICY))
expected_catalog = {field['id']: field for field in fields}
actual_catalog = {field['id']: field for field in native['catalog_definitions']}
assert len(actual_catalog) == len(native['catalog_definitions'])
assert set(expected_catalog) == set(actual_catalog)
for key in expected_catalog:
    for field in ('value_type', 'default', 'introduced_in'):
        assert expected_catalog[key][field] == actual_catalog[key][field]
assert native['catalog_schema_version'] == 6
print('Catalog persistence: PASS (exact IDs/defaults and all cross-cutting decisions)')
