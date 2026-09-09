---
name: setup-dev-loop
description: Guided setup wizard for the dev-loop. Use when the owner asks to "set this loop up", "set up the dev-loop", "bootstrap from scratch", "read the README and set this up for me", or any equivalent after forking/cloning this repo. Interviews the owner, fills CLAUDE.md, creates labels and the Project board, computes the UTC cron schedule, generates the 8 routine prompts, and walks the owner through the steps only they can do (connectors, GitHub App, native triggers, secrets).
---

# setup-dev-loop — guided bootstrap wizard

You are setting up the autonomous dev-loop for a new owner who just forked/cloned this repo.
Your job: **interview → configure → provision → verify**, doing everything automatable yourself
and asking the owner, one at a time, only for the steps that need their identity, secrets or
external consoles. Read `README.md` and `docs/routines.md` first — they are the spec.

**Golden rules of this wizard:**
- **Never invent values.** Every roster/channel/repo/timezone value comes from the owner's answers.
- **One topic at a time.** Don't dump a 20-question form; interview in the phases below, confirm
  each phase back to the owner before moving on.
- **Everything you change goes through a branch + PR** (`claude/setup`), per the sacred rules —
  even in the owner's fresh fork. Exception: if the owner explicitly tells you to commit the
  initial setup directly, respect their call in their own fork.
- **Idempotent and resumable.** If CLAUDE.md is already partially filled, keep valid values,
  confirm them, and only ask what's missing. It must be safe to re-run this wizard.
- **Detect, don't assume.** Check `gh auth status`, existing labels, existing board, existing
  generated files before creating anything.

## Phase 0 — Preflight (automated checks)

Run and report:
1. `gh auth status` — must be logged in. Token scopes must include `repo`; for the board also
   `project` (if missing: ask the owner to run `gh auth refresh -s project` themselves — it's
   interactive).
2. `git remote get-url origin` — confirm this is the **owner's fork**, not the upstream template.
   Derive `{{HUB}}` (owner/repo slug) and `{{OWNER_GITHUB}}` from it; confirm with the owner.
3. `jq --version`, `curl --version` — needed by the scripts.
4. Check whether `CLAUDE.md` still has `<!-- SETUP -->` placeholders (fresh fork) or is already
   filled (re-run).

## Phase 1 — Interview

Ask in this order, one block at a time. Offer sensible defaults; record answers.

**1. GitHub**
- Org or user account holding the target repos (`{{ORG}}`).
- Target repos: for each — name, stack, one-line purpose, base branch (offer to detect via
  `gh repo view <repo> --json defaultBranchRef`), build/test commands, and whether PR comments
  trigger automation there (IaC plan/apply bots → flag as **no Auto-fix**).
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
- Working window (default 06:00–22:00) and workdays (default Mon–Sat, one rest day).

**5. Sprint deck (R6)**
- Contributor GitHub handles for the weekly deck. Empty → skip R6.
- Which day/time the deck should land (default Friday 09:00 local).

**6. Working language**
- Language for Slack messages, PRDs and commit messages (default English). Docs of the repo stay
  in English.

Confirm the full summary back to the owner before Phase 2.

## Phase 2 — Configure (automated)

1. **Fill `CLAUDE.md`:** replace every `<!-- SETUP:* -->` section with the interview values
   (LANGUAGE, REPOS table incl. no-Auto-fix flags, REVIEW mode + roster, SLACK channels, TEAM,
   SCHEDULE). Keep the surrounding structure intact.
2. **Compute the UTC crons** from timezone + window + workdays, keeping each routine's cadence
   from the table in `docs/routines.md` (R1 3×/day, R2 2×/day, R4 4×/day, R5 6×/day, R7 4×/day,
   R0 5×/day, R3 1× morning, R6 weekly). Use "odd" minutes (not :00). ⚠️ If the window crosses
   UTC midnight, the `dow` field can't express the rest day exactly for the late-evening hours —
   apply the compromise documented in `docs/routines.md` ("Known limitation") and tell the owner.
3. **Generate `docs/routines.generated.md`:** copy each prompt template from `docs/routines.md`
   with every `{{PLACEHOLDER}}` resolved — including splicing the §0 preamble into each prompt
   where it says `[§0 preamble here]`, and the right `{{REVIEW_MODE_BLOCK}}` for the chosen mode.
   Drop routines the owner opted out of (R1 without meeting sources, R6 without contributors).
   Each entry must be copy-paste-ready: name, model guidance, repos to select, connectors,
   cron expression, allowed-tools notes (R6 → `Artifact`), and the full prompt in one block.
4. **Labels:** run `REPO={{HUB}} ./scripts/setup-labels.sh` (use `DRY_RUN=1` first, show the
   owner, then apply).
5. **Board** (if opted in): run `PROJECT_OWNER=<owner> PROJECT_OWNER_TYPE=<organization|user>
   ./scripts/setup-project.sh` (DRY_RUN first). Then remind the owner of the `DEVLOOP_PROJECT_TOKEN` secret and set the repo variable
   `DEVLOOP_PROJECT_NUMBER` (`gh variable set`) for the sync workflow.
6. **Commit** everything on `claude/setup` and open the PR. Never push to main.

## Phase 3 — Owner-only steps (walk through one by one)

Present these as a checklist and wait for confirmation on each before ticking it off:

1. **Connect connectors** at claude.ai: Slack, plus Granola / Google Drive / Google Calendar as
   chosen. Without them the routines can't read meetings or post to Slack.
2. **Install the Claude GitHub App** (github.com/apps/claude) on the org/user and grant it access
   to the hub + ALL target repos. ⚠️ One missing repo in a routine's sources fails the whole run
   at "Cloned repository".
3. **Create the routines** at https://claude.ai/code/routines: for each entry in
   `docs/routines.generated.md`, create the routine, paste the prompt, set the cron, select
   `dev-loop` + its target repos as sources, pick the model, restrict pushes to `claude/`
   branches, and enable Auto-fix where the CLAUDE.md table says so. (If you have tooling to
   create routines programmatically, offer to do it; otherwise guide the paste.)
4. **Native GitHub triggers** (UI-only, no API): on R2 add `Issue: Labeled` on the hub with
   filter `Labels is one of prd:plan-approved`; on R5 the same with `prd:arch-review`.
5. **`DEVLOOP_PROJECT_TOKEN` secret** (board only): fine-grained PAT with *Projects: Read and
   write* → repo secret.
6. **Merge the setup PR.**

## Phase 4 — Verify (automated smoke test)

1. Labels: `gh label list` shows the 16 loop labels.
2. Board (if used): columns match the 12 states; create a scratch issue, add `prd:needs-review`,
   confirm the sync workflow moves the card, then close and remove it.
3. Consistency: every channel ID/reviewer ID/repo in `CLAUDE.md` appears correctly in
   `docs/routines.generated.md`; no `{{PLACEHOLDER}}` or `<!-- SETUP` markers remain anywhere.
4. Ask the owner to run one routine manually ("Run now" on R4 or R3) and confirm the Slack
   message arrives in the notifications channel.
5. Hand over: summarize what's live, the daily interaction model (approve = label, refine =
   `refine:` comment, intake = `#dev-loop` tag, merge = theirs), and where to watch usage
   (claude.ai/code/routines).
