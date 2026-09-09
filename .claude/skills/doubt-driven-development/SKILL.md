---
name: doubt-driven-development
description: Adversarial self-review with fresh context before opening or approving a PR — verifies that the diff REALLY does what the description/commit says, not what R2 believes it did. Use it when R2 is about to open a PR that fixes a bug, touches concurrency/lifecycle/disposal, crosses an architecture boundary, or makes a non-trivial claim ("it's fixed", "it's thread-safe", "no more leak"); and when R0/R5 review a PR from another agent. Does NOT apply to mechanical changes (rename, formatting, an obviously correct one-liner) or when the owner explicitly asked for speed over verification.
---

# doubt-driven-development — Doubt your own claim before it stands

A confident PR is not a correct PR. R2 runs on Opus, with nobody reading line by line before
the PR opens, and in a long session the model accumulates context that turns assumptions into
"facts" without anyone noticing — including R2 itself. Doubt-driven is the discipline of
materializing a **fresh-context** reviewer, biased to **refute, not approve**, before a
non-trivial claim gets to stand.

**Real case that motivates this skill:** a PR said "fixed the memory leak: added `dispose()`
which cancels the stream subscription" in `XyzViewModel`. The diff did indeed add that
`dispose()`. But the `ViewModel` was still registered as a `lazySingleton` in the service
locator (`getIt.registerLazySingleton<XyzViewModel>(() => XyzViewModel())`) — a single
instance that lives for the entire life of the app and on which nobody ever calls `dispose()`,
because `get_it` doesn't dispose lazy singletons automatically when navigating between
screens. The added `dispose()` was dead code. R2 read its own diff and saw "I added dispose,
therefore I fixed the leak" — a plausible, false inference. Nobody compared the claim against
the actual DI registration until the leak reappeared in production.

This is **not** `review-pr`. `review-pr` is the final verdict on a finished PR (Approve /
Request changes). This skill is the prior stance: doubting your own claim while course
correction is still cheap — before R2 opens the PR, or as the first move of R0/R5 when
receiving it.

## When to use it

A claim is **non-trivial** when at least one of these is true:
- It says something stopped failing ("fixed", "no more leak/race/N+1") without the PR
  including the proof that demonstrates it.
- It touches lifecycle, disposal, DI scope, concurrency, or shared state — the kind of
  property the compiler/linter can't verify.
- It crosses an architecture or service boundary (see `review-pr` dimension B).
- Its blast radius is irreversible (deploy to prod, migration, public API contract).
- It depends on context the next person reading the code won't have.

**When NOT to use it:** rename, formatting, an obviously correct one-line PR, following an
unambiguous instruction from the owner, or when the owner explicitly asked for speed over
verification. Doubting every keystroke ships nothing — the skill applies only to the
non-trivial.

## Who runs it, and the non-negotiable rule

- **R2, before opening the PR (self-review):** R2 cannot be its own "fresh context" reviewer —
  it already lives inside the reasoning that produced the fix. For Step 3 (DOUBT), R2 must
  invoke a **new subagent** (Agent tool, `general-purpose` or `Explore`) that receives ONLY
  the diff and the contract — never R2's session, never its reasoning, never the PR
  description R2 itself wrote.
- **R0/R5, when receiving R2's PR:** they are fresh context by construction (a separate
  routine that didn't inherit R2's session). The risk here is different: reading the PR
  description and believing it. The hard rule is the same: the contract is verified against
  the diff; the description is evidence of nothing.

In both cases, the Step 3 reviewer receives ARTIFACT + CONTRACT. It never receives the CLAIM —
passing the conclusion biases toward validation.

## The cycle: CLAIM → EXTRACT → DOUBT → RECONCILE (→ STOP)

```
Checklist to copy into every doubt cycle:
- [ ] Step 1 CLAIM      — the PR's claim, written in 2-3 lines + why it matters
- [ ] Step 2 EXTRACT    — isolated diff (not the description) + the real contract it must satisfy
- [ ] Step 3 DOUBT      — fresh-context subagent, adversarial prompt, ARTIFACT+CONTRACT only
- [ ] Step 4 RECONCILE  — each finding classified against the real diff, not the description
- [ ] Step 5 STOP       — stop condition met (trivial findings, 3 cycles, or "ship it")
```

### Step 1 — CLAIM: name the claim

Extract the EXACT claim from the PR's title/description/commit — don't paraphrase it into
something more defensible.

```
CLAIM: "Fixed the XyzViewModel memory leak:
        dispose() cancels the stream subscription."
WHY IT MATTERS: if the leak persists, every navigation
                accumulates memory until the app OOMs in
                long sessions — invisible in quick QA.
```

If you can't write it in two lines, it's a vibe, not a verifiable claim. Bring it into the
light before scrutinizing it.

