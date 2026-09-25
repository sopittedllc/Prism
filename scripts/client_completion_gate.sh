#!/bin/sh

set -eu

project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
exec "$project_root/.claude/hooks/completion_gate.sh" "${1:-check-if-marked-complete}"
