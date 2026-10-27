# Claude software factory: configuration. Sourced by the runner and the gate.
# Precedence: environment variable > this file > built-in default.
# Every line here is optional; delete what you do not need.

# GitHub label that queues an issue for the factory.
FACTORY_LABEL="${FACTORY_LABEL:-factory}"

# Branch that pull requests target. Empty means the remote's default branch.
FACTORY_BASE_BRANCH="${FACTORY_BASE_BRANCH:-}"

# Escalation ladder: one full session per model, cheapest first. A later model
# starts only when the previous one did not pass the gate.
FACTORY_MODELS="${FACTORY_MODELS:-sonnet opus}"

# Hard spending cap for one task, in USD, across every attempt.
FACTORY_MAX_COST_USD="${FACTORY_MAX_COST_USD:-10}"

# Wall-clock cap for one session, in seconds.
FACTORY_SESSION_TIMEOUT="${FACTORY_SESSION_TIMEOUT:-2700}"

# How many times the Stop hook sends a failing gate back to the same session
# before giving up and letting the runner escalate.
FACTORY_GATE_MAX_ATTEMPTS="${FACTORY_GATE_MAX_ATTEMPTS:-3}"

# Lines of failing output fed back to Claude. More lines cost more tokens.
FACTORY_GATE_TAIL_LINES="${FACTORY_GATE_TAIL_LINES:-60}"

# Push the branch of a failed attempt so a human can continue from it (1 or 0).
FACTORY_PUSH_FAILED="${FACTORY_PUSH_FAILED:-1}"

# Gate commands, run in order; the first failure stops the gate.
# Leave unset to auto-detect: package.json scripts lint, typecheck and test;
# pytest; go vet and go test; cargo test. Nothing detected means the gate fails:
# the factory never ships unverified work. Use ("true") to opt out on purpose.
# FACTORY_GATE_CMDS=("npm run -s lint" "npm run -s typecheck" "npm test --silent")

# Commands run once in the fresh worktree before Claude starts (install
# dependencies). Leave unset to auto-detect from the lockfile.
# FACTORY_SETUP_CMDS=("npm ci")