### Step 2 — EXTRACT: the minimal reviewable unit

The subagent needs the **real diff** and the **contract**, not the PR's narrative.

- **ARTIFACT** = the PR's full diff (`gh pr diff <N>`), not your summary of what you changed.
- **CONTRACT** = what has to be true for the CLAIM to be real. In the leak case:
  "the `XyzViewModel` instance must not accumulate listeners/memory over the app's lifetime;
  if the fix depends on `dispose()`, something has to call it at some point in the screen's
  real lifecycle."
- If the diff is a 500-line PR, don't send it whole: decompose the CLAIM by relevant
  file/hunk first. A reviewer can't hold 500 lines in a single useful read.

Don't send your reasoning about why you think it works. If you hand over the conclusion, you
get back a validation of your conclusion.

### Step 3 — DOUBT: invoke the fresh-context reviewer

The prompt **must be adversarial** — the framing decides the answer.

```
Adversarial review. Find what is WRONG in this artifact
with respect to the contract. Assume the author is overconfident.
Look specifically for:
- Does the fix attack the CAUSE or only a cosmetic symptom?
- If it depends on a method/hook (dispose, cleanup, cancel):
  does anything in the real code invoke it? in which lifecycle/scope?
- DI registration / object scope: did it change, or is it the same
  as before the "fix" (lazySingleton, global, static)?
- Other code paths retaining the same reference.
- Existing repo conventions this breaks.
- What happens in the case the PR doesn't mention.

Do NOT validate. Do NOT summarize. Find problems, or state
explicitly that you found none after exhaustive review
of the ARTIFACT against the CONTRACT.

ARTIFACT: <full diff, gh pr diff <N>>
CONTRACT: <what must be true for the CLAIM to be real>
```

Pass ARTIFACT + CONTRACT only. **Do not pass the CLAIM** — spoiling the conclusion biases the
reviewer toward confirming it instead of refuting it.

In the dev-loop, this is invoked with the Agent tool (`subagent_type: general-purpose` or
`Explore` to locate the real DI registration/lifecycle in the code). If R0/R5 are already the
reviewing routine, the "subagent" can be R0/R5 itself as long as it enters the diff WITHOUT
having previously read the PR description as if it were verified fact.

### Step 4 — RECONCILE: fold in the findings; don't accept or ignore them wholesale

The reviewer's output is data, not a verdict. You remain the orchestrator — re-read the diff
against each finding before classifying. Accepting everything without re-reading the code is
the same mistake as ignoring it all.

Classify each finding, in this order of precedence (first that applies wins):

1. **Badly framed contract** — the reviewer flagged something because the CONTRACT you gave it
   was ambiguous or incomplete. Fix the contract first, re-classify on the next cycle.
2. **Valid and actionable** — a real problem that requires changing the artifact. Change it,
   run the cycle again.
3. **Valid trade-off** — the problem is real but the cost of fixing it exceeds the cost of
   accepting it. Document the trade-off explicitly in the PR — let the owner see it, don't
   hide it.
4. **Noise** — the reviewer flagged something that is actually correct under context it didn't
   have. Note it and move on; ask yourself whether adding that context to the CONTRACT would
   have avoided the false positive.

A fresh reviewer can be wrong for lack of context. Don't grant it the point just "because it's
fresh" — go look at the diff again.

### Step 5 — STOP: a bounded cycle, not infinite recursion

