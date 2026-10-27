# Claude software factory

An autonomous, token-frugal software factory built on Claude Code. Label a GitHub issue `factory`, and the factory does the rest: it triages the issue, writes tests first when the change warrants it, implements the change, verifies it with your real lint, typecheck and test commands, and opens a pull request. When it cannot finish, it hands the issue back with a precise reason. A human always reviews and merges.

There is no server, database or custom agent framework. The whole factory is a set of Claude Code **skills**, **subagents** and **hooks**, plus one shell **runner**, all installed into your repository.

```
issue labelled "factory"
        │
        ▼
  runner (shell, 0 tokens) ── claims issue, makes an isolated worktree, installs deps
        │
        ▼
  Claude session (sonnet) ── factory skill
        ├─ triager subagent (haiku)       size, risk, file:line pointers, plan
        ├─ spec skill (M/L or high risk)  acceptance criteria + failing tests
        ├─ build skill                    smallest diff, targeted tests
        ├─ reviewer subagent (opus)       high risk only
        └─ retro skill                    at most 2 lessons for next time
        │
  Stop hook: gate (lint, typecheck, tests; 0 tokens), sends failures back, up to 3 times
        │
        ▼
  runner reruns the gate itself ──fail──▶ next model on the ladder (opus), same worktree
        │ pass                                   │ still failing / budget spent
        ▼                                        ▼
  commit, push, open PR                  label needs-human, push WIP branch, comment why
```

## Why it is cheap

Most agent systems spend tokens on work that needs no intelligence. This one spends them only where judgement is needed.

| Design choice | Effect |
|---|---|
| Git, labels, commits, pull requests and the gate are plain shell | Zero tokens for anything deterministic |
| Haiku triages and locates code; the main session starts from `file:line` pointers | The expensive model does not explore the repository |
| Small low-risk tasks skip spec and review | Most tasks touch one mid-size model and nothing else |
| Escalation ladder: sonnet first, opus only after a failure | Pay for the big model only when the small one could not do it |
| Gate failures feed back only the last 60 lines | No full logs in context |
| Hard caps: `--max-budget-usd` per task, session timeout, gate attempts | No runaway loops, a known worst case per task |
| Opus reviews only high-risk diffs | Review spend goes where the risk is |
| Skill text is stable across runs | Prompt-cache hits |
| `learnings.md` collects at most 2 lines per run, through reviewed PRs | The factory stops repeating mistakes without growing its prompt |

## Why it is robust

- **Verification is not the agent's opinion.** The gate runs your real commands. The Stop hook will not let a session end with a failing gate, and the runner reruns the gate independently before it delivers anything.
- **No unverified work ships.** If no gate commands are configured or detected, the gate fails.
- **Isolation.** Every run happens in its own git worktree on its own branch. Your working tree is never touched.
- **Guard rails, enforced by hooks rather than prompts.** In factory mode the agent cannot push, rewrite history, call `gh`, publish, deploy, read or print secrets, or edit `.claude/`, `.factory/`, `.github/workflows/` or `.git/`. The runner checks the final diff again and refuses changes to protected paths.
- **Crash safety.** A lock prevents concurrent runs. If the runner dies mid-task, its exit trap labels the issue `factory:needs-human` instead of leaving it stuck.
- **Untrusted input.** Issue text is marked as untrusted data, and every station is told to treat it as a description of work, never as instructions. Only people with triage access can add labels on GitHub.
- **Honest hand-offs.** Unclear tasks come back as `factory:needs-info` with specific questions. Failed tasks come back as `factory:needs-human` with the gate output and a pushed work-in-progress branch.
- **Test tampering is visible.** The build rules forbid weakening tests, the reviewer checks for it, and the PR carries a warning if any test files were deleted.

## Requirements

