---
name: retro
description: Capture at most two reusable lessons from a factory run into .factory/out/learning.md. Use at the end of every factory run.
---

# Retro

Ask one question: did anything in this run cost extra turns that a one-line note would have prevented next time? For example a test command that needs a flag, a non-obvious convention, a directory to avoid, a flaky check.

- If yes, write up to two lines to `.factory/out/learning.md`, each as `- [area] lesson`. Be specific and imperative: `- [api] Run tests with npm test -- --runInBand; parallel runs share one database.`
- If no, write nothing. Most runs should write nothing.
- Never repeat a lesson already in `.factory/learnings.md`, and never record facts about this one task.

The runner adds your lines to `.factory/learnings.md` through the pull request, so a human reviews every lesson before future runs read it.
