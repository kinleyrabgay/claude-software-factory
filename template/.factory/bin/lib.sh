#!/usr/bin/env bash
# Shared helpers for the factory runner and hooks.
# Sourced, never executed. Keep it Bash 3.2 compatible (stock macOS bash).

log() { printf '[factory %s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "error: $*"; exit 1; }

# Load .factory/config.sh, then fill anything still unset with defaults.
# Precedence: environment variable > config file > default below.
factory_load_config() {
  local root="$1"
  if [[ -f "$root/.factory/config.sh" ]]; then
    # shellcheck source=/dev/null
    source "$root/.factory/config.sh"
  fi
  : "${FACTORY_LABEL:=factory}"
  : "${FACTORY_BASE_BRANCH:=}"
  : "${FACTORY_MODELS:=sonnet opus}"
  : "${FACTORY_MAX_COST_USD:=10}"
  : "${FACTORY_MAX_TURNS:=}"
  : "${FACTORY_SESSION_TIMEOUT:=2700}"
  : "${FACTORY_GATE_MAX_ATTEMPTS:=3}"
  : "${FACTORY_GATE_TIMEOUT:=900}"
  : "${FACTORY_GATE_TAIL_LINES:=60}"
  : "${FACTORY_TASK_MAX_CHARS:=20000}"
  : "${FACTORY_PUSH_FAILED:=1}"
  : "${FACTORY_WORKTREE_DIR:=$root/.factory/worktrees}"
  : "${FACTORY_ALLOWED_TOOLS:=Read,Edit,Write,MultiEdit,Glob,Grep,Bash,Skill,Task,Agent,TodoWrite}"
  : "${FACTORY_GIT_NAME:=claude-factory}"
  : "${FACTORY_GIT_EMAIL:=claude-factory@users.noreply.github.com}"
  [[ -n "${FACTORY_GATE_CMDS+set}" ]] || FACTORY_GATE_CMDS=()
  [[ -n "${FACTORY_SETUP_CMDS+set}" ]] || FACTORY_SETUP_CMDS=()
}

# Run a command with a wall-clock limit, using whatever this machine has.
factory_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed: $!\n"' "$secs" "$@"
  fi
}

# Package manager for a Node project, from its lockfile.
_factory_node_pm() {
  local root="$1"
  if [[ -f "$root/pnpm-lock.yaml" ]]; then echo pnpm
  elif [[ -f "$root/yarn.lock" ]]; then echo yarn
  elif [[ -f "$root/bun.lockb" || -f "$root/bun.lock" ]]; then echo bun
  else echo npm
  fi
}

# Sets GATE_CMDS: explicit FACTORY_GATE_CMDS, else detected from repo files.
# An empty result is a failure on purpose: an unverified change never ships.
factory_gate_cmds() {
  local root="$1" pm s
  GATE_CMDS=()
  if [[ ${#FACTORY_GATE_CMDS[@]} -gt 0 ]]; then
    GATE_CMDS=("${FACTORY_GATE_CMDS[@]}")
    return 0
  fi
  if [[ -f "$root/package.json" ]]; then
    pm="$(_factory_node_pm "$root")"
    for s in lint typecheck test; do
      if jq -e --arg s "$s" '.scripts[$s] // empty' "$root/package.json" >/dev/null 2>&1; then
        GATE_CMDS+=("$pm run $s")
      fi
    done
  fi
  if [[ -f "$root/pyproject.toml" || -f "$root/pytest.ini" || -f "$root/setup.cfg" ]]; then
    GATE_CMDS+=("python -m pytest -q")
  fi
  if [[ -f "$root/go.mod" ]]; then
    GATE_CMDS+=("go vet ./..." "go test ./...")
  fi
  if [[ -f "$root/Cargo.toml" ]]; then
    GATE_CMDS+=("cargo test --quiet")
  fi
  return 0
}

# Sets SETUP_CMDS: explicit FACTORY_SETUP_CMDS, else dependency install by lockfile.
factory_setup_cmds() {
  local root="$1"
  SETUP_CMDS=()
  if [[ ${#FACTORY_SETUP_CMDS[@]} -gt 0 ]]; then
    SETUP_CMDS=("${FACTORY_SETUP_CMDS[@]}")
    return 0
  fi
  if [[ -f "$root/package.json" ]]; then
    case "$(_factory_node_pm "$root")" in
      pnpm) SETUP_CMDS=("pnpm install --frozen-lockfile") ;;
      yarn) SETUP_CMDS=("yarn install --immutable || yarn install --frozen-lockfile") ;;
      bun) SETUP_CMDS=("bun install --frozen-lockfile") ;;
      *) if [[ -f "$root/package-lock.json" ]]; then SETUP_CMDS=("npm ci"); else SETUP_CMDS=("npm install"); fi ;;
    esac
  fi
  return 0
}

# Run GATE_CMDS in order, stopping at the first failure. Full output goes to
# $2; sets GATE_FAILED_CMD. Returns 0 when every command passed.
factory_run_gate() {
  local root="$1" log_file="$2" cmd rc
  GATE_FAILED_CMD=""
  : >"$log_file"
  if [[ ${#GATE_CMDS[@]} -eq 0 ]]; then
    echo 'No gate commands configured or detected. Set FACTORY_GATE_CMDS in .factory/config.sh (use ("true") to opt out explicitly).' >"$log_file"
    GATE_FAILED_CMD="(no gate commands)"
    return 1
  fi
  for cmd in "${GATE_CMDS[@]}"; do
    echo "\$ $cmd" >>"$log_file"
    rc=0
    (cd "$root" && export CI=1 && factory_timeout "$FACTORY_GATE_TIMEOUT" bash -c "$cmd") >>"$log_file" 2>&1 || rc=$?
    if [[ $rc -ne 0 ]]; then
      echo "[exit $rc]" >>"$log_file"
      GATE_FAILED_CMD="$cmd"
      return 1
    fi
  done
  return 0
}