- Git, `jq`, Bash 3.2 or later (stock macOS works)
- [Claude Code](https://docs.claude.com/en/docs/claude-code) (`claude` on the PATH) and an Anthropic API key or Claude subscription login
- [GitHub CLI](https://cli.github.com/) (`gh`) for GitHub mode only

## Install

```bash
git clone <this repo> ~/claude-software-factory
~/claude-software-factory/install.sh /path/to/your/repo
```

The installer copies files that do not exist yet and never overwrites without `--force`. If your repository already has `.claude/settings.json`, it writes `.claude/settings.factory.json` for you to merge.

Then, in your repository:

```bash
.factory/bin/factory-run.sh --dry-run --task-file README.md
```

This shows the base branch, models, setup commands and **gate commands** the factory will use. If no gate commands are detected, set `FACTORY_GATE_CMDS` in `.factory/config.sh`.

Commit the files. The runner works in a fresh worktree, which only contains committed files:

```bash
git add .claude .factory .github
git commit -m "Add Claude software factory"
```

## Use

**Locally, with a task file.** No GitHub needed; the result is a local branch.

```bash
cat > task.md <<'EOF'
# Add a --json flag to the export command
Output the same fields as the table view, as a JSON array.
EOF
.factory/bin/factory-run.sh --task-file task.md
```

**Locally, against GitHub issues.** Takes the oldest open issue labelled `factory`, or the one you name.

```bash
.factory/bin/factory-run.sh
.factory/bin/factory-run.sh --issue 42
```

**Autonomously, in GitHub Actions.**

1. Add the `ANTHROPIC_API_KEY` repository secret.
2. Optional: add `FACTORY_GH_TOKEN` (a fine-grained PAT or GitHub App token with contents, issues and pull-requests write). Without it, GitHub does not run your CI on the factory's pull requests.
3. Push, and label an issue `factory`.

The workflow runs on the label, every 4 hours to drain the queue, and on manual dispatch.

## Labels: the queue and its states

| Label | Meaning | What you do |
|---|---|---|
| `factory` | Queued | Add it to queue an issue |
| `factory:in-progress` | A run has claimed it | Wait |
| `factory:pr-open` | A pull request is open | Review and merge |
| `factory:needs-info` | The task was unclear; questions are in a comment | Answer, then add `factory` again |
| `factory:needs-human` | No attempt passed the gate, or the change touched protected files | Take over from the pushed branch, or improve the issue and add `factory` again |

## Configuration

All settings live in `.factory/config.sh`, and any of them can be overridden by an environment variable of the same name.

| Setting | Default | Purpose |
|---|---|---|
| `FACTORY_MODELS` | `sonnet opus` | Escalation ladder, cheapest first |
| `FACTORY_MAX_COST_USD` | `10` | Spending cap per task, across all attempts |
| `FACTORY_SESSION_TIMEOUT` | `2700` | Seconds per Claude session |
| `FACTORY_GATE_CMDS` | auto-detect | Commands that define "done" |
| `FACTORY_SETUP_CMDS` | auto-detect | Dependency install in the fresh worktree |
| `FACTORY_GATE_MAX_ATTEMPTS` | `3` | Gate failures sent back to one session before escalating |
| `FACTORY_GATE_TAIL_LINES` | `60` | Lines of failure output fed back to Claude |
| `FACTORY_BASE_BRANCH` | remote default | Branch that pull requests target |
| `FACTORY_LABEL` | `factory` | Queue label, and the prefix for the state labels |
| `FACTORY_PUSH_FAILED` | `1` | Push the branch of a failed attempt for a human |
| `FACTORY_MAX_TURNS` | unset | Optional extra cap on turns per session |

Gate auto-detection: `package.json` scripts `lint`, `typecheck` and `test` (npm, pnpm, yarn or bun, chosen by lockfile); `pytest`; `go vet` and `go test`; `cargo test`.

## What is in the box

```
install.sh                         installer
template/                          everything that lands in your repository
  .claude/settings.json            registers the guard and gate hooks
  .claude/hooks/guard.sh           PreToolUse: blocks dangerous commands and protected edits
  .claude/hooks/gate.sh            Stop hook and `--check`: the deterministic quality gate
  .claude/skills/factory/          the pipeline: contract, steps, token rules
  .claude/skills/spec/             acceptance criteria and failing tests first
  .claude/skills/build/            smallest correct diff, test-driven
  .claude/skills/retro/            at most 2 lessons per run
  .claude/agents/triager.md        haiku: size, risk, pointers, plan
  .claude/agents/reviewer.md       opus: adversarial review, high risk only
  .factory/bin/factory-run.sh      the runner
  .factory/bin/lib.sh              shared shell helpers
  .factory/config.sh               settings
  .factory/learnings.md            the factory's memory
  .github/workflows/factory.yml    the autonomous trigger
tests/run.sh                       test suite (uses a stub claude; costs no tokens)
docs/architecture.md               design, contracts and decisions
docs/runbook.md                    operating, tuning and troubleshooting
```

## Tests

```bash
tests/run.sh
```

The suite builds a throwaway repository, installs the factory, and checks the guard rules, the gate protocol and full runner flows (success, escalation, blocked task, protected-path refusal) with a stub `claude`. It spends no tokens.

## Safety note

The guard hook is a seatbelt, not a sandbox: a determined process can get past pattern matching. Run unattended sessions in CI or a container with no production credentials, and keep branch protection on your default branch so that nothing merges without review.
