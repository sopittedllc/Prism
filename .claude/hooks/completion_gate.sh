#!/bin/sh

set -eu
project_dir=${CLAUDE_PROJECT_DIR:-"$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"}
mode=${1:-check-if-marked-complete}

if ! output=$(python3 "$project_dir/scripts/workflow_gate.py" "$mode" 2>&1); then
  echo "$output" >&2
  exit 2
fi

exit 0
