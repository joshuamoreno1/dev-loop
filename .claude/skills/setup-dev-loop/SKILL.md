---
name: setup-dev-loop
description: Guided setup wizard for the dev-loop. Use when the owner asks to "set this loop up", "set up the dev-loop", "bootstrap from scratch", "read the README and set this up for me", or any equivalent after creating their copy of this template (or cloning it). Interviews the owner, fills CLAUDE.md, creates labels and the Project board, computes the UTC cron schedule, generates the 8 routine prompts, and walks the owner through the steps only they can do (connectors, GitHub App, native triggers, secrets).
---

# setup-dev-loop — guided bootstrap wizard

You are setting up the autonomous dev-loop for a new owner who just created their private copy
of this template (via "Use this template") or cloned it.
Your job: **interview → configure → provision → verify**, doing everything automatable yourself
and asking the owner, one at a time, only for the steps that need their identity, secrets or
external consoles. Read `README.md` and `docs/routines.md` first — they are the spec.

**Golden rules of this wizard:**
- **Never invent values.** Every roster/channel/repo/timezone value comes from the owner's answers.
- **One topic at a time.** Don't dump a 20-question form; interview in the phases below, confirm
  each phase back to the owner before moving on.
- **Everything you change goes through a branch + PR** (`claude/setup`), per the sacred rules —
  even in the owner's fresh copy. Exception: if the owner explicitly tells you to commit the
  initial setup directly, respect their call in their own repo.
- **Idempotent and resumable.** If CLAUDE.md is already partially filled, keep valid values,
  confirm them, and only ask what's missing. It must be safe to re-run this wizard.
- **Detect, don't assume.** Check `gh auth status`, existing labels, existing board, existing
  generated files before creating anything.

## Phase 0 — Preflight (automated checks)

Run and report:
1. `gh auth status` — must be logged in. Token scopes must include `repo`; for the board also
   `project` (if missing: ask the owner to run `gh auth refresh -s project` themselves — it's
   interactive).
2. `git remote get-url origin` — confirm this is the **owner's own private copy**, not the
   upstream template. Derive `{{HUB}}` (owner/repo slug) and `{{OWNER_GITHUB}}` from it; confirm
   with the owner. **If origin still points at the upstream template** (plain clone): stop and
   fix it first — create their private repo (`gh repo create <owner>/dev-loop --private`),
   re-point origin (`git remote set-url origin <new-url>`; keep the template as `upstream`),
   and push. Never run the setup scripts against the upstream slug.
3. `jq --version`, `curl --version` — needed by the scripts.
4. Check whether `CLAUDE.md` still has `<!-- SETUP -->` placeholders (fresh copy) or is already
   filled (re-run).

## Phase 1 — Interview

Ask in this order, one block at a time. Offer sensible defaults; record answers.

**1. GitHub**
- Org or user account holding the target repos, and whether it's an organization or a personal
  account (builds `{{ORG_QUALIFIER}}`: `org:<name>` or `user:<name>`).
- Target repos: for each — name, stack, one-line purpose, base branch (offer to detect via
  `gh repo view <repo> --json defaultBranchRef`), build/test commands, and whether PR comments
  trigger automation there (IaC plan/apply bots → flag as **no Auto-fix**).
