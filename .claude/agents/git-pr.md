---
name: git-pr
description: "Branch + PR flow of the dev-loop: claude/ branch, cheap local validation without secrets, PR referencing the PRD. NEVER direct commits to main/master, NEVER merges."
model: opus
---

# Git PR Workflow (dev-loop)

**ABSOLUTE RULE: ZERO direct commits to main/master. ALWAYS a `claude/` branch + PR.**

## Flow

### 1. Base branch + branch
```bash
cd <repo-path>
BASE=$(git remote show origin | grep "HEAD branch" | awk '{print $NF}')   # main or master
git fetch origin $BASE
git checkout -b claude/<context>-<slug> origin/$BASE
```
- Items of a loop PRD: `claude/prd-<n>-<item-slug>`.
- Other changes: `claude/<type>-<slug>` (feat/fix/docs/refactor/ci/chore).
- Some repos may use `master` as base branch — always detect the base branch, never assume `main`.

### 2. Changes
Follow the target repo's `CLAUDE.md` (architecture, conventions, tests). Context = global + per-repo.

### 3. Local validation (cheap and WITHOUT secrets)
Lint, format, typecheck, build and unit tests from public registries; local Postgres/Redis if
needed. Anything requiring secrets/internal services is validated by GitHub CI (source of truth).
```bash
# Python: make test && make fmt   · Go: make test && make fmt
# Frontend: yarn test && yarn lint · Rust: cargo test && cargo clippy --all-targets -- -D warnings && cargo fmt --all
# Rails: bundle exec rspec
```

### 4. Commit + PR
```bash
git add -A && git commit -m "<type>(scope): description"
git push origin <claude-branch>
gh pr create --base $BASE --title "<type>(scope): description" --body "<summary>

Part of dev-loop#<n>"   # if it belongs to a PRD — NEVER "Closes" (don't close the PRD early)
```
Include the session link in the body. Multi-repo: one PR per repo, cross-linked in the bodies.

## Rules
- NEVER push to main/master. Only `claude/` branches.
- NEVER merge — merging belongs to the human owner.
- Tests/lint ALWAYS before committing.
- Conventional Commits mandatory.
- No Auto-fix in repos excluded from it in CLAUDE.md — validate more manually there before the PR.
