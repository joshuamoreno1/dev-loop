---
name: planning-and-task-breakdown
description: Breaks a dev-loop PRD down into its "## Implementation plan" — each item = 1 small PR, with a target repo, explicit dependencies, and verifiable acceptance criteria. Use it when building the plan (R1 · Builder) or when refining it with owner feedback (R7 · Refiner), always BEFORE R2 opens the first PR. It does not implement code.
---

# planning-and-task-breakdown — A PRD's implementation plan

A good "## Implementation plan" is the difference between a PRD that R2 implements reliably,
in parallel and without getting stuck, and one that produces half-finished PRs, PRs in the
wrong repo, or PRs blocked by an unseen dependency. Remember the canonical cardinality:
**PRD → PR is 1:N** — each plan item is exactly 1 PR, in a concrete target repo.

## When to use

- You are in **R1 (Phase B · Builder)** generating the body of a new PRD.
- You are in **R7 (Refiner)** incorporating owner feedback that changes the scope, repos or
  acceptance criteria of the existing plan.
- The owner manually asks "break this down into PRs" on an issue.

**When NOT to use:** the PRD already has a plan with small items, a target repo and verifiable
criteria — don't rewrite it for the sake of rewriting. Don't use it either to plan WITHIN a PR
(that is R2's job while implementing the item, not this skill's).

## The process

### Step 1 — Plan mode (read-only, zero code)

Before writing the plan:
- Read the full PRD: context, problem, functional/non-functional requirements, high-level
  acceptance criteria, risks/dependencies already noted.
- For each candidate repo, read its `CLAUDE.md` (architecture, conventions, build & test
  Quick Reference) — the plan you generate must respect that architecture, not invent its own.
- If the PRD carries real ambiguity (you don't know what it requires without guessing), do NOT
  fill the gap: it goes to "OPEN QUESTIONS" + label `prd:blocked`, not into the plan.

**Do not open code, do not create branches, do not open PRs in this step.** The only output is
the plan text inside the PRD Issue body (there is no local `tasks/plan.md` — the GitHub Issue
IS the plan document; there is no memory between runs, so state lives there).

### Step 2 — Map the dependency graph (across repos)

Unlike a single-repo plan, dependencies here usually cross repos:

```
backend-api: new endpoint (schema + API)
    │
    ├── web-frontend: UI that calls the endpoint
    │
    └── infra: new env var / secret (if the endpoint needs new config)
```

Hard sequencing rule: if one item changes the runtime that another item's infrastructure
config deploys, the order is 1) CD workflow + runtime code → 2) wait for the image/artifact
build → 3) infrastructure resources. Never the reverse.

### Step 3 — Each item is a PR that is mergeable on its own

Don't cut by technical layer within the same repo — cut by functional delivery. An item that
"leaves the schema half-done" is not a PR, it's half a task.

**Bad (horizontal cut, no item is mergeable on its own):**
```
Item 1: Schema migration in backend-api
Item 2: API endpoints in backend-api
Item 3: HTTP client in another-service
Item 4: UI in web-frontend
```
(Items 1 and 2 don't pass CI independently if the second depends on running both together;
and if the reviewer only approves item 1, the repo ends up with dead, unused schema.)

**Good (cut by delivery, each item works and passes its own gate):**
```
Item 1 (backend-api): complete endpoint (schema + API + tests) — works standalone, even if
  nothing consumes it yet.
Item 2 (another-service): integration that consumes Item 1's endpoint — depends on Item 1.
Item 3 (web-frontend): UI that consumes Item 2's integration — depends on Item 2.
```

If within ONE repo the change is small, a single item can cover schema+logic+tests — the rule
is not "1 item = 1 layer", it's "1 item = 1 PR that compiles, passes CI and breaks nothing
on its own".

### Step 4 — Structure every item the same way

Fixed format so that R2 implements it without interpreting, R5 can audit it and the owner
reads it fast:

```markdown
- [ ] **Item N — <short title, no "and" in the title>** — repo: `<org>/<target-repo>`
  - **Description:** what this PR does, in one sentence.
  - **Acceptance criteria (verifiable):**
    - [ ] <specific, checkable condition, not "works well">
    - [ ] <specific, checkable condition>
  - **Local verification (repo Quick Reference):** `<lint/test/build command from the repo's
    CLAUDE.md, e.g. cargo clippy --all-targets -- -D warnings && cargo test>`
  - **Dependencies:** Item M (or "None")
  - **Estimated size:** S | M | L (if it comes out L+, split it into 2 items)
```

If you can't write the acceptance criteria in 3 bullets or fewer, or the title needs an "and"
to describe it, that's a sign it's two items, not one.

### Step 5 — Order the items and leave checkpoints (per the state machine)

Order the items respecting Step 2's graph (foundations first). The "checkpoint" in this
context is not a manual pause — it's the PRD's aggregate label, which R2/R5 compute on their own:

| Checkpoint | When | Who moves it |
|---|---|---|
| `prd:building` | Plan items without an open PR remain | R2 |
| `prd:arch-review` | ALL items have an open PR, under review by the configured reviewers | R2 → R5 |
| `prd:ready-for-review` | EVERY PR passed its gate (green CI + comments resolved + reviewer APPROVED) | R5 |
| `prd:done` | ALL PRs merged | R5 |