Stop when:
- The next cycle returns only trivial or already-considered findings, **or**
- 3 cycles are complete (escalate to the owner; don't give it a fourth solo lap), **or**
- The owner explicitly says "ship it".

If after 3 cycles the reviewer keeps producing substantial findings, the PR probably isn't
ready — report it, don't force it. If 3 cycles is "obviously insufficient" because the diff is
large: the diff is too large — go back to Step 2 and decompose. Don't raise the limit.

## Full example: the leak that "was fixed"

| Step | Content |
|---|---|
| **CLAIM** | "Memory leak fix: `XyzViewModel.dispose()` cancels the `StreamSubscription`." |
| **EXTRACT** | ARTIFACT = diff with the new `dispose()` in `lib/features/x/view_model/xyz_view_model.dart`. CONTRACT = "the instance stops accumulating memory over the app's lifetime; if `dispose()` is the mechanism, something must invoke it." |
| **DOUBT** | Subagent (`Explore`) receives ARTIFACT+CONTRACT, runs `grep -rn "XyzViewModel" lib/core/di/service_locator.dart` and finds `getIt.registerLazySingleton<XyzViewModel>(() => XyzViewModel())` — untouched in the diff. Reports: "`dispose()` has no visible caller; `get_it` doesn't invoke `dispose()` on lazy singletons when leaving a screen; the instance lives forever, the fix is reachable only if something explicitly calls `getIt<XyzViewModel>().dispose()`, and I didn't find it." |
| **RECONCILE** | Valid and actionable (not noise: the real `service_locator.dart` was re-read; the instance is effectively neither recreated nor disposed). The DI registration must change to `registerFactory` (new instance per screen, disposed on exit) or the `dispose()` must be wired to a real navigation hook that actually runs. |
| **STOP** | Cycle 1 found a real blocking finding → Request changes citing `service_locator.dart:N` and the concrete fix. Not approved with `dispose()` as dead code. |

## Common rationalizations (don't believe them)

| Rationalization | Reality |
|---|---|
| "The PR describes the fix well, no need to look at the diff" | The description was written by the same R2 that convinced itself it worked. The evidence is the diff, not the prose. |
| "I wrote it myself, I know it works" | Confidence doesn't correlate with correctness on novel problems — the `lazySingleton` leak was written by someone convinced it worked. |
| "Invoking a subagent is expensive" | Debugging a leak in production is more expensive. The check is bounded; the prod bug isn't. |
| "The reviewer will just nitpick" | Only if the prompt isn't scoped. Constrain it to "findings that would make the CONTRACT fail", not "what do you think of the code". |
| "I'll do the doubting at the end with review-pr" | `review-pr` is the final gate. Doubt-driven catches the wrong course early, while correcting is cheap. By PR time, it's already late. |
| "The reviewer found nothing, we're done" | Valid only if the CONTRACT was complete. If the CONTRACT was ambiguous, "nothing found" is noise from a badly framed contract, not an approval. |
| "R0/R5 already review; R2 doesn't need to doubt itself" | R0/R5 review the description + diff of the finished PR. This skill cuts in earlier, while R2 can still fix it without burning a review cycle of the reviewers configured in CLAUDE.md's Review roster (or a self-review cycle if none). |

## Red flags

- Invoking a fresh-context subagent for a rename or a formatting change.
- Treating the reviewer's output as authoritative without re-reading the real diff.
- Running more than 3 cycles without escalating to the owner.
- Reviewer prompt like "is this okay?" instead of "find what's wrong".
- Skipping the doubt under time pressure on a high-impact decision (disposal, concurrency, service boundary).
- Passing the CLAIM to the subagent (biases toward confirmation).
- Accepting "I added the dispose/cleanup" as proof the resource is released, without verifying who invokes it and in which DI scope the object lives.
- Trusting the PR description as if it were the contract — the contract is defined by Step 2's CONTRACT, not by R2's prose.
- Re-invoking the subagent on an unchanged artifact (same findings; you're stuck, not doubting).

## Relationship to other dev-loop skills

- **`review-pr`**: complementary. Doubt-driven is in-flight, per-claim, before the PR or at the
  start of the review; `review-pr` is the final verdict (Approve / Request changes) on the
  completed PR. A PR can go through several doubt-driven cycles and still need the
  4-dimension check of `review-pr` before the verdict.
- **`source-driven-development`**: SDD verifies that a signature/API/config really exists.
  Doubt-driven verifies that your reasoning about what the diff achieves is correct. SDD
  checks that the method exists; doubt-driven checks that, even though it exists, you used it
  in a way that actually satisfies the contract (the `dispose()` existed and compiled — the
  problem was that nobody called it).
- **`test-driven-development`**: a test that reproduces the bug and fails BEFORE the fix, and
  passes after, is a form of doubt already resolved with evidence — if the bugfix has that
  test, much of Step 3 is already covered for the behavior the test exercises. But a test that
  only verifies `dispose()` doesn't throw, without verifying it's invoked in the real
  lifecycle, doesn't replace the cycle — it's exactly the kind of false positive doubt-driven
  catches.

## Verification

- [ ] The PR's non-trivial claim was written as an explicit CLAIM before accepting it.
- [ ] The Step 3 reviewer had real fresh context: a new subagent (if R2 self-reviews) or
      R0/R5 without having taken the PR description as verified fact.
- [ ] The reviewer received ARTIFACT (real diff) + CONTRACT — never the CLAIM, never R2's narrative.
- [ ] The prompt was adversarial ("find what's wrong"), not validating ("does this look good?").
- [ ] Each finding was classified by re-reading the real diff, with the precedence: badly
      framed contract / valid-actionable / valid trade-off / noise.
- [ ] A stop condition was met: trivial findings, 3 cycles, or the owner's "ship it".
- [ ] If the CLAIM depended on a cleanup method/hook (dispose, cancel, close), it was verified
      who invokes it and in which scope/lifecycle the object lives — not just that the method exists.

---
Adapted from Addy Osmani's "doubt-driven-development" skill — github.com/addyosmani/agent-skills (MIT).
