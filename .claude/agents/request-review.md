---
name: request-review
description: "Get a PR ready for the dev-loop gate: green CI + resolved comments, then request the architecture review from the reviewers configured in CLAUDE.md's Review roster (or run self-review mode). Gate follow-up is R5's job."
model: opus
---

# Request Review (dev-loop)

## Flow

### 1. Verify the PR is actually ready
```bash
gh pr checks <N> --repo <owner/repo>
gh pr view <N> --repo <owner/repo> --json state,reviews,comments,mergeable
```
- Green CI is mandatory. Checks running → wait and re-check.
- Failing checks → read the logs, fix, push to the PR's `claude/` branch, repeat until green.
- Pending comments (humans or bots) → address them, push, re-verify.
- Ready = green CI + resolved comments + no conflicts.

### 2. Request the architecture review
Two modes, configured in CLAUDE.md:

- **Team-review mode:** post in the review channel configured in CLAUDE.md, tagging the
  reviewers from CLAUDE.md's Review roster by their Slack member ID (`<@MEMBER_ID>`, never
  plain-text `@name` — plain text doesn't notify): clickable link to the PR (`<url|repo#N>`)
  + summary of the change + PRD context (issue as a link). Reviewer response protocol:
  `APPROVED` | `BLOCKER:`/`CHANGE:`/`SUGGESTION:` items.
- **Self-review mode:** the routine performs the adversarial review itself, applying the
  `review-pr` standard, and records the verdict (`APPROVED` or the `BLOCKER:`/`CHANGE:`/
  `SUGGESTION:` items) as a comment on the PR.

### 3. Report
Leave a record in the loop's notification channel configured in CLAUDE.md: PR as a link +
status (green CI, review requested).

## Rules
- NEVER request review with red CI or unaddressed comments.
- Gate follow-up (reading the reviewer's response, applying feedback, promoting labels) is
  **R5**'s job — this agent only gets the PR ready and the review requested; don't duplicate
  that work.
- GitHub references in Slack ALWAYS as clickable links.