A badly ordered plan (item 3 depends on an item 5 that doesn't exist yet) translates directly
into a PR stuck in `prd:building` — that's why dependencies go explicitly on each item, not
implicitly in the list order.

## Size of each item (PR)

| Size | Scope | Example | Rule |
|---|---|---|---|
| **S** | 1 endpoint / 1 component / 1 migration | Add a field to a serializer | Ideal — R2 does it in one run |
| **M** | One complete feature slice in 1 repo | Endpoint + tests + doc for a new resource | Acceptable |
| **L** | Crosses 2+ repos or 2+ subsystems | "Integrate X with Y" without breakdown | **Break it down** into S/M items before leaving it in the plan |
| **XL** | The whole PRD in one item | "Implement the feature" | Never — that's the absence of a plan, not an item |

R2 opens **at most 3 items without a PR per run** — plans made of only L/XL items guarantee
that R2 runs out of runs and the PRD stalls in `prd:building` for weeks.

**Signals that an item needs a breakdown:**
- It touches 2+ distinct target repos.
- The acceptance criteria don't fit in 3 bullets.
- The title carries an "and" or "also".
- You can't name the local verification command of a single repo (Quick Reference).

## Template — full "## Implementation plan"

This is what goes literally in the PRD Issue body (R1 when creating it, R7 when refining it):

```markdown
## Implementation plan

### Item 1 — <title> — repo: `<org>/<repo>`
- **Description:** ...
- **Acceptance criteria:**
  - [ ] ...
  - [ ] ...
- **Local verification:** `<command>`
- **Dependencies:** None
- **Size:** S

### Item 2 — <title> — repo: `<org>/<repo>`
- **Description:** ...
- **Acceptance criteria:**
  - [ ] ...
- **Local verification:** `<command>`
- **Dependencies:** Item 1
- **Size:** M

<!-- ...more items... -->
```

No flat checklist without a repo or criteria — an item without a target repo is an item R2
can't start implementing without guessing.

## Parallelization (for R2)

- **Safe in parallel:** items in different repos with no dependency between them (e.g. one
  item in `backend-api` and another in `web-frontend` that don't share a contract).
- **Mandatory sequential:** items with explicit "Dependencies", schema migrations, any
  runtime → infrastructure chain (see Step 2).
- **Needs coordination:** two items sharing an API contract across repos (e.g. backend +
  frontend consuming the same endpoint) — the item on the side that DEFINES the contract
  goes first and explicitly as a dependency of the other; don't leave them "in parallel"
  without that relation.

## Rationalizations to reject

| Rationalization | Why it's false here |
|---|---|
| "The PRD title makes it obvious" | R2 doesn't interpret, it executes the literal plan. Without written items, there's nothing to implement. |
| "One giant PR is simpler" | It breaks `PRD → PR = 1:N`, R5 can't gate by parts, and a single Request Changes from the reviewer blocks the WHOLE PRD. |
| "Dependencies can be inferred from list order" | R2 doesn't guarantee execution order between items — without the explicit "Dependencies" field, two items may open in the same run without one waiting for the other. |
| "The target repo can be specified later" | R2 searches `is:pr "dev-loop#<n>"` per repo to check idempotency — without a declared target repo, it doesn't know where to search or where to open the branch. |

## Red flags — the plan is NOT ready for `prd:approved`

- Any item without a target repo or without acceptance criteria.
- Vague acceptance criteria ("works well", "improve performance") instead of a checkable
  condition.
- An L/XL-sized item without a breakdown.
- Implicit dependencies (the list order "hints at" a dependency that isn't written down).
- Items targeting a repo that uses `master` as base branch, or that is excluded from Auto-fix,
  without a note that extra manual validation is required before the PR — always detect the
  base branch.
- The plan doesn't mention the repo's local verification command (it exists in its Quick
  Reference).

If you spot any of these in R1's Phase B or during R7's refinement: don't let it silently
reach `prd:needs-review` — fix it or, if it depends on an owner decision, leave it in
"OPEN QUESTIONS" with the label `prd:blocked`.

## Verification checklist before leaving it in `prd:needs-review`

- [ ] Every item has a valid target repo (from the "Loop target repos" table in CLAUDE.md).
- [ ] Every item has verifiable acceptance criteria (3 bullets or fewer).
- [ ] Every item has its local verification command (repo Quick Reference).
- [ ] Every item has an explicit "Dependencies" field (even if it's "None").
- [ ] No item is L or XL without a breakdown.
- [ ] The item order respects the dependency graph (foundations first).

This does NOT replace the architecture gate by the reviewers configured in CLAUDE.md's Review
roster (or self-review mode) in R5, nor the PRD's aggregate Definition of Done (the label
table `prd:building → prd:arch-review → prd:ready-for-review → prd:done` in
`docs/routines.md`) — it's the "is the plan well built?" criterion, prior to a single PR
existing.

---
Adapted for the dev-loop from Addy Osmani's "planning-and-task-breakdown" skill —
github.com/addyosmani/agent-skills (MIT).
