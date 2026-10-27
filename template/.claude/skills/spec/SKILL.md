---
name: spec
description: Turn a task into acceptance criteria and failing tests before any implementation (test-first). Use in the factory pipeline for size M or L or high-risk tasks, or when asked to spec a task.
---

# Spec: acceptance criteria and failing tests first

Goal: an executable definition of done, so the gate verifies the work and nobody has to trust the summary.

1. Write `.factory/out/spec.md`, at most 15 lines:
   - **Acceptance criteria**: a numbered checklist of observable behaviour (inputs and outputs, errors, edge cases). No implementation detail.
   - **Out of scope**: what you will deliberately not change.
   - **Assumptions**: decisions you made where the task is silent. Pick the conservative option.
2. Find the nearest existing test for the code you will change (same folder, or the triager's pointers) and copy its conventions: framework, file naming, fixtures, helpers. Do not add a test framework.
3. Write tests that encode the acceptance criteria: at least one per criterion, including at least one edge or error case.
4. Run only those tests. They must fail, and for the right reason (missing behaviour, not a typo or import error). Fix the test until that is true.
5. If the behaviour cannot be tested automatically (docs, copy, pure config), say so in `spec.md` and name the manual check instead.

Do not implement the feature in this step.
