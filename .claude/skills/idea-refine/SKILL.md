---
name: idea-refine
description: Refines a PRD (an Issue in dev-loop) by incorporating the feedback the owner left on the issue, via divergent thinking (exploring options/trade-offs anchored in that feedback) and convergent thinking (converging on a concrete proposal). Use it in R7 · PRD Refiner when a PRD has the prd:refine label or a new comment starting with "refine:" posted after your last marker. It is async — it doesn't assume a live dialogue, it works on feedback already written; any real ambiguity goes to OPEN QUESTIONS, requirements are never invented.
---

# idea-refine — PRD refinement (divergent → convergent)

Adapts the divergent/convergent ideation discipline of the original idea-refine to the
refinement of an **already existing** PRD (an Issue in dev-loop), incorporating the real
feedback the owner left on the issue. It's not an ideation session from scratch: it starts
from a concrete PRD + real comments, not from a vague concept.

## When to use it

- **R7 · PRD Refiner**: a PRD enters refinement if it has the `prd:refine` label or an owner
  comment starting with `refine:` posted after your last `🔧 Refined` marker.
- Ad hoc: when someone asks you to "refine this PRD" and there is already written feedback
  on the issue.

Out of this skill's scope: detecting PRDs that should be unified (that's R7's dedup logic,
not the divergent/convergent transformation of ONE PRD) and approving the PRD (always the
owner's call).

## Key difference vs. the original idea-refine: there is no turn-by-turn dialogue

The original resolves ambiguity **by asking** (`AskUserQuestion`, 3-5 questions before
continuing). That doesn't exist here: the owner's feedback is already written — in issue
comments, or in the originating meeting — and R7's next run may be hours later. What the
original resolves with a question is resolved here like this:

1. Read the **entire** issue thread (accumulated context, not just the last comment).
2. If context is missing, fetch the transcript/note of the originating meeting via the PRD's
   source KEY (the meeting-recording UUID or document file ID — it's in the PRD's sources
   section).
3. If something is still ambiguous after that → `OPEN QUESTIONS` section. Never fill it in
   with a reasonable assumption disguised as a decision.

## Process (same 3-phase discipline, applied to a PRD)

### Phase 1 — Understand and Expand (divergent)

1. **Reconstitute the problem.** Re-read the PRD's current "Context and problem" + ALL new
   feedback (posted after your last `🔧 Refined` marker). If the feedback reframes or
   contradicts the original problem, rewrite the statement — it's still the same underlying
   question: what problem does this solve and for whom?
2. **Detect open decision points** in the feedback — the async equivalent of the original's
   "sharpening questions". They are not asked: they are written down. E.g.: the owner writes
   "make it configurable" but doesn't say by whom, at what granularity, or in which layer.
3. **For each decision point, generate 2-4 concrete options** (not the original's 5-8 generic
   variations — here they are real ways to FULFILL what the owner already asked for, not new
   features). Anchor each option in:
   - the literal text of the feedback (what they said, not what you assume they meant),
   - the `CLAUDE.md` and architecture of the PRD's target repo (Clean Architecture /
     Hexagonal / frontend conventions depending on the stack — don't propose something that
     already violates a repo convention),
   - the transcript of the originating meeting if it adds nuance,
   - useful lenses from the original when they apply: invert the approach, remove an assumed
     constraint, the simplest version that still fulfills it, whether it also serves another
     repo/team.

   Guardrail: options explore **how** to implement what was asked, they never add scope the
   owner didn't mention. Exploring ≠ inventing requirements.

### Phase 2 — Evaluate and Converge

1. Discard the options that don't fit the target repo's `CLAUDE.md` or the sacred rules
   (architecture, security, GitOps conventions, etc.).
2. From the remaining ones, **converge on ONE** per decision point — the one that best meets:
   real value (solves exactly what the owner asked for), feasibility (doesn't inflate the
   "Implementation plan" more than necessary) and consistency with the rest of the already
   written PRD.
3. **If two options are equally defensible** and the only way to choose is a preference the
   owner didn't express → don't guess, don't flip a coin. That's an `OPEN QUESTION`, specific
   and actionable (not a generic "how should this be?").
4. **Be honest, not a yes-machine.** If the feedback introduces unjustified complexity, or
   contradicts a previous PRD decision without saying so explicitly, point it out in the
   refinement comment — don't apply it silently and don't ignore it.

### Phase 3 — Sharpen and Update the PRD

Unlike the original (which produces a new markdown file in `docs/ideas/`), here the artifact
ALREADY exists: the PRD is the issue. Apply the changes directly to its body:

- Update "Context and problem" if it changed in Phase 1.
- Update "Functional/non-functional requirements" and "Acceptance criteria" with what was
  converged on in Phase 2.
- Update "## Implementation plan" if the scope of any item changed, or add items if the
  feedback explicitly demands it. Never delete plan items unless the feedback asks for it.
- If the feedback explicitly leaves something out of scope, say so in the PRD (one line in
  Requirements or in the Plan) — it's the equivalent of the original's "Not Doing": making
  explicit what was decided NOT to do prevents someone from re-proposing it later.
- Preserve ALL existing sources/keys (meeting-recording UUID, document file ID, message
  permalinks) — never delete them, they are the basis of the N:M recording↔PRD dedup.
- Everything still ambiguous after Phases 1-2 goes to "## OPEN QUESTIONS" (create it if it
  doesn't exist): the specific question + why it matters, not a generic list.
- Comment on the issue: `🔧 Refined: <what changed, what was NOT applied and why, what went
  to OPEN QUESTIONS> — marker up to <id/last processed comment>`. That comment is your
  idempotency key — the next run only processes what came after this marker.
- Remove the `prd:refine` label if it was set. Leave the PRD in `prd:needs-review`.

## Guardrails (don't skip them)

- **Never invent requirements** the owner didn't ask for, neither in the PRD body nor in the
  implementation plan. Exploring options (Phase 1) is not adding scope.
- **Never delete sources/keys** of meetings or messages — traceability and dedup depend on them.
- **Never approve the PRD yourself** — `prd:approved` is exclusively the owner's decision.
- **Real ambiguity → OPEN QUESTIONS**, not a reasonable assumption disguised as a decision.
- If the feedback actually describes an initiative different from the PRD's (not a refinement
  but a new topic), don't force it in: say so in the comment. Deciding whether it deserves a
  separate PRD or unification is R7's responsibility outside this skill, not yours here.
- There is no interactive process: `AskUserQuestion` does not exist in this flow. If you feel
  you need to ask something, that question IS the OPEN QUESTION.

## Expected output per run

- PRD (issue) updated with the feedback incorporated and, if applicable, an `OPEN QUESTIONS`
  section.
- A `🔧 Refined: ...` comment with the idempotency marker.
- `prd:refine` label removed if it was set; PRD in `prd:needs-review`, ready for the owner's
  next review.

---
Adapted for the dev-loop from Addy Osmani's "idea-refine" skill — github.com/addyosmani/agent-skills (MIT).
