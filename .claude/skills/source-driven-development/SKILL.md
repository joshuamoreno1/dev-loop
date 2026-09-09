---
name: source-driven-development
description: Grounds every implementation decision (API, method signature, model name, config) in the target repo's real code or in official documentation — never in memory/training. Use it before writing code that invokes a library, framework, internal service or model, and especially in routines that run on Opus (R2), with a high risk of hallucinating signatures/APIs that "sound" plausible.
---

# source-driven-development — Grounding in real sources

Opus is good at improvising API signatures that don't exist. In the dev-loop that's not an
academic detail: the **R2 routine runs on Opus** and edits target repos without anyone
reviewing line by line before the PR. An invented signature, a model name that doesn't exist,
or a parameter that "should" be there goes straight to CI — and if CI doesn't catch it, to
production.

**Hard rule:** before using an API, signature, method or config, **verify it** in the target
repo's real code or in the official documentation. If you didn't verify it, don't write it.

## The cycle: DETECT → VERIFY → IMPLEMENT → CITE

### 1. Detect stack and version
Before touching code, identify exactly what you are using:
- Read the target repo's `CLAUDE.md` (it's the source of truth for conventions — it overrides
  any generic assumption from training).
- Read the real dependency file: `go.mod`, `package.json`, `requirements.txt`/`pyproject.toml`,
  `Gemfile.lock`, `Cargo.toml`. The version matters — a signature valid in v2 may not exist in v1.
- If the version is ambiguous, say so explicitly and ask. Don't assume "the latest one I know".

### 2. Verify in the source of truth — two routes depending on what you're touching

**A. Internal repo code (most cases in the dev-loop):**
There is no "official documentation" for your internal repos — the source of truth IS the
code. Before calling a method, a handler, an internal service or a component:
```bash
grep -rn "def method_name" app/
grep -rn "func MethodName" internal/
```
Read the real signature (parameters, types, exact name) with `Read`/`grep`, don't recall it.
If the method doesn't show up, it doesn't exist — don't invent it "because it would make
sense for it to exist".

**B. External library / framework / third-party API:**
Authority hierarchy (most to least reliable):
1. Official documentation (react.dev, docs.djangoproject.com, docs.rs, pkg.go.dev)
2. The project's official changelog/blog
3. Web standards (MDN, web.dev)
4. Runtime compatibility (caniuse.com)

**Not authoritative, do not cite as a source:** Stack Overflow, tutorials, AI-generated
summaries, or "what I remember from training". If that's the only source you have, say so and
mark it as unverified — don't present it as fact.

**C. Model names / agent config (special case, it has bitten before):**
Model names are NOT guessed by pattern. Verify the real registry of the installed package
before writing the name in env vars or config:
```bash
grep -rn "opus\|haiku\|sonnet" node_modules/<agent-framework>/**/*.json
# or check the package's published registry at the version the repo runs
```
Real examples of this failure class: writing a model name one minor version above what
actually exists (a `-4-6` that was never released when the real name ends in `-4-5`), or an
agent framework whose registry only supports models up to a given version — a nonexistent
model name in the framework's model env var may not throw an error at all: it does a
**silent fallback** to a different model, and the problem goes unnoticed until someone
notices quality dropped. The lesson: never change a model name (in any config) without first
grepping the registry of the package that repo actually runs.

### 3. Implement per what you verified
- Use the exact signature you saw in the code or the docs — not the "improved" one from memory.
- If the repo's code contradicts what the official docs say (old version, deprecated
  pattern), **say so explicitly** instead of silently choosing. The target repo wins if its
  `CLAUDE.md` documents the deviation on purpose (e.g. a deliberately nonstandard spelling or
  naming in the codebase is intentional, not a typo to "fix").
- If you couldn't verify something (you didn't find the method, there's no clear official
  doc), mark it explicitly as unverified instead of filling the gap with an assumption.

### 4. Cite the source
Every nontrivial pattern carries its source, in the commit/PR or in a comment if the logic
isn't obvious:
- Internal code: `path/to/file.rb:123` (path relative to the repo + line).
- External: full, specific URL (the method's page, not the framework's home).
- If you quote a doc fragment to justify a non-obvious decision, quote it verbatim, not
  paraphrased from memory.

## Red flags (if you're doing this, stop and verify)
- Writing a method/API call without having done `grep`/`Read` on the real code first.
- Phrases like "I think the method is called..." or "it should accept..." — if you think,
  verify.
- Changing a model name or version in config without having checked the real
  registry/changelog.
- Citing Stack Overflow or a tutorial as if it were the authoritative source.
- Using a pattern that "was always used like this" without confirming it's still current in
  the repo's actual version.
- Delivering a PR without being able to say, for every nontrivial signature/API you touched,
  where you verified it.

## Checklist before writing the PR
- [ ] I read the target repo's `CLAUDE.md` (not just the dev-loop global layer).
- [ ] Every internal signature/method I call, I saw with `grep`/`Read` in the real code, not
      from memory.
- [ ] Every external API I use comes from official docs (specific URL), not a
      tutorial/blog/SO.
- [ ] If I changed a model name or agent config, I verified the package's real registry.
- [ ] No deprecated pattern present just because "that's how I remembered it".
- [ ] Conflicts between official docs and the repo's existing code are made explicit — not
      silently resolved.
- [ ] Everything unverified is marked as such, not presented as fact.

---
Adapted for the dev-loop from Addy Osmani's "source-driven-development" skill — github.com/addyosmani/agent-skills (MIT).
