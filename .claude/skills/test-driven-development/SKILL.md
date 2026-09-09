---
name: test-driven-development
description: The dev-loop TDD discipline — Red-Green-Refactor, the Prove-It Pattern for bugs, the test pyramid, and verification before declaring a change complete. Use it when implementing any new logic, fixing a bug, modifying existing behavior in a target repo (Go, Python, TypeScript/Node, SPA frontends, Ruby on Rails, Rust, AI agents), or before opening a PR from R2/git-pr. Does NOT apply to purely config, docs, or static-content changes with no behavioral impact.
---

# test-driven-development — TDD in the dev-loop

A test is proof; "it seems to work" is not a verdict. You write the failing test BEFORE the
code that makes it pass. A repo with good tests is a superpower for an agent iterating
without constant supervision; a repo without tests is debt that charges interest on every PR.

**When it does NOT apply:** purely configuration changes (kustomize YAML, env vars), docs,
static content with no behavior. Everything else — new logic, bugfix, refactor that touches
behavior, edge case — goes through this cycle.

## The RED-GREEN-REFACTOR cycle

```
    RED                  GREEN                  REFACTOR
 Test that FAILS   →   Minimal code that   →   Clean up without
 (the behavior         makes it pass           breaking tests
 doesn't exist yet)                            (repeat as needed)
```

1. **RED** — Write the test first. It must fail. If it passes right away, it isn't testing
   anything (empty fixture, mock that always answers ok, trivial assertion).
2. **GREEN** — Minimal code to pass the test. Don't over-engineer or solve the next ticket
   in one go — that's a refactor or a separate PR.
3. **REFACTOR** — With tests green, improve names, extract shared logic, remove duplication.
   Run the tests after every refactor step, not just at the end.

## Prove-It Pattern (bugfixes)

Given a reported bug, **don't start with the fix.** Start with the test that reproduces it.

```
Bug reported → Test reproducing the bug → Test FAILS (bug confirmed)
→ Implement the fix → Test PASSES → Run the full suite (no regressions)
```

If the bug was reported by an agent in the loop or by CI, the reproduction test goes in the
same PR as the fix — never "fix now and add the test later if there's time".

## Cycle per stack — real commands

The dev-loop's local validation (see `.claude/agents/git-pr.md`) is **cheap and secret-free**:
lint, format, build, and **unit tests** that don't depend on internal services or credentials.
Anything that needs secrets, internal services, or real infrastructure is validated by
**GitHub CI — the source of truth**, never "it ran fine on my machine" as the final argument.

