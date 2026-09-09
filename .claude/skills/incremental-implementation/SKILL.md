---
name: incremental-implementation
description: Use when implementing any item of a PRD's "## Implementation plan", or any change touching more than one file. Enforces thin, reversible slices and one small PR per item — never a giant PR bundling several plan items.
---

# incremental-implementation — thin, reversible slices (dev-loop)

In the dev-loop, a PRD carries a `## Implementation plan` where **each item = 1 PR**. The R2
routine executes that plan by opening small, focused PRs, each one with `Part of dev-loop#N`
in the description, with a cap of **at most 3 items per run**. This skill is the discipline
that makes that model work: if an "item" ends up being 800 lines touching 4 layers, it's not
an item — it was cut wrong and must be split before writing code.

It's not optional or negotiable for speed: a big PR is slower to review, slower to revert,
and breaks the "3 items per run" count because a badly cut item eats the budget of the other
two.

## The cycle

**Implement → Test → Verify → Commit → PR.** It repeats for each plan item, not once at the
end of the whole PRD.

1. Take the next unchecked item of the implementation plan (don't jump ahead to future items).
2. Implement ONLY that item.
3. Run build + test + lint for the target repo's stack (see table below).
4. Commit with Conventional Commits.
5. Open the PR: clear title, description with `Part of dev-loop#N`, item checkbox marked in
   the PRD/task list if applicable.
6. Repeat with the next item — never bundle two items into the same PR to "save a run".

## Rules (in priority order)

**Rule 0 — The simplest thing that works.** Before writing code: what is the simplest version
of this item? If the PRD's item is already simple, don't complicate it by adding abstractions
the plan didn't ask for.

**Rule 0.5 — Scope discipline.** Touch ONLY the files the item requires. Seeing a neighboring
file "that could also be improved" is not a license to touch it in this PR — that's scope
creep, and in `review-pr` (this repo's own review standard) a description that doesn't match
the diff is a **BLOCKER** finding. If you spot something worth fixing, note it as a new plan
item, don't hang it here.

**Rule 1 — One logical change per PR.** One implementation-plan item = one logical unit. If
you notice the item is actually two independent things, split it into two PRs — even if that
means renegotiating the PRD's implementation plan before continuing.

**Rule 2 — Build and tests must pass after every PR.** There is no "I'll fix it in the next
item". Per stack (use the one that applies to the target repo, not all of them):

```bash
# Rust
cargo build --release --locked && cargo test && cargo clippy --all-targets -- -D warnings && cargo fmt --all

# Ruby on Rails
bundle exec rspec [spec/path_spec.rb[:line]]

# Go
make test && make fmt   # or: go build ./... && go test ./... && golangci-lint run

# Python
make init && make test && make fmt

# TypeScript/Node & SPA frontends
yarn build && yarn test && yarn lint

# Infrastructure-as-code
# use the repo's dry-run/validate commands (e.g. server-side dry-run, plan, kustomize build)
```

**Rule 3 — Feature flags when the item leaves behavior incomplete.** If the plan item
introduces something not yet complete end-to-end (e.g.: backend ready but the next item's
frontend doesn't consume the endpoint yet), the PR must merge with the flag off by default.
If the item is self-contained and breaks nothing when merged (the most common case when the
plan is well cut), do NOT add an artificial flag — that's complexity nobody asked for.

Concrete examples per stack:

```typescript
// TypeScript frontend — runtime config, off by default
// app config
export const config = { features: { newFilter: false } }

// in the component/composable
if (config.features.newFilter) { /* new code */ }
```

```python
# Python (hexagonal) — settings via env var, conservative default
class Settings(BaseSettings):
    feature_new_scoring: bool = False  # off until the item that activates it merges

# in the adapter/service
if settings.feature_new_scoring:
    ...
```

```go
// Go (Clean Architecture) — flag in config, injected via DI
type Config struct {
    FeatureNewRule bool `env:"FEATURE_NEW_RULE" envDefault:"false"`
}
// in app/ (never in domain/) — domain must not know a flag exists
if cfg.FeatureNewRule { ... }
```

**Rule 4 — Conservative defaults.** New code off/no-op by default until the item that
completes it merges. Never the other way around (on by default "because it's almost ready
anyway").

**Rule 5 — Every PR must be independently revertible.** If reverting item 2's PR breaks the
already-merged item 1, the cut is wrong. This connects directly to the repo's sacred rule:
reverting is always `revert/X` → PR → the owner merges, never a direct revert. A small,
isolated PR makes that revert trivial; a PR mixing items makes it impossible without dragging
along unrelated work.

## Slicing strategies (for implementation-plan items)

If, when reading the `## Implementation plan`, an item looks big, apply one of these before
starting to code (and if needed, update the PRD/task list with the new cut):

1. **Vertical (thin end-to-end):** one complete path through the stack for one case, not all
   cases. E.g.: "create ticket" before "create + edit + delete" in a single PR.
2. **Contract-first:** if the item crosses backend/frontend, define the contract (schema/DTO)
   in one PR, and implement each side in separate PRs against that fixed contract.
3. **Risk-first:** if the item has an uncertain part (external integration, data migration,
   behavior of a third-party service), that part goes first and alone — if it fails, it fails
   cheap, before investing in what depends on it.

## Checklist before opening the PR

- [ ] The PR does ONE complete thing (one plan item, no more, no less)
- [ ] Build passes
- [ ] Existing tests pass
- [ ] Type checking / lint pass
- [ ] The item's new functionality works (verified, not just "it compiles")
- [ ] Commit in Conventional Commits
- [ ] PR description includes `Part of dev-loop#N`
- [ ] If the item leaves something incomplete: flag off by default

## Red flags — stop writing code if you see this

- More than ~100 lines written without running build/test
- The PR touches modules or layers the plan item doesn't mention
- You are combining two plan items "because they're similar"
- The build is broken between commits of the same PR
- You are building a generic abstraction for a single use case
- This item's PR depends on another PR (from another item) merging first to not break prod —
  a sign the plan's cut is wrong, not that the merge needs coordinating

## Simplicity — examples

- ✗ A generic `EventBus` with a middleware pipeline to notify a single event
- ✓ A direct function call
- ✗ A config-driven flag for something the same PR already completes end-to-end
- ✓ No flag — the PR is small and safe to merge as-is

---

Adapted for the dev-loop from Addy Osmani's "incremental-implementation" skill —
github.com/addyosmani/agent-skills (MIT).
