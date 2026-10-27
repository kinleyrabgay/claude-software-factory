#!/usr/bin/env bash
# Deterministic quality gate: lint, typecheck, tests. Costs no tokens.
#
#   As the Stop hook (factory mode only): refuses to let the session end until
#   the gate passes, feeding back only the tail of the failure. After
#   FACTORY_GATE_MAX_ATTEMPTS it lets the session end and the runner escalates.
#   Interactive sessions (FACTORY_MODE unset) are never gated.
#
#   gate.sh --check: run the gate once, print a short report, exit 0 or 1.
set -uo pipefail

mode=hook
if [[ "${1:-}" == "--check" ]]; then mode=check; fi

if [[ "$mode" == hook ]]; then
  cat >/dev/null 2>&1 || true
  if [[ "${FACTORY_MODE:-0}" != 1 ]]; then exit 0; fi
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${CLAUDE_PROJECT_DIR:-$(cd "$here/../.." && pwd)}"
if ! source "$root/.factory/bin/lib.sh" 2>/dev/null; then
  echo "gate: $root/.factory/bin/lib.sh not found" >&2
  if [[ "$mode" == check ]]; then exit 1; fi
  exit 0
fi
factory_load_config "$root"

out="$root/.factory/out"
state="$root/.factory/state"
mkdir -p "$out" "$state"
log_file="$out/gate-last.txt"
factory_gate_cmds "$root"

if [[ "$mode" == check ]]; then
  if factory_run_gate "$root" "$log_file"; then
    echo "gate: pass (${GATE_CMDS[*]})"
    exit 0
  fi
  echo "gate: FAIL at \`$GATE_FAILED_CMD\` (full log: .factory/out/gate-last.txt)"
  tail -n "$FACTORY_GATE_TAIL_LINES" "$log_file"
  exit 1
fi

attempts_file="$state/gate-attempts"
attempts="$(cat "$attempts_file" 2>/dev/null || echo 0)"
if ! [[ "$attempts" =~ ^[0-9]+$ ]]; then attempts=0; fi

# Count this failed stop. Block it (exit 2, message to Claude) until the limit,
# then let the session end so the runner can escalate or hand off.
fail_stop() {
  attempts=$((attempts + 1))
  echo "$attempts" >"$attempts_file"
  if ((attempts >= FACTORY_GATE_MAX_ATTEMPTS)); then
    echo fail >"$state/gate-status"
    echo "Factory gate: giving up after $attempts attempts; the runner will escalate." >&2
    exit 0
  fi
  printf 'Factory gate (attempt %s of %s): %s\n' "$attempts" "$FACTORY_GATE_MAX_ATTEMPTS" "$1" >&2
  exit 2
}

status="$(jq -r '.status // empty' "$out/result.json" 2>/dev/null || true)"
case "$status" in
  blocked)
    echo blocked >"$state/gate-status"
    exit 0
    ;;
  done) ;;
  *) fail_stop "write .factory/out/result.json with status \"done\" or \"blocked\" as the factory skill specifies, then end your turn." ;;
esac

if factory_run_gate "$root" "$log_file"; then
  echo pass >"$state/gate-status"
  exit 0
fi

fail_stop "$(printf '`%s` failed. Last %s lines of output:\n%s\n\nFix the root cause (never skip, delete or weaken tests), update .factory/out/result.json, then end your turn.' \
  "$GATE_FAILED_CMD" "$FACTORY_GATE_TAIL_LINES" "$(tail -n "$FACTORY_GATE_TAIL_LINES" "$log_file")")"