| Stack | Local RED-GREEN command | Architecture notes |
|---|---|---|
| **Go** (Clean Architecture: `cmd/→app/→domain/→repositories/→infrastructure/`, thin HTTP handlers, DI container) | `go test ./...` (add `-race` if it touches concurrency) | Test `domain/` pure, without infra mocks — if you need to mock the ORM to test a business rule, the rule is in the wrong layer. Layers like `app/`/`repositories/` do use fakes/stubs of their ports. |
| **Python** (Hexagonal `domain/port/→adapter/`, web framework + DI, formatter/linter) | `make init && make test && make fmt` (or the repo's `pytest` + formatter) | Test `domain/` without importing the web framework or concrete adapters. DI fixtures inject fakes of the ports, not mocks of the framework. |
| **SPA frontends** (TypeScript/Node, component framework + stores) | `yarn test` (or the repo's watch variant) + `yarn lint` | Business logic goes in composables/stores/hooks — test it there, not through the component. If the change is visual/E2E, complement with the `verify` or `run` skill before declaring the fix done. |
| **Rails** | `bundle exec rspec [spec/path_spec.rb[:line]]` | Service objects are the natural unit of test — one service, one spec. Destructive migrations aren't validated with specs; they're validated with an explicit rollout plan in the PR. |
| **Rust** | `cargo test && cargo clippy --all-targets -- -D warnings && cargo fmt --all` | Clippy with `-D warnings` is part of the GREEN cycle, not a separate step — a new warning blocks just like a broken test. |
| **AI agents** (agent runtime repos) | The repo's local build/run smoke scripts + unit tests in the agent's base language (Go/Python/TS) | No real secrets locally: use fixtures/mocks of chat platforms, CRMs, and internal APIs. Smoke tests with real data (leads, tickets) run in the real environment, not in R2. |
| **Infra / Kubernetes** | `kustomize build <env>/resources && kubectl apply --dry-run=server -f <file>` | Not classic TDD, but the same principle applies: validate the manifest BEFORE assuming it applies cleanly. `dry-run=server` is your "RED before GREEN". |

## The test pyramid

```
        ╱╲        E2E (~5%)      — full flows, minutes, real environment
       ╱  ╲       Integration (~15%) — crosses a boundary (DB, API, queue), seconds
      ╱────╲      Unit (~80%)    — pure logic, isolated, milliseconds
     ╱──────╲
```

**Beyoncé rule:** if you liked it, you put a test on it. A refactor, a migration, or an infra
change is not responsible for catching your bugs — your tests are. If something breaks and
you had no test for it, it's on you.

Decision guide:
- Pure logic, no I/O? → unit test (domain/, composables, service object).
- Crosses a boundary (repository, adapter, external API, message queue)? → integration test.
- A critical end-to-end user flow (login, checkout, full ticket)? → E2E, limited to critical
  paths — don't use it to cover edge cases a unit test resolves more cheaply.

## Writing good tests

- **Test state and outcome, not implementation.** Verify what the function returns or the
  observable side effect, not which internal method it called. A test that verifies `expect(repo.Save).toHaveBeenCalledWith(...)` breaks on any refactor even when behavior doesn't change.
- **DAMP over DRY in tests.** Every test should read as a complete specification without
  having to chase a shared helper. Duplicating the arrange between tests is fine if it makes
  each one self-explanatory.
- **Test-double preference (from most to least confidence):** real implementation > fake
  (in-memory port/repository) > stub (returns fixed data) > interaction mock. Mock only at
  the boundary where the real thing is slow, non-deterministic, or has side effects you
  don't control (external APIs, real message/email sends, third-party support tools).
- **Arrange-Act-Assert.** Setup, action, verification — in that order, unmixed.
- **One assertion per behavioral concept**, not a giant test proving three rules.
- **Descriptive names** that read as specification: `it('rejects tickets without an assigned group')`,
  not `it('works')` or `it('test 3')`.

## Anti-patterns to avoid

| Anti-pattern | Problem | Fix |
|---|---|---|
| Testing implementation details | Breaks on refactor even when behavior didn't change | Test input/output, not internal structure |
| Flaky tests (timing, execution order) | Erode trust in the suite — the team starts re-running "just in case" | Deterministic assertions; every test isolates its own state |
| Testing framework/library code (web framework, ORM) | You waste time proving something that isn't yours | Test ONLY your code (domain, your own adapters) |
| Snapshot abuse | Huge snapshots nobody reviews, break on any change | Use sparingly; review every snapshot diff in the PR |
| No isolation between tests | Pass alone, fail when run together | Every test does its own setup/teardown |
| Mocking everything | The test passes, production breaks | Real > fake > stub > mock; mock only at the external boundary |

## Common rationalizations (don't believe them)

| Rationalization | Reality |
|---|---|
| "I'll write the test after it works" | You won't. And a test written after proves the implementation, not the expected behavior. |
| "This is too simple to test" | Simple things get complicated. The test documents what was expected, for the next one to touch the code (agent or human). |
| "Tests slow me down" | They slow you down TODAY. They save time every time someone (including you, on R2's next run) touches that code. |
| "I tested it manually" | It doesn't persist. Tomorrow a change breaks it and nobody finds out until it blows up in prod. |
| "It ran fine on my machine" | Valid only for the cheap local validation. If the change touches secrets/internal services, the verdict belongs to CI — skipping this step has produced strings of red CI runs historically. |
| "I already ran the tests, I'll run them again just in case" | With no code change in between, repeating the same command adds nothing. Re-run only after the next edit. |
| "It's just a prototype / a small PRD" | PRD items end up in PRs and in main. TDD from day one avoids the "test debt" crisis when the prototype becomes permanent. |

## Red flags

- New code without a corresponding test in the same PR.
- Tests that pass on the first run (they may not be testing what you think).
- "All tests pass" without having actually run the command (running only the touched file's
  tests instead of the full suite has let regressions through).
- Bugfix without a reproduction test.
- Tests that verify framework behavior, not your code's.
- Tests disabled/skipped so the suite "passes".
- Repeating the same test command twice in a row with no code change in between.

## Verification before declaring the change complete

Before R2/git-pr opens the PR, or before reporting to the owner that a change is ready:

- [ ] Every new behavior has its test.
- [ ] The stack's test command ran clean (table above) — locally, without secrets.
- [ ] If it's a bugfix: the reproduction test exists and failed BEFORE the fix.
- [ ] Test names describe the verified behavior, not "test1"/"works".
- [ ] No test was left skipped or commented out to dress up the suite.
- [ ] Coverage didn't drop (if the repo tracks it).
- [ ] What local validation CANNOT cover (secrets, internal services, real integration)
      is stated explicitly in the PR description — GitHub CI validates it, not an
      assumption.

---
Adapted from Addy Osmani's "test-driven-development" skill — github.com/addyosmani/agent-skills (MIT).
