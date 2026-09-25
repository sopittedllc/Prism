#!/usr/bin/env python3
"""Compatibility wrapper for the shared command policy guard."""

from pathlib import Path
import runpy

runpy.run_path(str(Path(__file__).resolve().parents[2] / "scripts" / "pretool_guard.py"), run_name="__main__")
