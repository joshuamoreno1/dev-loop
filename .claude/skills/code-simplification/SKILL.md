---
name: code-simplification
description: Review or apply code simplification to improve clarity WITHOUT changing behavior — deep nesting, long functions, generic names, duplication, dead code, excess comments. Use it in the review routines (R0/R5) to evaluate simplification/clarity of a diff without touching functionality, and in any refactor where the goal is readability, not new features. Do NOT use it if the code is already clear, if you don't fully understand what it does (apply Chesterton's Fence first), if it's performance-critical code where a "simpler" version would be measurably slower, or if the code is scheduled for a full rewrite.
---

# code-simplification — Clarity without breaking behavior

Simplifying is not reducing lines; it's reducing the time it takes someone on the team to
understand the code. The question that decides every change: **would a new dev understand
this faster than the original?** If the answer is no, revert the change — you didn't
simplify, you generated churn.

In the dev-loop, this skill is used by the review routines (**R0/R5**) to judge whether a diff
is simple and clear without having altered behavior; it also applies whenever any routine
simplifies code directly, within the scope of what it's already touching.

## When to use / when NOT

**Use when:**
- A feature already passed tests but ended up over-engineered under time pressure.
- A review flags deep nesting, long functions, or confusing naming.
- There is duplicated logic across files after a merge, or post-merge inconsistency.
- You're reviewing a PR (R0/R5) and need to decide whether the diff is readable, not whether
  it's "correct" (that's `review-pr`, dimension C — here the focus is only clarity/simplicity).

**Do NOT use when:**
- The code is already clear — don't invent simplifications to justify the exercise.
- You don't fully understand what the code does. Chesterton's Fence first (below); if after
  reading context, tests, and `git blame` you still don't understand it, don't touch it.
- It's performance-critical code where the simple version would be measurably slower.
- The code is scheduled for a full rewrite — don't invest in polishing something being deleted.

## Principles

1. **Preserve exact behavior.** Same input → same output, same side effects, same order,
   same error behavior. Before touching anything: does this pass the same tests without
   modifying them? If you have to touch a test for the simplification to pass, you changed
   behavior — that's not a refactor, it's something else.
2. **Follow the repo's conventions, not yours.** The target repo's `CLAUDE.md` and the global
   layer outrank personal preference. Simplifying while breaking consistency with the rest of
   the code is churn, not improvement.
3. **Clarity over cleverness.** An explicit `if/else` beats a nested ternary or a chain of
   `.reduce()` if you have to parse mentally to understand it.
4. **Balance — don't over-simplify.** Aggressive inlining that deletes a helper that named a
   concept, or removing a repository interface that exists for testing/mocking (even if it has
   a single implementation today), is not simplification: it breaks Clean Architecture/DI.
   Optimizing for fewer lines instead of comprehension is the same mistake in reverse.
5. **Scope = what changed.** You simplify the code the task is already touching; you don't go
   out doing drive-by refactors of unrelated files. That generates noisy diffs and regression
   risk in something nobody asked to review.

## Chesterton's Fence — understand before touching

Before simplifying anything, answer:
- What is this code's responsibility? Who calls it, what does it call?
- What edge cases and error paths does it cover?
- Are there tests defining the expected behavior? Read them.
- Why might it have been written this way? What do `git blame`/the original commit say?

If you can't answer these questions, you're not ready to simplify — read more context first
(neighboring code, original PR, tests). Accumulated complexity often has no real reason behind
it, but the only way to know is to look, not to assume.

## Process

### 1. Identify opportunities

| Pattern | Signal | Simplification |
|---|---|---|
| Deep nesting (3+ levels) | `if` inside `if` inside `if` | Guard clauses / early return, extract a function |
| Long functions (50+ lines) | One method does everything | Split into functions with descriptive names |
| Nested ternaries | Hard to read in one pass | `if/else`, `switch`, or lookup table |
| Boolean flag parameters | `doThing(x, true, false)` | Options object or separate functions |
| Repeated conditionals | Same `if` in several places | Extract a clearly named predicate function |
| Generic names | `data`, `temp`, `result`, `val` | Name by what it contains |
| Abbreviations | `usr`, `cfg`, `btn` | Full word (except `id`, `url`, `api`) |
| Duplication (5+ lines) | Same block copied | Extract to a shared function/module |
| Dead code | Unreachable, feature flag already resolved | Delete (confirm nothing calls it first) |
| Unnecessary abstraction | Wrapper that only delegates | Inline, call the thing below directly |
| Data/field that breaks the schema | A value that no longer fits downstream | **Delete it, don't substitute a heuristic** (see below) |

