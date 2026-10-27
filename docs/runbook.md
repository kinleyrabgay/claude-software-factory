# Runbook

## Writing tasks the factory finishes

The factory does best with issues a good engineer could finish without asking anything:

- **Outcome, not steps.** "Export supports `--json` with the same fields as the table" beats "edit export.ts".
- **Acceptance criteria.** A short checklist of observable behaviour becomes the spec and the tests.
- **Pointers when you have them.** A file, an endpoint, an error message, a failing command.
- **One concern per issue.** Split anything that would be more than one reviewable PR.

Good fits: bug fixes with a reproduction, small features, test coverage, refactors with a clear target, dependency bumps with a test suite. Poor fits: product decisions, large redesigns, anything needing production access.

## Daily operation

- **Queue work:** label issues `factory`.
- **Review PRs** labelled `factory:pr-open` like any other PR. The PR shows size, risk, attempts, cost and the gate commands that passed.
- **Answer `factory:needs-info`:** reply in the issue, then add `factory` again. Comments are part of the next task.
- **Take over `factory:needs-human`:** the comment says why it stopped. The branch with the work in progress is pushed; continue from it, or improve the issue and relabel.
- **Curate `.factory/learnings.md`:** lessons arrive through PRs. Delete stale or vague lines; keep it under about 60 lines.

## Watching cost

Every attempt appends a line to `.factory/state/runs.jsonl` (uploaded as a workflow artifact in CI):

```bash
jq -s 'group_by(.model) | map({model: .[0].model, runs: length, cost: (map(.cost_usd) | add)})' .factory/state/runs.jsonl
```

Levers, from most to least effective:

1. **Better issues.** Unclear issues burn a triage and come back anyway.
2. **A faster, narrower gate.** The gate runs at least twice per attempt. Keep `FACTORY_GATE_CMDS` to what proves correctness.
3. **`CLAUDE.md` with test commands and conventions.** The triager stops rediscovering them.
4. **A cheaper ladder.** `FACTORY_MODELS="haiku sonnet"` for repositories with simple tasks.
5. **A lower cap.** `FACTORY_MAX_COST_USD=3`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `... is not committed` | The worktree only has committed files | Commit `.claude/`, `.factory/` and `.github/` |
| Every run ends `needs-human` with "No gate commands" | Nothing auto-detected | Set `FACTORY_GATE_CMDS` in `.factory/config.sh` |
| Gate fails on a clean checkout | Your main branch is red, or setup is missing a step | Fix main first; set `FACTORY_SETUP_CMDS` (codegen, env files, services) |
| `Setup command failed` | Dependency install failed in the fresh worktree | Run the setup command locally in a clean clone; set `FACTORY_SETUP_CMDS` |
| The factory's PRs do not run CI | PRs created with `GITHUB_TOKEN` do not trigger workflows | Add the `FACTORY_GH_TOKEN` secret |
| `another factory run is active` | A run is in progress, or one crashed | The lock clears itself when its process is gone; otherwise delete `.factory/state/run.lock` |
| The issue is stuck on `factory:in-progress` | The job was killed hard (runner timeout, cancelled) | Remove the label, add `factory` again |
| A session blocked by the guard for a legitimate command | Pattern false positive | Adjust the pattern in `.claude/hooks/guard.sh`, and add a case to `tests/run.sh` |
| Want to inspect a run locally | Worktrees are removed after each run | `FACTORY_KEEP_WORKTREE=1 .factory/bin/factory-run.sh ...`, then look in `.factory/worktrees/` |

## Extending

- **New station:** add a skill under `.claude/skills/`, call it from a step in the `factory` skill, and give it a file in `.factory/out/` as its output. Keep the rule: a skill if it needs the session's context, a subagent if it needs a different model or a fresh view.
- **New guard rule:** add a pattern in `guard.sh` and a blocked and an allowed case in `tests/run.sh`.
- **Other trackers:** replace the GitHub section of `factory-run.sh` (pick, claim, hand-off, deliver). The session contract does not change.
- **Parallel runs:** the lock allows one run per checkout. For parallelism, run several CI jobs with different issues; each gets its own checkout.
