#!/usr/bin/env bash
# PreToolUse guard. Exit 2 blocks the tool call and shows the reason to Claude.
#
#   Always on:   catastrophic shell commands (rm -rf /, mkfs, curl | sh, force push).
#   Factory mode (FACTORY_MODE=1, set by the runner) also blocks:
#     - git history/remote operations, all `gh` calls, publish and deploy tools
#     - reading or printing secrets
#     - edits to .claude/, .factory/ (except .factory/out/), .github/workflows/,
#       .git/, secret files, and anything outside the project
#
# This is a seatbelt, not a sandbox: run unattended sessions in CI or a container.
set -uo pipefail

block() {
  echo "Blocked by factory guard: $1" >&2
  exit 2
}

input="$(cat)"
command -v jq >/dev/null 2>&1 || block "jq is not installed, so this tool call cannot be checked."

tool="$(jq -r '.tool_name // empty' <<<"$input")"
factory="${FACTORY_MODE:-0}"
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"

has() { grep -Eq -- "$1" <<<"$2"; }

# Separator before a word: start, ; & | ( or whitespace.
B='(^|[;&|(`[:space:]])'
# Command position: start of a command, optionally behind npx/bunx/dlx/env VAR=x.
C='(^|[;&|(`])[[:space:]]*((npx|bunx|pnpm[[:space:]]+dlx|env([[:space:]]+[[:alnum:]_]+=[^[:space:]]*)+)[[:space:]]+)?'
# `git` plus global options (-C dir, --no-pager, ...) up to the subcommand.
G="${C}git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+|[[:space:]]+--?[[:alnum:]-]+(=[^[:space:]]+)?)*[[:space:]]+"