- **CI/CD audit per target repo (do this yourself, don't just ask):** list its workflows
  (`gh api repos/<owner>/<repo>/actions/workflows` or read `.github/workflows/`) and check what
  actually runs on PRs — lint, typecheck, tests, build, security scanning, deploy. Then be
  straight with the owner: **the loop's PR quality is capped by each repo's CI** — the agent
  gates are probabilistic judgment; the pipeline is the only deterministic review the generated
  code gets, and it's what Auto-fix converges against. For every repo with thin or no CI, warn
  explicitly and recommend fixing the pipeline BEFORE (or alongside) pointing the loop at it —
  even offer to make "add CI to <repo>" one of the loop's first PRDs. Record the per-repo CI
  status in the CLAUDE.md repos table.
- Use the Project v2 board? (yes/no). If yes: org-level or user-level board.

**2. Slack**
- Notifications channel: name + channel ID (the owner must create it — private — and paste the
  ID; explain: channel details → copy ID, or from the channel URL).
- Intake tag (default `#dev-loop`).
- Review mode: **self-review** (solo TL, default) or **team-review**. If team-review: review
  channel (name + ID) and the roster — per stack, reviewer name + **Slack member ID**
  (`UXXXXXXXX`); explain how to copy a member ID from a Slack profile. Reviewers can be humans
  or the owner's own AI agents — anything with a Slack account that can reply.

**3. Meeting sources**
- Granola? Google Meet (Drive transcripts)? Google Calendar (context)? None?
- If none → R1 is skipped entirely (intake = Slack tag + manual issues); say so explicitly.

**4. Schedule**
- IANA timezone (e.g. `America/Bogota`).
- Working window (default 06:00–22:00) and working days (default Mon–Sat; no runs on
  non-working days).

**5. Sprint deck (R6)**
- Contributor GitHub handles for the weekly deck. Empty → skip R6.
- Which day/time the deck should land (default Friday 09:00 local).

**6. Working language**
- Language for Slack messages, PRDs and commit messages (default English). Docs of the repo stay
  in English.

Confirm the full summary back to the owner before Phase 2.

## Phase 2 — Configure (automated)

1. **Fill `CLAUDE.md`:** replace every `<!-- SETUP:* -->` section with the interview values
   (LANGUAGE, REPOS table incl. no-Auto-fix flags and per-repo CI status, REVIEW mode + roster,
   SLACK channels, SOURCES, TEAM, SCHEDULE). Keep the surrounding structure intact.
2. **Compute the UTC crons** from timezone + window + working days, keeping each routine's
   cadence from the table in `docs/routines.md` (R1 3×/day, R2 2×/day, R4 4×/day, R5 6×/day,
   R7 4×/day, R0 5×/day, R3 1× morning, R6 weekly). Use "odd" minutes (not :00). ⚠️ If the window
   crosses UTC midnight, the `dow` field can't express the non-working days exactly for the
   late-evening hours — apply the compromise documented in `docs/routines.md` ("Known
   limitation") and tell the owner. ⚠️ If the timezone observes DST, warn the owner that fixed
   UTC crons drift ±1h across the year (see the DST note in `docs/routines.md`).
3. **Generate `docs/routines.generated.md`:** copy each prompt template from `docs/routines.md`
   with every `{{PLACEHOLDER}}` resolved — including `{{ORG_QUALIFIER}}` (`org:X` for an org,
   `user:X` for a personal account, from interview 1), splicing the §0 preamble into each prompt
   where it says `[§0 preamble here]`, and the right `{{REVIEW_MODE_BLOCK}}` standalone after the
   preamble in R5 and R2 (in self-review mode R2 gets the one-liner variant — see "Gates" in
   `docs/routines.md`). Drop routines the owner opted out of (R1 without meeting sources, R6
   without contributors). Open each routine's entry with a **config table** (Name · Model ·
   Cron (UTC) · Repos to select · Connectors · Allowed tools (R6 → `Artifact`) · Push restriction
   `claude/` · Auto-fix on/off) followed by the full prompt in one copy-paste block.
4. **Labels:** run `REPO={{HUB}} ./scripts/setup-labels.sh` (use `DRY_RUN=1` first, show the
   owner, then apply).
5. **Board** (if opted in): run `PROJECT_OWNER=<owner> PROJECT_OWNER_TYPE=<organization|user>
   ./scripts/setup-project.sh` (DRY_RUN first). Then remind the owner of the `DEVLOOP_PROJECT_TOKEN` secret and set the repo variable
   `DEVLOOP_PROJECT_NUMBER` (`gh variable set`) for the sync workflow.
6. **Commit** everything on `claude/setup` and open the PR. Never push to main.

## Phase 3 — Owner-only steps (walk through one by one)

Present these as a checklist and wait for confirmation on each before ticking it off:

1. **Merge the setup PR first.** The routines clone the default branch: if they get created
   before the merge, their first runs read the unfilled template CLAUDE.md.
2. **Connect connectors** at claude.ai: Slack, plus Granola / Google Drive / Google Calendar as
   chosen. Without them the routines can't read meetings or post to Slack.
3. **Install the Claude GitHub App** (github.com/apps/claude) on the org/user and grant it access
   to the hub + ALL target repos. ⚠️ One missing repo in a routine's sources fails the whole run
   at "Cloned repository".
4. **Create the routines** at https://claude.ai/code/routines: for each entry in
   `docs/routines.generated.md`, create the routine using its config table (prompt, cron, repos,
   model, connectors, `claude/` push restriction, Auto-fix flag). (If you have tooling to create
   routines programmatically, offer to do it; otherwise guide the paste.)
5. **Native GitHub triggers** (UI-only, no API): on R2 add `Issue: Labeled` on the hub with
   filter `Labels is one of prd:plan-approved`; on R5 the same with `prd:arch-review`.
6. **Wire `/fire` (optional but recommended):** enable the "Call via API" trigger on R1/R4/R5/R7,
   copy each fire endpoint, and add `FIRE_URL_R5`/`FIRE_URL_R7` as repo secrets so
   `.github/workflows/fire-routines.yml` fires them on label/comment actions (check its header —
   if the "Call via API" panel shows a different curl shape, mirror it there). Skipping this is
   fine: the loop runs at cron latency.
7. **`DEVLOOP_PROJECT_TOKEN` secret + `DEVLOOP_PROJECT_NUMBER` variable** (board only):
   fine-grained PAT with *Projects: Read and write* → repo secret; board number → repo variable.

## Phase 4 — Verify (automated smoke test)

1. Labels: `gh label list` shows the 16 loop labels.
2. Board (if used): columns match the 12 states; create a scratch issue, add `prd:needs-review`,
   confirm the sync workflow moves the card, then close and remove it.
3. Consistency: every channel ID/reviewer ID/repo in `CLAUDE.md` appears correctly in
   `docs/routines.generated.md`; no `{{PLACEHOLDER}}` or `<!-- SETUP` markers remain anywhere.
4. Ask the owner to "Run now" each created routine once, starting with R3/R4 (cheap, Slack-only),
   and confirm the Slack message arrives in the notifications channel; a routine that fails at
   "Cloned repository" means the GitHub App is missing access to one of its source repos.
5. If `/fire` was wired: add the `prd:refine` label to the scratch issue and confirm the
   fire-routines workflow run fires R7 (Actions tab → green run).
6. Hand over: summarize what's live, the daily interaction model (approve = label, refine =
   `refine:` comment, intake = `#dev-loop` tag, merge = theirs), where to watch usage
   (claude.ai/code/routines) — and repeat the CI warning list from the interview: which target
   repos have thin pipelines and what that means for the PRs the loop opens there.
