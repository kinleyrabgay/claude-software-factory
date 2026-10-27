#!/usr/bin/env bash
# Install the Claude software factory into a git repository.
#
#   ./install.sh /path/to/repo                 copy files that do not exist yet
#   ./install.sh /path/to/repo --force         also overwrite existing files (keeps .bak copies)
#   ./install.sh /path/to/repo --no-workflow   skip the GitHub Actions workflow
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/template" && pwd)"
target="" force=0 workflow=1
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    --no-workflow) workflow=0 ;;
    -h | --help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 1 ;;
    *) target="$arg" ;;
  esac
done
[[ -n "$target" ]] || { echo "usage: ./install.sh /path/to/repo [--force] [--no-workflow]" >&2; exit 1; }
target="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repository: $target" >&2; exit 1; }

installed=() skipped=() notes=()
while IFS= read -r -d '' file; do
  rel="${file#"$src"/}"
  if [[ $workflow == 0 && "$rel" == .github/* ]]; then continue; fi
  dest="$target/$rel"
  if [[ -e "$dest" ]]; then
    if [[ "$rel" == .claude/settings.json && $force == 0 ]]; then
      cp "$file" "$target/.claude/settings.factory.json"
      notes+=(".claude/settings.json exists: merge the hooks from .claude/settings.factory.json into it, then delete that file.")
      continue
    fi
    if [[ $force == 0 ]]; then
      skipped+=("$rel")
      continue
    fi
    cp "$dest" "$dest.bak"
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$file" "$dest"
  installed+=("$rel")
done < <(find "$src" -type f -print0 | sort -z)

chmod +x "$target/.claude/hooks/"*.sh "$target/.factory/bin/"*.sh 2>/dev/null || true

echo "Installed into $target:"
for f in ${installed[@]+"${installed[@]}"}; do echo "  + $f"; done
for f in ${skipped[@]+"${skipped[@]}"}; do echo "  = $f (exists, kept; use --force to replace)"; done
for n in ${notes[@]+"${notes[@]}"}; do echo "  ! $n"; done

missing=""
for c in git jq claude gh; do command -v "$c" >/dev/null 2>&1 || missing="$missing $c"; done
if [[ -n "$missing" ]]; then echo; echo "Missing on this machine:$missing (gh is only needed for GitHub mode)"; fi

cat <<'EOF'

Next:
  1. Check the gate:      .factory/bin/factory-run.sh --dry-run --task-file <any.md>
     If it says no gate commands were detected, set FACTORY_GATE_CMDS in .factory/config.sh.
  2. Commit the files:    git add .claude .factory .github && git commit -m "Add Claude software factory"
  3. Try it locally:      .factory/bin/factory-run.sh --task-file task.md
  4. Go autonomous:       add the ANTHROPIC_API_KEY repository secret, push, and label an issue `factory`.
EOF
