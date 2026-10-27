# Architecture

## Principles

1. **Tokens only for judgement.** Anything a shell script can decide (queueing, git, verification, labels, pull requests) is a shell script. Claude reads, decides and writes code.
2. **Evidence over claims.** A task is done when the gate passes, not when the agent says so. The gate runs twice: as a Stop hook inside the session, and again in the runner before delivery.
3. **Rules in hooks, not prompts.** Prompts state the rules so the agent cooperates; hooks enforce them so a confused or manipulated agent cannot break them.
4. **Cheapest capable model first.** Escalate on evidence of failure, never by default.
5. **Fail closed, hand off clearly.** Missing gate, unclear task, protected change, crash: each ends in a labelled hand-off with a reason, never in silence or a half-done PR.

## Components

| Component | Kind | Model | Cost | Responsibility |
|---|---|---|---|---|
| `factory-run.sh` | Shell | none | 0 | Queue, lock, worktree, setup, escalation ladder, independent gate, delivery, hand-off |
| `factory` skill | Skill | ladder (sonnet, opus) | main | Orchestrates the stations inside one session; defines the input and output contract |
| `triager` | Subagent | haiku | low | Size, risk, clarity, `file:line` pointers, plan, targeted test command |
| `spec` skill | Skill | session model | medium | Acceptance criteria and failing tests (M, L or high risk only) |
| `build` skill | Skill | session model | main | Smallest correct diff; targeted tests, then the full gate once |
| `reviewer` | Subagent | opus | high | Adversarial review (high risk only) |
| `retro` skill | Skill | session model | tiny | At most 2 lessons per run |
| `guard.sh` | PreToolUse hook | none | 0 | Blocks dangerous commands, secret access, protected edits |
| `gate.sh` | Stop hook and CLI | none | 0 | Runs lint, typecheck and tests; sends failure tails back to Claude |

Triage and review are subagents because they need a **different model** and a **fresh context**: triage is cheap exploration that should not pollute the main context, and review must not share the builder's assumptions. Spec, build and retro are skills inside the main session because they need its context; splitting them into subagents would re-read the same files and pay for it twice.

## Lifecycle of one task

```
            ┌────────────── runner ──────────────────────────────────────────┐
 queue ───▶ │ lock → claim (label) → worktree on new branch → setup deps     │
            │                                                                │
            │  for model in ladder, while budget remains:                    │
            │     claude -p "run the factory skill" in the worktree          │
            │        triage → [spec] → build → [review] → retro → result     │
            │        Stop hook: gate fails? send tail back (max N times)     │
            │     result blocked?            → needs-info, stop              │
            │     runner gate passes + done? → deliver, stop                 │
            │     otherwise                  → next model (keeps the diff)   │
            │                                                                │
            │  deliver: protected-path check → commit → push → PR → labels  │
            │  fail:    WIP commit → push branch → needs-human + comment     │
            └─── exit trap: unlock, remove worktree, crash → needs-human ────┘
```

The next model on the ladder continues from the previous attempt's working tree and reads `gate-last.txt`. It fixes what failed instead of starting over, which is cheaper than a reset and rarely worse.

## Contracts

The runner and the session communicate only through files in `.factory/out/` (gitignored, per worktree):

| File | Writer | Reader | Content |
|---|---|---|---|
| `task.md` | runner | session | Issue title, body and comments, marked untrusted, truncated to `FACTORY_TASK_MAX_CHARS` |
| `attempt.json` | runner | session | Attempt number, model, previous model |
| `spec.md` | spec skill | build, reviewer | Acceptance criteria, out of scope, assumptions |
| `result.json` | session | gate, runner | `status`, `size`, `risk`, `summary`, `questions`, `tests` |
| `learning.md` | retro skill | runner | At most 2 lessons, appended to `learnings.md` in the PR |
| `gate-last.txt` | gate | session, runner | Full output of the last gate run |
| `session-N.json` | runner | runner | Claude's JSON result: cost, turns, subtype |

Per-run counters live in `.factory/state/` (also gitignored): `gate-attempts`, `gate-status`, and in the main checkout `runs.jsonl` (one line per attempt with model, outcome and cost) and the run lock.

## State machine (GitHub labels)

```
factory ──claim──▶ factory:in-progress ──PR──────────▶ factory:pr-open
                          │
                          ├──blocked──────────────────▶ factory:needs-info  ──answer + relabel──▶ factory
                          └──gate fails / protected
                             path / crash─────────────▶ factory:needs-human ──fix + relabel─────▶ factory
```

Labels are the queue, so the system has no other state to lose. A dropped workflow trigger costs nothing: the scheduled run finds the label later.

## Security model

Threats, and the layer that handles each:

| Threat | Layers |
|---|---|
| Prompt injection in issue text | Marked untrusted in `task.md`; every skill and agent treats it as data; the guard limits what any instruction could achieve; only triage-level users can label |
| Agent disables its own checks | Guard blocks edits to `.claude/` and `.factory/`; the runner rejects diffs touching protected paths; the runner reruns the gate itself |
| Secret exfiltration | Guard blocks env dumps, credential variable names, secret files; settings deny reading `.env`; CI should hold no production credentials |
| Destructive commands | Guard blocks recursive deletes of `/`, home or the project root, disk tools, pipe-to-shell, and force pushes, in every mode |
| Unreviewed changes reaching main | The agent cannot push or call `gh`; the runner only opens PRs; branch protection requires review |
| Runaway cost | `--max-budget-usd` with the remaining budget per session, session timeout, gate attempt cap, finite ladder |

The guard is pattern matching, so treat it as a seatbelt. The real sandbox is the environment: an ephemeral CI runner or container with scoped tokens.

## Decisions and alternatives

- **Claude Code as the runtime, not a custom agent loop.** It already handles tools, context compaction, subagents, skills, hooks and budgets. Building these again would cost months and add bugs.
- **One session per attempt, not one per station.** Stations share context inside a session; separate sessions would re-read the code each time.
- **Shell runner, not a workflow engine.** One task per run, with labels as durable state, needs no engine. If you later need fan-out across many repositories, the runner's contract (task in, result out) ports to any queue.
- **No tournaments by default.** Building several variants multiplies cost. The ladder gets most of the benefit for a fraction of the price. Add a tournament only for tasks you mark as critical.