check_bash() {
  local cmd="$1"

  # --- always on ---
  if has "${B}rm[[:space:]]+([^;&|]*[[:space:]])?(-[[:alnum:]]*[rR][[:alnum:]]*|--recursive)([[:space:]]+[^;&|]*)?[[:space:]](/|/\*|~|~/|\\\$HOME|\\\$\{HOME\}|\.|\./|\.\.|\.\./)([[:space:]]|;|&|\||\)|$)" "$cmd"; then
    block "recursive delete of /, home, the project root or its parent."
  fi
  if has "${B}(sudo[[:space:]]+)?(mkfs(\.[[:alnum:]]+)?|fdisk|diskutil[[:space:]]+(erase|partition)[[:alnum:]]*)([[:space:]]|$)" "$cmd" ||
    has "${B}dd[[:space:]][^;&|]*of=/dev/" "$cmd" ||
    has ':\(\)[[:space:]]*\{' "$cmd"; then
    block "disk or system destructive command."
  fi
  if has "(curl|wget)[^;&]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da|k)?sh([[:space:]]|$)" "$cmd"; then
    block "piping a download into a shell."
  fi
  if has "${G}push([[:space:]][^;&|]*)?[[:space:]](-f|--force|--force-with-lease|--mirror|--delete|-d|\+[^[:space:]]+)([[:space:]=]|$)" "$cmd"; then
    block "force push or remote branch deletion."
  fi

  [[ "$factory" == 1 ]] || return 0

  # --- factory mode ---
  if has "${C}sudo([[:space:]]|$)" "$cmd"; then
    block "sudo is not available to the factory."
  fi
  if has "${G}(push|pull|fetch|switch|worktree|rebase|merge|filter-branch|filter-repo|update-ref|remote|reflog|gc|stash|tag)([[:space:]]|$)" "$cmd" ||
    has "${G}(reset[[:space:]]+--hard|clean[[:space:]]+-[[:alpha:]]*[fdx]|checkout[[:space:]]+-[bB]|branch[[:space:]]+-[dDmMcC]|config[[:space:]]+--(global|system))" "$cmd" ||
    has "${G}commit[^;&|]*--no-verify" "$cmd"; then
    block "the runner owns branches, history and remotes. Leave changes in the working tree."
  fi
  if has "${C}gh([[:space:]]|$)" "$cmd"; then
    block "the runner owns GitHub (issues, PRs, labels)."
  fi
  if has "${C}(npm|pnpm|yarn|bun)[[:space:]]+([^;&|]*[[:space:]])?publish([[:space:]]|$)" "$cmd" ||
    has "${C}(cargo[[:space:]]+publish|twine[[:space:]]+upload|docker[[:space:]]+push|gem[[:space:]]+push)" "$cmd" ||
    has "${C}(vercel|netlify|flyctl|fly|heroku|kubectl|helm|terraform|pulumi|aws|gcloud|az|firebase|wrangler|serverless|sls)([[:space:]]|$)" "$cmd"; then
    block "publishing and deploying are human decisions."
  fi

  # Secrets: dumping the environment, naming credential variables, reading secret files.
  if has "${C}(printenv|env|export|set|declare[[:space:]]+-[[:alpha:]]*x)[[:space:]]*($|[;&|>)])" "$cmd" ||
    has "(ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN|GH_TOKEN|GITHUB_TOKEN|FACTORY_GH_TOKEN|NPM_TOKEN|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN)" "$cmd" ||
    has "/proc/[^[:space:]]*/environ" "$cmd" ||
    has "(^|[[:space:]/'\"=])(\.env(\.[[:alnum:]_-]+)?|[^[:space:]]*\.(pem|key|p12|pfx)|id_(rsa|ed25519|ecdsa)[^[:space:]]*|\.netrc|\.npmrc|\.pypirc)([[:space:]'\";|&)]|$)" "$cmd"; then
    if ! has "\.env\.(example|sample|template)([[:space:]'\";|&)]|$)" "$cmd" || has "(ANTHROPIC_API_KEY|GH_TOKEN|GITHUB_TOKEN|printenv)" "$cmd"; then
      block "commands may not read or print secrets or the environment."
    fi
  fi

  # Writes to protected paths through the shell.
  if has "(\.claude/|\.factory/(bin|state|config\.sh|learnings\.md)|\.github/workflows|\.git/)" "$cmd" &&
    has "(>|${B}(rm|mv|cp|tee|ln|chmod|chown|truncate|install|rsync|touch|unlink)([[:space:]]|$)|sed[[:space:]]+(-[[:alpha:]]*[[:space:]]+)*-[[:alpha:]]*i|perl[[:space:]]+-[[:alpha:]]*i|git[[:space:]]+(checkout|restore|rm|mv|apply))" "$cmd"; then
    block "factory, CI and git internals are read-only for the agent."
  fi
  return 0
}

check_path() {
  local path="$1" write="$2" rel base
  [[ -n "$path" ]] || return 0
  [[ "$path" == /* ]] || path="$root/$path"
  case "$path" in
    */../* | */..) block "paths with .. are not allowed ($1)." ;;
  esac
  base="$(basename "$path")"
  case "$base" in
    .env.example | .env.sample | .env.template) ;;
    .env | .env.* | *.pem | *.key | *.p12 | *.pfx | id_rsa* | id_ed25519* | id_ecdsa* | .netrc | .npmrc | .pypirc)
      block "$base may hold secrets."
      ;;
  esac
  [[ "$write" == 1 ]] || return 0
  case "$path" in
    "$root"/*) ;;
    *) block "writes outside the project are not allowed ($path)." ;;
  esac
  rel="${path#"$root"/}"
  case "$rel" in
    .factory/out/*) ;;
    .claude/* | .factory/* | .github/workflows/* | .git/* | .git)
      block "$rel is owned by the factory, CI or git. If the task needs it changed, report status \"blocked\" and explain."
      ;;
  esac
  return 0
}

case "$tool" in
  Bash)
    check_bash "$(jq -r '.tool_input.command // empty' <<<"$input")"
    ;;
  Edit | Write | MultiEdit | NotebookEdit)
    if [[ "$factory" == 1 ]]; then
      check_path "$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")" 1
    fi
    ;;
  Read)
    if [[ "$factory" == 1 ]]; then
      check_path "$(jq -r '.tool_input.file_path // empty' <<<"$input")" 0
    fi
    ;;
esac
exit 0
