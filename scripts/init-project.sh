#!/bin/sh

set -eu

usage() {
  echo "Usage: $0 \"Project Name\" [generic|daisy-seed|juce|apple-app-store] [owner] [--primary claude|codex|balanced]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage

project_name=$1
profile=${2:-generic}
shift
[ "$#" -eq 0 ] || shift
owner="TODO"
primary_client="balanced"
if [ "$#" -gt 0 ] && [ "$1" != "--primary" ]; then
  owner=$1
  shift
fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --primary)
      [ "$#" -ge 2 ] || usage
      primary_client=$2
      shift 2
      ;;
    *) usage ;;
  esac
done
case "$primary_client" in
  claude|codex|balanced) ;;
  *) echo "Unknown primary client: $primary_client" >&2; usage ;;
esac
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
profile_dir="$project_dir/profiles/$profile"

[ -f "$profile_dir/PROJECT_PROFILE.md" ] || {
  echo "Unknown profile: $profile" >&2
  echo "Available profiles: generic, daisy-seed, juce, apple-app-store" >&2
  exit 2
}

grep -q '{{PROJECT_NAME}}' "$project_dir/AGENT_GUIDE.md" || {
  echo "Already initialized or missing project-name token in AGENT_GUIDE.md" >&2
  exit 2
}
grep -q '{{PROJECT_NAME}}' "$project_dir/PROJECT.md" || {
  echo "Already initialized or missing project-name token in PROJECT.md" >&2
  exit 2
}

cp "$profile_dir/PROJECT_PROFILE.md" "$project_dir/PROJECT_PROFILE.md"
cp "$profile_dir/toolchain.json" "$project_dir/.workflow/toolchain.json"
rm -f "$project_dir/STATE_REGISTRY_PROFILE.md"
if [ -f "$profile_dir/STATE_REGISTRY.md" ]; then
  cp "$profile_dir/STATE_REGISTRY.md" "$project_dir/STATE_REGISTRY_PROFILE.md"
fi
if [ -d "$profile_dir/rules" ]; then
  for rule in "$profile_dir/rules/"*.md; do
    [ -f "$rule" ] || continue
    mkdir -p "$project_dir/.agents/rules/profile"
    cp "$rule" "$project_dir/.agents/rules/profile/"
  done
fi

escape_replacement() {
  printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

escaped_name=$(escape_replacement "$project_name")
escaped_owner=$(escape_replacement "$owner")

for target in "$project_dir/AGENT_GUIDE.md" "$project_dir/CLAUDE.md" "$project_dir/AGENTS.md" "$project_dir/PROJECT.md"; do
  sed -e "s|{{PROJECT_NAME}}|$escaped_name|g" \
      -e "s|{{OWNER}}|$escaped_owner|g" "$target" > "$target.tmp"
  mv "$target.tmp" "$target"
done

python3 - "$project_dir/.workflow/collaboration.json" "$primary_client" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["primary_client"] = sys.argv[2]
if sys.argv[2] == "claude":
    data["review_client"] = "codex"
elif sys.argv[2] == "codex":
    data["review_client"] = "claude"
else:
    data["review_client"] = "alternate"
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

python3 "$project_dir/scripts/sync_agent_adapters.py"

rm -f "$project_dir/TOOLCHAIN_PROFILE_EXAMPLE.md"
if [ -f "$profile_dir/TOOLCHAIN.example.md" ]; then
  cp "$profile_dir/TOOLCHAIN.example.md" "$project_dir/TOOLCHAIN_PROFILE_EXAMPLE.md"
fi

if [ ! -d "$project_dir/.git" ]; then
  git -C "$project_dir" init
fi

# Set sopittedllc Git identity
git -C "$project_dir" config user.name "So Pitted"
git -C "$project_dir" config user.email "support@sopitted.llc"

cp "$project_dir/.github/templates/project-quality.yml" "$project_dir/.github/workflows/project-quality.yml"

echo "Initialized '$project_name' with profile '$profile' and primary client '$primary_client'."
echo "Next: run the bootstrap-toolchain skill, then give Claude or Codex your first idea."
echo "No files were committed, dependencies installed, or hardware programmed."
