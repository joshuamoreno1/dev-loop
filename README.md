# dev-loop 🤖

An **autonomous development loop** for tech leads, built on **Claude Code Routines**.
It runs in Anthropic's cloud — laptop off — authenticated via OAuth (the Claude GitHub App,
no tokens to manage).

From your meetings (**Granola** and/or **Google Meet**) and messages (**Slack** `#dev-loop` tag),
requirements are extracted; they are **validated with you** before becoming PRDs; you approve;
they get implemented; a review gate checks plan and architecture; and only what passes every
filter reaches your final review. You stay the owner of every meaningful decision — the loop
does everything in between.

**This repo is a template.** Fork it (keep your fork **private**), open Claude Code inside it,
and say: **_"Read the README and set this loop up for me."_** A guided setup interviews you
(GitHub org, target repos, Slack, reviewers, meeting sources, timezone), fills in the
configuration, and walks you through the few steps only you can do.

The loop is **event-driven**: every owner action fires the corresponding routine instantly via
API (`/fire`), and implementation starts the moment a plan is approved (**native GitHub
trigger** `Issue: Labeled`). **Cron** is no longer the driver: it remains as a **safety net
(reconcile)** that catches anything an event missed. Details in
[`docs/routines.md` → "Trigger model"](./docs/routines.md#trigger-model-event-driven--reconcile).

```mermaid
flowchart TD
    G["🎙️ Granola<br/>meetings"] --> R1A
    M["📹 Google Meet<br/>transcripts/notes (Drive)"] --> R1A
    S["💬 Slack<br/>thread tagged #dev-loop"] --> R4

    R1A["R1 · Triage<br/>cron reconcile · extracts candidates"] --> TRIAGE
    TRIAGE{"👤 OWNER validates in Slack<br/>which ones → PRD? (cuts the noise)"}:::human -->|"/fire · owner action"| R1B
    R1B["R1 · Builder<br/>event (/fire) + reconcile · builds chosen PRDs"] --> ISSUE
    R4["R4 · Slack Intake<br/>event (/fire) + reconcile · #dev-loop tag"] --> ISSUE

    ISSUE["📋 PRD issue in your dev-loop fork<br/>label: prd:needs-review"] --> GATE1
    ISSUE -.->|"refine: / prd:refine · /fire"| R7["R7 · PRD Refiner<br/>event (/fire) + reconcile"]
    R7 -.updates the PRD.-> ISSUE
    GATE1{"👤 OWNER approves PRD<br/>prd:approved"}:::human -->|"/fire · owner action"| R5PLAN

    R5PLAN["R5 · Gate A — PLAN review<br/>reviewers (or self-review) evaluate the plan · prd:plan-review"] --> PLANGATE
    PLANGATE{"PLAN approved?<br/>explicit PLAN APPROVED, no blockers"}:::gate
    PLANGATE -->|no · edit plan, re-request| R5PLAN
    PLANGATE -->|yes| PLANOK["✅ prd:plan-approved"]
    PLANOK -->|"native GitHub trigger · Issue:Labeled"| R2

    R2["R2 · Implementer<br/>native trigger Issue:Labeled prd:plan-approved + reconcile"] --> PR
    PR["🔀 PR in target repo<br/>claude/ branch · Auto-fix ON · prd:arch-review"] --> VIT
    VIT["🏛️ Review gate<br/>architecture review (reviewers or self-review)"] --> R5
    R5["R5 · Gate B — PR review<br/>event (/fire) + reconcile · applies feedback"] --> GATECONV

    GATECONV{"Does the GATE converge?<br/>green CI + comments resolved + APPROVED"}:::gate
    GATECONV -->|no| R5
    GATECONV -->|yes| READY["✅ prd:ready-for-review"]
    READY --> R3

    R3["R3 · PR Notifier<br/>morning cron · digest ONLY of ready-for-review"] --> GATE2
    GATE2{"👤 OWNER reviews and merges<br/>prd:done"}:::human --> DONE["✅ Merged"]

    R0["R0 · PR Reviewer<br/>cron reconcile"] -.reviews/approves.-> PRTEAM["📄 Team PRs<br/>docs + fix/feat/chore/release"]

    PRWEEK["🔀 PRs merged this week"] -.reads business impact.-> R6["R6 · Sprint Review Deck<br/>weekly"]
    R6 --> DECK["📊 HTML deck for stakeholders"]

    classDef human fill:#2d4a22,stroke:#4ea832,color:#e6e8ec,stroke-width:2px;
    classDef gate fill:#3a2e12,stroke:#c99a2e,color:#e6e8ec,stroke-width:2px;
```

> Standalone diagram: [`docs/dev-loop-diagram.md`](./docs/dev-loop-diagram.md).

---

## How knowledge is inherited (important)

When you run Claude Code locally from a root folder, it inherits that folder's global `CLAUDE.md`.
In the cloud that doesn't happen by itself. This repo solves it like this:

- **Global layer** → lives in this repo: [`CLAUDE.md`](./CLAUDE.md) (identity, sacred rules,
  review roster, target repos, lessons) + [`.claude/`](./.claude) (the PR-flow agents and the
  review skills — your review standard). Since **every routine selects `dev-loop`** as one of its
  repos, this context is always cloned, and every routine prompt starts by reading it.
- **Per-repo layer** → each target repo contributes its own `CLAUDE.md` + `.claude/`, which the
  routines load automatically when cloning it. **That decentralized knowledge is never lost.**

Effective context = **global (dev-loop) + per-repo (target)**. Same as running Claude locally from
your workspace root.

---

## State machine and cardinality

Entities: **Recording** (Granola/Meet) · **PRD** (Issue in your dev-loop fork) · **PR** (in target repos).

**Cardinality (key):**
- **Recording ⇄ PRD = N:M** — several meetings can converge into ONE PRD; one meeting can touch several PRDs.
- **PRD → PR = 1:N** — one PRD may need SEVERAL PRs (multi-repo or breakdown). The PRD carries an
  **"## Implementation plan"** (checklist; each item = 1 PR). Each PR references `Part of dev-loop#<n>`.

PRDs are **GitHub Issues**; the label is the **aggregate state** of their PRs. Source of truth for
a PRD's PR set: `is:pr "<owner>/dev-loop#<n>"`. Canonical detail in [`docs/routines.md`](./docs/routines.md).

| PRD label | Meaning (aggregate) | Who sets it |
|-------|-------------|---------------|
| `triage:pending` / `triage:done` | Meeting candidates waiting for / resolved by the owner | R1 |
| `prd:needs-review` | PRD generated, waiting for owner approval | R1 / R4 |
| `prd:refine` | the owner requests a refinement pass (R7 incorporates their feedback) | **the owner** |
| `prd:approved` | the owner approved it → enters **Gate A** (plan review) | **the owner** |
| `prd:plan-review` | The **implementation plan** is under review (before implementing) | R5 (Gate A) |
| `prd:plan-approved` | The plan passed review → ready for R2 to implement | R5 (Gate A) |
| `prd:building` | Plan items still missing PRs, or PRs in progress | R2 |
| `prd:arch-review` | All plan PRs open and under architecture review | R2 / R5 |
| `prd:ready-for-review` | **ALL** PRs passed their gate (green CI + comments resolved + APPROVED). Not monotonic: R5 **downgrades** it to `arch-review` if an unapproved PR reappears | R5 |
| `prd:done` | **ALL** PRs merged | R5 (reconcile) after the **owner** merges |
| `prd:blocked` | OPEN QUESTIONS or an unresolved blocker | R1 / R2 / R5 |
| `prd:discarded` | the owner discarded the PRD — will not be implemented (issue closed) | **the owner** |
| `src:granola` · `src:meet` · `src:slack` | Source(s) of the requirement | the routine that created it |

**Human gates (owner only):** validate the triage · approve each PRD (`needs-review → approved`) ·
merge each PR. In between there are **two review gates**, both orchestrated by R5: **(A)** review of
the **implementation plan** before implementing (`approved → plan-review → plan-approved`) and
**(B)** per-PR **architecture review** (`arch-review → ready-for-review`). Both run in one of two
modes, configured in `CLAUDE.md`:

- **Team-review mode** — R5 posts to your review channel tagging the configured reviewers (humans
  or your own AI agents, by Slack member ID) and waits for an explicit verdict.
- **Self-review mode** (default for a solo TL) — R5 itself runs an adversarial review with fresh
  context, applying the repo's review skills (`review-pr`, `security-and-hardening`,
  `doubt-driven-development`), and records an explicit verdict on the issue/PR.

