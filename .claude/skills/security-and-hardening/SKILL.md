---
name: security-and-hardening
description: Security lens for PR reviews — secrets (encrypted secrets files / your secrets manager), tenant isolation, PII in logs, authz on endpoints, agent/LLM risks and per-stack dependency audits. Use it when R0/R5 review a PR that touches secrets, tenant data, authentication/authorization, third-party webhooks (payments, CRM, support tools) or any endpoint with access to sensitive data. Complements `review-pr` (dimension D) — does not repeat it.
---

# security-and-hardening — Security review

Security lens that R0/R5 apply **on top of** `review-pr`, never instead of it. `review-pr`
already covers dimension D (exposed secrets, injection, missing authz, PII in logs as general
findings) and already carries the segregation anti-pattern guardrail (shared DB between
services, bypassing a datum's owner). This skill exists to go deeper into what that guardrail
doesn't cover: the security risks **specific to how your systems operate** — encrypted secrets
in Git, tenant isolation, agents with tool-calling, third-party integrations. If the PR
touches none of those surfaces, don't apply this skill; use `review-pr` alone.

## Process: map boundaries first

Before hunting for findings, locate where the PR crosses a trust boundary. In typical stacks,
the real boundaries are:

| Boundary | Where it shows up |
|---|---|
| HTTP endpoint | API frameworks (Go, Python/FastAPI, Rails, Node) |
| Incoming webhook | Third-party webhooks (payments, CRM, support tools, messaging) |
| Agent tool-call | Agent skills, LLM output used as data or as a command |
| Cross-tenant query | Schema-per-tenant (`tenant_<uuid>`), `tenant_id` scoping in shared tables |
| Encrypted secrets file | `infra/**/*.enc.yml` — secret in transit Git → GitOps → K8s |
| Log/trace | Observability platform / log aggregator — PII and tokens from user messages |

If the diff touches none of these, this skill adds no signal — don't force it.

## 1. Secrets: encrypted secrets files (BLOCKING on failure)

A typical GitOps secrets setup encrypts **only** the `data`/`stringData` keys (regex
`^(data|stringData)$`), with a **different encryption key per environment** (staging,
production, shared). Practical consequences for the reviewer:

- A secret in a file **without** the `.enc.yml`/`.enc.yaml`/`.enc.json` suffix never passes
  through the encryption tool → it reaches Git and the cluster in **plaintext**. Any sensitive
  value outside a `*.enc.yml` is BLOCKING, no matter if "it's only for a review app" or "it's
  temporary".
- The encryption key referenced in the file must belong to the environment of its path.
  A staging key in a `prod/**` file (or vice versa) is a cross-environment leak — BLOCKING.
- The secret may only live under the `data:`/`stringData:` key of a `Secret` — if a
  token/password-looking value shows up inside a `ConfigMap` (`variables.yml`) or a literal
  `value:` under `env:` in a `deployment.yml`, it's plaintext even if the filename ends in
  `.enc.yml` (those other fields aren't covered by the encrypted-keys regex).
- Quick verification before approving:
  ```bash
  git diff --cached -- '*.enc.yml' '*.enc.yaml' '*.enc.json' | grep -E '^\+' | grep -vE '^\+\+\+|ENC\[' 
  # any + line NOT starting with ENC[ is an unencrypted value inside an enc file
  git diff --cached -- ':!*.enc.yml' ':!*.enc.yaml' ':!*.enc.json' \
    | grep -iE '\+.*(api[_-]?key|secret|token|password|bearer )'
  ```
- If a secret reached a commit/PR (even in a malformed enc file, a plain `.yml`, or a log
  pasted into the PR description): **rotate it at the provider** (identity provider, payments,
  CRM, LLM provider) immediately. Deleting the line or rewriting history isn't enough — it's
  assumed compromised the moment it touched a remote.

## 2. Tenant isolation (cross-tenant leakage) — the #1 real risk in multi-tenant systems

This is what a generic OWASP checklist doesn't capture, and it's the class of incident with
real precedent in production codebases:

- **Multi-tenant agent/API services**: a single image serves N tenants in the same pod; the
  tenant is resolved from a request parameter (e.g. `?namespace=<tenant_code>`) and a Postgres
  schema per tenant (`tenant_<uuid>`). The tenant identifier must **always be the complete
  UUID, never truncated**. Any code that resolves the schema/tenant from a value that comes
  from the **client's request** without validating it against the authenticated session/token
  is a tenant IDOR — BLOCKING.
- **Real precedent pattern**: a tenant-resolution hook coerced the tenant `code` (a UUID) to an
  integer via an implicit cast (`.to_i`) before resolving the tenant — an implicit
  truncation/cast could end up writing to the wrong tenant. Any `.to_i`, implicit cast,
  `substring`, or loose comparison (`==` without type) on a tenant identifier is a red flag —
  demand strict comparison against the complete UUID.
- Every query/repository method that reads or writes a tenant's data without an explicit
  filter (`WHERE tenant_id = current_tenant`, `search_path` to the correct schema, an ORM
  scope by tenant) is BLOCKING — it doesn't matter that "the bug only triggers in a rare
  case"; in multi-tenant, a rare case is a leak of another customer's data.
- Agent memory and logs/traces (the tenant tag in your observability platform) are also
  per-tenant data: verify one tenant cannot read another tenant's memory, history, or logs
  (agent memory APIs, diagnostic endpoints).

## 3. PII in logs / observability

- Never full phone/email/address in plaintext logs shipped to your log aggregator —
  mask or truncate (last 4 digits, domain without user, etc.).
  A trace can carry the tenant identifier as a tag — that's acceptable as a tenant
  identifier, but the **content** of user messages (chat, support, messaging channels) must
  not go out at INFO level without sanitizing.
- Redact `Authorization` headers/tokens before logging request/response of integrations
  (identity provider, payments, CRM, support tools) — a log with the full bearer token is
  equivalent to a plaintext secret; the same rotation rule from section 1 applies.

## 4. Authz on endpoints (broken access control)

Authentication (a valid JWT from your identity provider) is not authorization (that user has
access to THAT tenant/resource). Per stack:

- **Go**: the handler validates ownership/tenant *after* resolving the resource; it doesn't
  trust that the auth middleware already covered it — domain doesn't decide authz, but the
  handler must not skip the check.
- **Python/FastAPI**: `Depends(get_current_user)` proves identity; the tenant/role check goes
  explicitly in the service/adapter — it is not assumed just because the token is valid.
- **Rails**: a `before_action` that resolves the tenant must resolve it **from the
  authenticated token/session**, not blindly accept the `tenant_code`/`id` arriving as a
  param — if the param is only used for look-up without comparing against the token's tenant,
  it's the same pattern as the precedent in section 2.
- **Incoming webhooks** (payments, CRM, support tools, messaging): they must validate the
  provider's signature/secret, not just the payload shape — a webhook without signature
  verification is an unauthenticated endpoint disguised as an integration.

## 5. OWASP Top 10 — only what applies to your stacks

- **Injection**: always parameterize (whatever ORM the stack uses) — never interpolate user
  input into raw SQL.
- **XSS**: modern SPA frameworks auto-escape by default; any `v-html`/`dangerouslySetInnerHTML`
  with content not 100% controlled by the backend is a finding.
- **SSRF**: if any endpoint fetches a user-provided URL (webhooks, "import from URL", link
  preview), it must go through a host allowlist — never a direct `fetch(user_url)`; it can
  point at internal cloud metadata endpoints or internal services.
- **Security misconfiguration**: open CORS (`origin: '*'` or reflecting any origin) on public
  frontends/APIs, missing security headers.

## 6. Agent/LLM risks — an attack surface of its own

- **Prompt injection**: messages from chat/support/messaging channels that the agent reads as
  context can carry instructions. The system prompt/persona **is not a security boundary** —
  permissions live in code (skills with explicit tool access), not in the instruction.
- **Excessive agency**: destructive actions (closing/reassigning tickets, touching K8s, moving
  money) require explicit confirmation or a skill allowlist — same spirit as the Sacred Rules
  of the global CLAUDE.md (never restart/delete K8s resources or act without confirmation).
- **LLM output as data, not as a command**: never `eval`/raw SQL/direct shell from text
  generated by the agent — validate and type before executing any action.
- **Memory/RAG partitioned per tenant**: see section 2 — an agent must not be able to retrieve
  memory or context from a tenant that isn't its own.

## 7. Dependencies — per-stack audit

| Stack | Command |
|---|---|
| Go | `govulncheck ./...` (lockfile: `go.sum` committed) |
| Python (uv) | `uv pip audit` / `pip-audit` against the project lockfile |
| Node (yarn) | `yarn audit` / `yarn npm audit` |
| Ruby | `bundle audit` |

Triage: critical/high severity + code reachable at runtime = fix now; not reachable
(confirmed) = fix soon, non-blocking. Never apply forced remediation
(`--force`/equivalent) without reading the changelog of the resulting version — it may jump
outside the declared version range or introduce a silent breaking change.

## Review checklist

```markdown
- [ ] No plaintext secret outside `data:`/`stringData:` of a `*.enc.yml`
- [ ] The file's encryption key matches its environment (staging/prod/shared)
- [ ] Every query/endpoint over tenant data validates the tenant against the session/token,
      not against a request param/query string
- [ ] tenant_code/tenant identifier always the complete UUID, no type coercion (.to_i, substring, cast)
- [ ] Logs don't expose full PII (phone/email/address) or tokens/Authorization
- [ ] Every protected endpoint verifies authz (not just authn) — ownership + tenant
- [ ] Incoming webhooks validate the provider's signature/secret
- [ ] If an agent/LLM is involved: output treated as untrusted, tool permissions scoped,
      memory/RAG partitioned per tenant
- [ ] Dependencies: no unmitigated reachable critical/high findings in the stack's lockfile
```

## Verdict

Use the same severities and policy as `review-pr`. Any finding flagged above is
**BLOCKING** by default (cross-tenant leak, plaintext secret, missing authz, webhook without
signature verification) — report it with `file:line`, which rule it violates (cite this skill)
and the concrete fix. Only downgrade to MINOR something clearly cosmetic (e.g. improvable
logging where it's already confirmed no real PII is exposed). Don't inflate the review by
inventing risks if the PR touches none of the boundaries in the "Process" section.

---
Adapted from Addy Osmani's "security-and-hardening" skill —
github.com/addyosmani/agent-skills (MIT).