**Comments:** default is not to add them. A comment explaining the "what" gets deleted if the
code is already readable (rename instead of commenting). A "why" comment is preserved only if
it documents something the code cannot express — a non-obvious workaround for an external API,
a hidden invariant, a bug guard. One line, not a paragraph. No docstrings explaining PR
context or design decisions — that goes in the commit/PR description.

**Prefer deleting over substituting.** If a field or datum breaks validation/schema downstream
and there is no clean source for a valid value, delete it (`data.pop("field", None)`). Don't
add a heuristic ("if it's too long, replace it with X") or a conditional substitution chain:
that couples the code to assumptions about the consumer and adds one more branch to maintain.

### 2. Apply incrementally

One change → run tests → if they pass, continue. A simplification refactor goes in its own PR
or commit, separate from features/bugfixes (one thing per PR). If the refactor touches **more
than 500 lines**, don't do it by hand: invest in automating it (codemod, `sed`/AST script) —
at that scale, manual editing is error-prone and exhausting to review (same criterion as
"automate anything done manually 2+ times" from the global CLAUDE.md).

### 3. Verify the result

Is the simplified version genuinely faster to understand? Did you introduce inconsistency
with the rest of the repo's code? Is the diff clean and reviewable in one pass? If the answer
to the first is "no" or you're unsure, revert — the diff isn't worth it.

## Per stack (Clean Architecture / SOLID)

- **Go** — Clean Architecture (`cmd/ → app/ → domain/ → repositories/ → infrastructure/`).
  Don't delete repository interfaces for having a single implementation: they exist for DI
  and testing, they are not over-engineering. Simplifying here means flattening fat HTTP
  handlers, not deleting the domain/infra boundary.
- **Python** — Hexagonal/Port-Adapter (`domain/port/ → adapter/`). The domain doesn't import
  the web framework or adapters — if a simplification adds that import to "save a layer",
  it's not simplification, it's breaking the architecture. Linter clean, guard clauses
  instead of nesting.
- **Frontend (SPA)** — business logic in composables/stores/hooks, not in the component.
  Simplifying a fat component means moving logic to the composable/store where it belongs,
  not flattening it inside the component body.
- **Rails** — logic in service objects, not in the controller or chained model callbacks.
  Duplication between specs is solved with shared examples/factories, not copy-paste.

## Red flags — if you're doing this, stop

- You had to modify a test for the "refactor" to pass → you changed behavior.
- The result ended up longer or harder to follow than the original.
- You renamed by personal preference, not by repo convention.
- You deleted error handling "because it looked cleaner" (`except: pass`, ignoring an `err`).
- You're simplifying code you don't fully understand (go back to Chesterton's Fence).
- You stuffed many unrelated simplifications into a single commit/PR.
- You went outside the task's scope to refactor something nobody asked you to touch.
- You substituted a broken datum with a heuristic instead of deleting it.

## Verification checklist

- [ ] All existing tests pass without having been modified.
- [ ] The stack's build/lint passes clean (`cargo clippy && cargo fmt`, `ruff`, `eslint`,
      `rubocop` depending on the repo).
- [ ] Each simplification is incremental and reviewable on its own (not one giant commit).
- [ ] The diff has no changes unrelated to the task's scope.
- [ ] The simplified code follows the target repo's `CLAUDE.md` conventions.
- [ ] No error handling was removed or weakened.
- [ ] No dead code, unused imports, or redundant explanatory comments remain.
- [ ] No broken datum was "fixed" with a heuristic substitution instead of deletion.

---
Adapted from Addy Osmani's "code-simplification" skill — github.com/addyosmani/agent-skills (MIT).