Either way the rule is the same: **nothing passes by silence — only by explicit positive evidence.**

### Two kinds of issue (important)
- **Triage issue** → temporary: the "menu" of candidates R1 shows you to pick which → PRD.
  It also stores the keys of the NOT-chosen meetings (so they aren't re-proposed). **It is not a PRD.**
- **PRD issue** → **one need = one PRD**. A single issue carries its WHOLE lifecycle. There is NOT
  one issue per meeting; several meetings feed the same PRD issue (N:M).

### Anatomy of a PRD issue
- **Title:** the need. · **Labels:** its current state.
- **Body:** context + requirements + acceptance criteria + `## Implementation plan` (checklist, each item = 1 PR)
  + **sources with their keys** (the N meetings/messages that feed it).
- **Comments:** your feedback (`refine:`), R7's passes, and the PR links.
- **Linked PRs** via `Part of dev-loop#<n>` → progress shows as the plan's ☑ boxes get checked on merge.
- **Close:** when ALL its PRs merge (`prd:done`).

---

## The routines

Each row lists its **primary trigger (event)** and the **reconcile cron**. Cron times are computed
for YOUR timezone during setup; see [`docs/routines.md` → "Trigger model"](./docs/routines.md#trigger-model-event-driven--reconcile).

| # | Routine | Trigger (event · reconcile) | What it does |
|---|---------|--------|----------|
| **R1** | Meetings Triage & PRD Builder | `/fire`: answering a triage (Builder) · cron 3×/day | **Triage (today's meetings only, one triage per day):** reads **Granola + Google Meet**, extracts candidates from TODAY's meetings and asks you in Slack which → PRD (supports grouping). **Builder:** generates PRDs (with a PR plan) ONLY for the chosen ones |
| **R7** | PRD Refiner | `/fire`: requesting a refinement · cron 4×/day | Incorporates your issue feedback (`refine:` or `prd:refine` label) into the PRD before approval. Refinement loop |
| **R2** | Implementer | **native GitHub trigger** `Issue:Labeled prd:plan-approved` · cron 2×/day | When the plan is approved, implements **each plan item** on a `claude/` branch → opens PR(s) + Auto-fix ON → requests review per the configured mode |
| **R5** | Review Orchestrator | `/fire`: approve / merge · cron 6×/day | **Gate A:** runs the **plan** review (`approved → plan-review → plan-approved`). **Gate B:** runs the gate **per PR**; when **all** converge → `prd:ready-for-review`; reconciles `prd:done` when everything merges, and **downgrades** `ready-for-review → arch-review` if an unapproved PR reappears |
| **R3** | PR Notifier | daily morning cron | Slack digest ONLY of `prd:ready-for-review` for your review |
| **R4** | Slack Intake (`#dev-loop` tag) | `/fire`: leaving a tagged request · cron 4×/day | Captures threads tagged `#dev-loop` → creates PRD issues `src:slack` |
| **R0** | PR Reviewer | cron 5×/day (PR Auto-fix reacts via webhook) | Reviews team PRs: docs (flags trivial ones) **and functional** (fix/chore/feat/release): comments or approves. Never merges code |
| **R6** | Sprint Review Deck | weekly cron | Reads the week's merged PRs → HTML demo deck for stakeholders (business impact + metrics) |

All reconcile crons run **Mon–Sat** inside your working window; one rest day with no runs (configurable).
The **full prompts** for each routine are in [`docs/routines.md`](./docs/routines.md).

### Event-driven + reconcile (why this model)
The loop **doesn't wait for cron to react**: every owner action fires its routine instantly via API
(`/fire`), and R2 starts the moment the plan is approved. **Cron** remains as a **safety net**:
it sweeps whatever an event didn't cover, at lower frequency, with a rest day.

| When it acts | How it fires | Routines |
|--------------|-----------------|----------|
| **The instant you act** | **API fire (`/fire`)** (owner action) | approve → **R5** (Gate A) · merge → **R5** (reconcile) · refine → **R7** · answer a triage → **R1** Builder · leave a `#dev-loop` request → **R4** |
| **The instant the plan is approved** | **native GitHub trigger** `Issue:Labeled prd:plan-approved` | **R2** implements |
| **Near real-time on PRs** | Claude GitHub App webhook | **Auto-fix** addresses PR comments |
| **Backup sweep** | **reconcile cron** | R1/R4/R5/R7 (catch missed events) · R0 (reviews PRs) · R3 (digest) · R6 (weekly deck) |

> **Note on the daily run cap:** Routines (research preview) has a daily per-account run limit.
> The event-driven model **reduces** cron spend (sparser crons, one rest day); `/fire` calls only
> run when you actually did something. Check your usage at claude.ai/code/routines.

### How do routines avoid repeating work? (idempotency — there is no memory)
Routines have **no memory** between runs (each run is a fresh VM). The "don't repeat" control
**lives in GitHub**, via a stable per-source key embedded in each issue: the meeting **UUID**
(Granola), the transcript/note **file ID** (Google Meet), the message **permalink/ts** (Slack),
the commit **SHA** (PR reviews). Before acting, the routine searches for that key in the hub;
if it's already there, it skips. The issues/PRs themselves are the ledger. Reinforced by labels
and the PREFLIGHT rule.

### Dedup by key vs. semantic dedup (avoiding duplicate PRDs on the same topic)
There are **two levels** of "don't duplicate":
- **By key (same item):** UUID/fileID/permalink → avoids reprocessing the same meeting/message.
- **By topic (same subject):** before creating a PRD, **R1 and R4 search for related open PRDs**.
  If one already covers the topic (even from **another source** — e.g. you reported it on Slack and
  later a meeting covers the same thing), **they don't create another**: they check for new info,
  **add it to the existing PRD** (linking the new key), and leave it for your review. If unsure,
  they flag it "(duplicate of #X?)".
- **Unification (R7):** each run, R7 looks for overlapping open PRDs and **asks you on Slack
  whether to unify** (`Unify #X and #Y?`). It never merges without your OK.

### R1 in two phases (why)
R1 does **not** send meetings straight to PRD. First it runs a **triage** of TODAY's meetings
(one triage per day): it extracts candidates from **Granola and Google Meet** and shows them to
you in Slack so you pick which deserve a PRD (protocol: `PRD: 1,3,4` · `PRD: [1,3], 4` to **group**
several candidates into one PRD · `all` · `none`). Only then does the **builder** generate the
chosen PRDs (with their PR plan). This kills the noise from chatty meetings.

### Feeding work in from Slack (the `#dev-loop` tag)
To push a bug/support item/requirement into the loop, **reply in the thread with the `#dev-loop`
tag**. When you leave the request, R4 fires instantly via API (`/fire`); otherwise the reconcile
cron picks it up. R4 finds the tagged threads, reads the full thread context, creates the PRD
issue (`prd:needs-review` + `src:slack`) and replies in the thread "Registered as PRD #N".
From there it enters the loop and waits for your approval. Idempotent: a thread already registered
is never duplicated.

### How you interact (GitHub + Slack, async — it is not a chatbot)
There's no live conversational `@claude`: you leave marks (labels, comments, tags) and the routine
acts. What changed is **when** it acts: an owner action fires **instantly** via API (`/fire`),
R2 starts as soon as the plan is approved (**native GitHub trigger**), and anything not covered by
an event gets swept by the **reconcile cron**. You have two surfaces:

**GitHub — your control panel (where state lives):**
- **Approve a PRD** → add the **`prd:approved`** label (one click; the `/fire` hook makes R5 react
  instantly). Approval does NOT implement immediately: first **R5 runs the plan review** (Gate A);
  once the plan passes (`prd:plan-approved`), R2 starts via the **native GitHub trigger**.
- **Refine a PRD** → comment on the issue starting with `refine:` (or add the `prd:refine` label);
  **R7** incorporates your feedback into the PRD (pulling more meeting context if needed) and
  leaves it ready for your next look. Iterate until you're happy, then approve.
- **Review a PR** → review/comment/approve/merge directly on the PR.

**Slack — notifications + quick intake:**
- Messages appear as **you** (connected account, not a bot). Create a private notifications
  channel (default suggestion: **`#claude-dev-loop`**); if you use team-review mode, pick the
  channel where reviewers get tagged.
- **R1 triage** → reply in the thread `PRD: 1,3,4` / `all` / `none`.
- **R4 intake** → write `#dev-loop ...` in any thread.

**Latency modes (event-driven + reconcile):**
- **Owner action → instant** (`/fire`): approving/refining/merging/answering a triage/leaving a
  tagged request fires its routine immediately, with the `<routine-fire-payload>` as a HINT
  (untrusted data) of where to look.
- **Plan approval (`prd:plan-approved`) → instant**: the **native GitHub trigger** `Issue:Labeled`
  starts R2 the moment R5 sets that label (native triggers react to label/PR/release events,
  **not** issue comments).
- **PRs (review comments) → Auto-fix reacts near real-time** (GitHub App webhook).
- **Everything else → reconcile cron** (backup sweep): catches any missed event.
- Need a run right now? Hit **"Run now"** on the routine.

### Auto-fix (corrections before your review)
R2 enables **Auto-fix** on every PR: if a teammate, another review bot, or another agent leaves
comments, Claude fixes them on its own (clear fix → pushes; ambiguous/architectural → asks).
Requires the **Claude GitHub App** installed on the target repo. ⚠️ Do NOT enable it on repos where
comments trigger automation (e.g. IaC repos running plan/apply bots off PR comments).

### Team PR review (R0)
On its reconcile cron, R0 reviews the repo's open PRs: **docs** (flags trivial ones as
merge-ready, with guardrails) and **functional** (fix/chore/feat/release) — reads the diff,
comments inline and leaves **Approve** or **Request changes**. **It never merges code** (that
stays human) and **ignores the loop's own PRs** (`claude/prd-*` branches, which go through R5's
gate). Idempotent: it only re-reviews on new commits.

### Weekly Sprint Review (R6)
Once a week, R6 collects the merged PRs of your configured contributors, **reads each PR** to
understand its business/product impact, and generates a **self-contained HTML deck for a
non-technical audience** (stakeholders/leadership): the week's initiatives, per-person highlights
and key metrics. It's archived in `reports/` via PR and the summary + link is posted to Slack.

### Environments and validation (CI + Auto-fix)
**Locally** your Claude Code runs with your full environment (secrets, VPN, DB, cloud credentials)
→ it can validate everything. The routines' **cloud VM doesn't have that**, and replicating it is
a bad idea (no dedicated secrets store, no interactive SSO auth). So validation is **2-level**:
the routine runs only cheap, secret-free checks (lint, typecheck, build, unit tests + local
Postgres/Redis preinstalled on the VM) **before** the PR; **GitHub CI** (your runners with
secrets/access) is the **source of truth after**; and **Auto-fix** closes the loop by fixing CI
failures. Routines stay short and never need your secrets. Details in
[`docs/routines.md`](./docs/routines.md#environments-and-validation).

### Cross-cutting rule — the owner's action always wins
Every routine runs a **PREFLIGHT** before acting: it re-reads current state and applies
*compare-and-set*. If the owner got there first (merged, moved the label, implemented it
themselves), the routine detects it and steps aside. Idempotent. See the `PREFLIGHT` block in
[`docs/routines.md`](./docs/routines.md).

---

## 🚀 Setting up the loop (fork)

> **The short way:** fork this repo (keep it **private**), open **Claude Code** inside it and say:
> **_"Read the README and set this loop up for me."_**
> Claude runs the guided setup (the `setup-dev-loop` skill): it interviews you, executes everything
> automatable (🤖) and asks you, one by one, only for the steps that require your identity,
> secrets or external consoles (🧑).

The setup splits into what **you do** and what **Claude does for you**.

### 🧑 Only you (Claude can't — identity, secrets, external access)
1. **Fork** the repo (or use it as a template). Keep it **private** (it will contain your team
   roster, channels and repo map).
2. **Authenticate GitHub** with the scopes the scripts need:
   ```bash
   gh auth login                 # repo scope
   gh auth refresh -s project    # needed for the board (Projects v2)
   ```
3. **Connect the connectors** in claude.ai that the routines will read: **Slack**, and
   optionally **Granola** and/or **Google Drive/Meet/Calendar**. Without meeting connectors,
   R1 is skipped and intake happens via Slack (R4) and manual issues — the loop still works.
4. **Install the [Claude GitHub App](https://github.com/apps/claude)** on your org/user and
   **grant it access to the target repos** (clone + Auto-fix). ⚠️ If ANY repo in a routine's
   `sources` lacks access, the whole run fails at "Cloned repository".
5. **Create the Slack channel** for loop notifications (private), and note its ID.
6. **Board secret** (if you use the Project v2 board): create a **fine-grained PAT** with
   *Projects: Read and write* and add it as the repo secret `DEVLOOP_PROJECT_TOKEN`. The Actions
   `GITHUB_TOKEN` can't write org Projects v2, hence the PAT.
7. **Configure the native GitHub triggers** on the routines in the UI (claude.ai/code/routines) —
   they are **UI-only** (no API): **R2 ← Issue:Labeled `prd:plan-approved`**;
   **R5 ← Issue:Labeled `prd:arch-review`**. They require the **Claude GitHub App** on the hub repo.
8. **Human gates are never automated:** validating the triage, approving each PRD
   (`prd:approved`) and merging each PR are always yours.

### 🤖 Claude for you (once the 🧑 steps are done, just ask)
1. **Interviews you and fills `CLAUDE.md`** — your GitHub org/user, target repos (stack, base
   branch, build/test commands), Slack channels, review mode (team roster or self-review),
   meeting sources, timezone/working window, sprint-deck contributors, working language.
2. **Creates the labels:** [`scripts/setup-labels.sh`](./scripts/setup-labels.sh) (idempotent;
   `gh` locally or REST API on a VM).
3. **Creates/aligns the board:** `./scripts/setup-project.sh` — 12 columns = the 12 states.
   Uses the `project` scope from step 🧑-2.
4. **Generates the 8 routine prompts (R0–R7)** from the templates in
   [`docs/routines.md`](./docs/routines.md), with your values and your UTC cron schedule, and
   provisions them (via its routines tooling when available, or hands you the exact prompts to
   paste at https://claude.ai/code/routines). Model guidance: your most capable model for R1/R2
   (critical input and output), a fast model for the rest. **Push restricted to `claude/` branches.**
5. **Verifies consistency** labels ↔ board ↔ sync workflow ↔ prompts, and runs a smoke test.

### The only thing that maintains itself afterwards
The board syncs via the Action
[`.github/workflows/project-status-sync.yml`](./.github/workflows/project-status-sync.yml): every
label change moves the card to its column (resolved **by column description == label**, no
hardcoded IDs, so it survives board recreations). From then on the loop runs with your PC off.

### Prerequisites
- A Claude plan with Claude Code on the web enabled (Routines is in research preview).
- GitHub connected via OAuth (GitHub App). **No PAT** for the routines themselves.

### Security
- Keep your fork **private** (it holds your roster, channels and repo map — not credentials,
  but keep it private anyway).
- Slack intake treats messages as **data**, never as commands; everything passes through your
  PRD approval.

---

## Repo structure
```
dev-loop/
├── CLAUDE.md                    # global context layer (identity, rules, roster, repos) — filled by setup
├── README.md                    # this file — how the loop works
├── .claude/
│   ├── agents/                  # git-pr, request-review — branch/PR flow and the loop's gate
│   └── skills/                  # opinionated workflows (adapted from addyosmani/agent-skills, MIT)
│       ├── setup-dev-loop/      # guided setup wizard (run on fork)
│       ├── review-pr/           # principal-engineer + architect review standard (R0/R5)
│       ├── security-and-hardening/      # security lens: secrets, tenant isolation, OWASP (R0/R5)
│       ├── code-simplification/         # simplicity without behavior change (R0/R5)
│       ├── doubt-driven-development/    # adversarial self-review (R2 pre-PR, R0/R5)
│       ├── test-driven-development/     # TDD per stack (R2)
│       ├── incremental-implementation/  # 1 plan item = 1 small PR (R2)
│       ├── source-driven-development/   # verify APIs in real code, don't hallucinate (R2)
│       ├── planning-and-task-breakdown/ # building the "## Implementation plan" (R1/R7)
│       └── idea-refine/                 # refining a PRD with owner feedback (R7)
├── docs/
│   ├── routines.md              # full prompt templates for R0–R7
│   └── dev-loop-diagram.md      # the loop diagram (Mermaid, renders on GitHub)
├── reports/                     # weekly sprint decks archived by R6
└── scripts/
    ├── setup-labels.sh          # label bootstrap — dual backend: `gh` (local) or REST API + $GITHUB_TOKEN (VM/web)
    ├── setup-project.sh         # ensures the GitHub Project's Status columns — `gh` + GraphQL, runs locally
    └── dl.sh                    # query/mutation CLI for PRDs and triages (REST API + $GITHUB_TOKEN)
```

### `scripts/setup-labels.sh` — label bootstrap (local or VM)
Creates/updates the state-machine labels idempotently. **Auto-detects the backend**: uses `gh`
if installed (local setup), or the **REST API with `curl` + `$GITHUB_TOKEN`** when it isn't — the
case on routine VMs and **Claude Code web/app**, where `gh` doesn't exist. A single label list
(source of truth) feeds both paths.

```bash
./scripts/setup-labels.sh                                   # repo auto-detected from git remote
REPO=<owner>/dev-loop ./scripts/setup-labels.sh             # explicit
LABELS_BACKEND=api GITHUB_TOKEN=ghp_xxx ./scripts/setup-labels.sh   # force API (VM/web)
DRY_RUN=1 ./scripts/setup-labels.sh                         # show without executing
```

### `scripts/setup-project.sh` — board columns (Project v2)
A GitHub Project v2's columns are the options of the single-select **Status** field. This script
aligns them with the state machine (12 columns: Triage → Needs review → … → Discarded),
auto-discovering or creating the board. **Runs locally only** (or wherever `gh` is authenticated
with the `project` scope): Projects v2 has no REST API and its GraphQL is gated on routine VMs.

```bash
DRY_RUN=1 PROJECT_OWNER=<owner> ./scripts/setup-project.sh   # preview columns
PROJECT_OWNER=<owner> ./scripts/setup-project.sh             # additive (preserves existing)
PROJECT_OWNER=<owner> PROJECT_NUMBER=7 ./scripts/setup-project.sh    # specific board
PROJECT_OWNER=<owner> PROJECT_REPLACE=1 ./scripts/setup-project.sh   # leave EXACTLY the 12
```

### `scripts/dl.sh` — the loop's CLI (no `gh`)
Recurring operations on PRD issues and triages, so you don't rebuild label/state logic on every
query. Uses the **GitHub REST API with `curl` + `jq` + `$GITHUB_TOKEN`** (works on routine VMs,
which don't have `gh`). All mutations respect **PREFLIGHT** (compare-and-set) and support `DRY_RUN=1`.

```bash
scripts/dl.sh status                    # panel of everything waiting on the owner (triage + PRDs)
scripts/dl.sh triage                    # open triages (triage:pending)
scripts/dl.sh prds [state]              # PRDs by state, or all ordered by lifecycle
scripts/dl.sh show <n>                  # issue detail (labels, state, body)
scripts/dl.sh prd-prs <n>               # PRs linked to a PRD (cross-refs "dev-loop#<n>")
scripts/dl.sh resolve-triage <n> "PRD: 1,3" ["note"]   # comment + triage:done + close
scripts/dl.sh prd-label <n> prd:approved ["note"]      # compare-and-set of the state label
scripts/dl.sh approve <n> ["note"]      # shortcut: prd-label <n> prd:approved
scripts/dl.sh comment <n> "text"        # comment on an issue
DRY_RUN=1 scripts/dl.sh prd-label 14 prd:refine        # print the call without executing
```

---

## License

MIT — see [LICENSE](./LICENSE). The skills under `.claude/skills/` are adapted from
[addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) (MIT).
