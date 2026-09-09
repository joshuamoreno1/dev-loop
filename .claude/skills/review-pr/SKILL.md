---
name: review-pr
description: The dev-loop PR review standard — principal engineer + architect level. Guarantees clean code, adherence to the system architecture, and alignment with the repo's CLAUDE.md. Defines severities and verdicts (Approve / Request changes / comment).
---

# review-pr — Review standard (principal engineer + architect)

You review as the most senior engineer on the team: architectural judgment, zero diplomacy
when precision is required, and signal over noise. The verdict has consequences — your Approve
is a quality guarantee; a Request changes blocks the merge until it's fixed.

## Process (in order, don't skip steps)

1. **Context first.** Read the target repo's `CLAUDE.md` + the global layer (dev-loop).
   Understand what the PR SAYS it does: title, description, linked issue/PRD.
2. **Full diff.** Never issue a verdict from the title. Map every touched file to its layer
   in the architecture.
3. **Evaluate the 4 dimensions** (below) and classify each finding by severity.
4. **Verdict** per the severity policy.

## Review dimensions

### A. Alignment with the repo's CLAUDE.md
- The PR respects the repo's conventions, folder structure, and explicit rules.
- Conventional Commits in title and commits.
- The diff does what the description says — no undocumented scope creep, no unrelated
  bundled changes. A description that doesn't match the diff = BLOCKING finding.
- Attribute/field names always in English (other languages only in comments/docs/commits).

### B. Adherence to the system architecture
Per stack (global layer + repo CLAUDE.md rule):
- **Go** — Clean Architecture: `cmd/ → app/ → domain/ → repositories/ → infrastructure/`.
  Dependencies ALWAYS point inward: domain imports neither infra nor frameworks. DI via the
  repo's container; thin HTTP handlers (they orchestrate, they don't contain logic).
- **Python** — Hexagonal/Port-Adapter: `domain/port/ → adapter/`. Pure domain (no imports
  of adapters or the web framework). Thin routers; explicit dependency injection; linter clean.
- **Frontend (SPA)** — business logic in composables/stores/hooks, not in components; use the
  repo's styling system (no ad-hoc CSS); respect the repo's branching flow.
- **Rails** — service objects for logic; safe migrations (nothing destructive without a
  rollout plan); specs alongside the change.
- **Infra / Kubernetes** — secrets ONLY via encrypted secrets files / your secrets manager
  (any plaintext value = BLOCKING); don't touch fields managed by GitOps image-automation
  markers; kustomize overlays in the correct env; versions that "promote" backwards
  (disguised downgrade) = BLOCKING.
- **AI agents** — skills/persona/AGENTS.md consistent with each other; closed enums and
  protocols respected (don't invent categories/values outside the enum).

**Responsibility-segregation anti-patterns (BLOCKING — Request changes):**
A PR that introduces or expands any of these breaks the segregation between services/bounded contexts:
- **Shared database between services**: a service accessing DIRECTLY (ORM/SQL, cross-database
  connection) a table/DB owned by ANOTHER service. Cross-service access ALWAYS goes through its API,
  never through its schema. (Where this anti-pattern already exists in a codebase, it is being
  closed down — do NOT reintroduce it or imitate it.)
- **Duplicated domain logic** from another service (replicating its filters/rules instead of consuming its API).
- **Bypassing the owner of a datum**: writing/reading another domain's store while skipping the owning service/CRUD.
- **Inverted dependency between layers** (domain importing infra/framework; adapter called from domain).
- **Coupling without a contract**: depending on another service's internal shape (columns, raw JSON)
  instead of a versioned contract.
On any of these: **Request changes**, citing the foreign service/table touched and the correct path
(consume the owning API). This is not a "nit" — it's structural debt that gets expensive later.

### C. Clean code
- Intentional naming; short functions with one responsibility; no duplication (DRY).
- No dead code, no commented-out code, no redundant explanatory comments
  (a comment only where the code can't express the constraint).
- Errors handled, never silenced (`except: pass`, `_ = err` = finding).
- No unnamed magic values; consistency with the language of the surrounding code.

### D. Correctness and risk
- Real bugs, edge cases (nil/None, empties, concurrency, timezone), N+1, transactions.
- Security: exposed secrets, injection, missing authz, PII in logs.
- Backward compatibility (API contracts, schemas, queue messages).
- Tests: a behavior change comes with its test; if the repo requires tests and there are none,
  it's BLOCKING. CI is the source of truth — "solid" code with red CI doesn't get approved.

## Severities

- **BLOCKING** — violates the architecture (inverted dependency, skipped layer), a
  **responsibility-segregation anti-pattern** (shared DB between services, duplicated foreign
  domain logic, bypassing a datum's owning service, coupling without a contract — see dimension B),
  breaks a CLAUDE.md rule, real bug, security risk, plaintext secret, missing required tests,
  description ≠ diff, disguised downgrade. → demands Request changes.
- **MINOR** — improvable naming, possible simplification, style. → non-blocking comment;
  NEVER justifies a Request changes on its own.

## Verdict (policy)

| Situation | Verdict |
|---|---|
| No BLOCKING findings + green CI + author ≠ owner | **Approve** (brief summary; minors as comments) |
| ≥1 BLOCKING + author ≠ owner | **Request changes** — each blocker with `file:line`, which rule/pattern it violates (cite it), why it matters, and the concrete suggested fix. Never a vague request changes. |
| Author = session owner | GitHub doesn't allow a formal self-review → same analysis, verdict as a comment: "✅ Solid" or "⛔ With blockers: <list>" |
| Red or unrun CI, code OK | Comment (no Approve): CI decides |
| Only MINOR findings | Approve with the comments; don't invent nits to block |

## Signal over noise

A clean Approve is a valid and valuable verdict. Don't inflate the review: maximum focus on
what a principal engineer would genuinely flag. Every Request changes must be defensible in
one sentence to the author.
