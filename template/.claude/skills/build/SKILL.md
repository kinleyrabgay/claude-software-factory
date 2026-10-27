---
name: build
description: Implement a task with the smallest correct diff, iterating against targeted tests until green, then run the full gate once. Use in the factory pipeline, or when asked to build or implement a factory task.
---

# Build

1. Implement the plan with the **smallest diff that fully solves the task**. Match the surrounding code: naming, error handling, comment density, file layout. Reuse existing helpers before writing new ones.
2. Iterate with the targeted test command (from triage or spec) until it passes. If spec wrote no tests (size S), add or update a test whenever the change has behaviour that can break.
3. Run the full gate once: `.claude/hooks/gate.sh --check`. Fix failures at the root cause.

Rules. The reviewer and the human both check these:
- Never skip, delete, loosen or `.only` tests, and never change an assertion just to make it pass. If a test is genuinely wrong, fix it and say so in the summary.
- No new dependencies unless the task cannot reasonably be done without one; name it in the summary.
- No unrelated refactors, formatting churn or drive-by fixes. Mention them in the summary instead.
- No placeholders: no TODO stubs, mock data in production paths or commented-out code.
- Handle the errors and edge cases the surrounding code handles.
- Do not commit; the runner commits.
