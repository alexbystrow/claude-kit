---
name: review-loop
description: Review code and fix what's found, in rounds, until a fresh review finds no significant bugs. Use when the user invokes /review-loop, or asks to "review and fix until clean", "keep reviewing until no bugs", "harden this branch", or similar. Scope defaults to the current branch's diff against the default branch; accepts a path, PR number, branch, or "whole repo". Targets correctness, security, crashes, data loss, and broken builds — not style nits.
---

# Review Loop

Review → verify → fix → re-check, repeated until a round comes back clean. Each round uses a **fresh reviewer** with no memory of earlier rounds, so it doesn't anchor on what you already fixed.

## 0. Set scope and bar

- **Scope** (from args, else default):
  - no args → `git diff $(git merge-base HEAD <default-branch>)...HEAD` plus uncommitted changes
  - path / glob → those files
  - PR number or branch → that diff (`gh pr diff <n>` / `git diff <base>...<branch>`)
  - `repo` → whole codebase; prioritise entry points, recently changed files, and anything security-relevant
- **Severity bar — "bigger bugs" only.** Fix a finding only if it is:
  - **critical** — security hole, data loss/corruption, crash, build/CI broken, secret leaked
  - **high** — wrong behaviour on a realistic path, broken contract/API, race, resource leak, missing error handling that hides failures, regressions
  - Everything else (style, naming, nits, speculative "might be nice") → **list it, don't fix it**, unless it's a one-line fix inside code you're already touching.
- **Docs mode** — when the scope is documentation (Markdown pages, guides), use this bar instead and pass it verbatim:
  - **critical** — a claim that makes a reader lose data or expose something (an unsafe default, a missing auth step), a construct that breaks the docs build, a leaked internal name or secret
  - **high** — a wrong path, method, field, header, status or error code, default or limit; an example request that fails as written; a broken link or anchor; a guarantee the source does not give; steps that do not work in the order given
  - Everything else (wording, structure, missing nice-to-know) → list it, don't fix it.
- **Baseline checks:** find the project's test / lint / typecheck / build commands (package.json scripts, Makefile, CLAUDE.md, CI config). Run them once now and record which already fail — pre-existing failures are not this loop's regressions, but mention them. Split them into **fast** (lint, typecheck, unit tests: run every round) and **slow** (full build, link crawl, e2e: run once after the last round). **If the repo's PR CI runs a slow check, the CI run is that check:** push and read `gh pr checks`, never rebuild it locally (tokens cost money).
- **Sources** (docs mode, or any claim-heavy scope): list the sources of truth the reviewer must check against (source repo clone at a pinned commit, spec file, unpacked dependency) as local paths. Fetch or clone them once yourself, before round 1, so no reviewer spends its context on downloading.
- **Round cap:** 5 rounds, unless the user gave another number.

## 1. Review (fresh agent every round)

Spawn a **new** `general-purpose` agent (never continue the previous round's reviewer).

**Model per round:**
- **Round 1 → `model: "haiku"`**, a broad sweep. Cheap and good at finding related problems; step 2 filters its false positives. Haiku rarely reports a round as clean (it rates severity high), so it never decides when to stop.
- **Round 2 onwards → `model: "sonnet"`.** Only a Sonnet round can end the loop as *clean*: Haiku skips verify-first steps, and a bug it misses would end the loop silently.
- **Opus** only when the user asks, or the scope is security, a migration, a public API contract or a prod incident.
- **Haiku context stays under 100k tokens** (5x price above). An agent starts at about 50k before reading anything, so the instruction alone does not hold it (measured 2026-10-14: 112–121k per round). **Give each Haiku reviewer one file** (or one module) and run them in parallel in one message; also tell it: *"If your context passes about 80k tokens, stop and report what you have, and say which parts you did not reach."* Unreached parts go into the next round's scope.

Prompt it with:

- the exact scope (diff command or file list) and repo path
- the project's CLAUDE.md gotchas, if any, as context
- the severity bar above (code or docs mode), verbatim
- the sources list, as local paths, and any artifact an earlier round produced (an unpacked dependency, a fetched spec). Pass **paths forward, never findings**, so the reviewer stays fresh.
- the instruction: *"Read the actual code, not just the diff hunks — follow callers and callees where a bug could hide. For each finding return: file:line, severity (critical/high/medium/low), one-sentence defect, a concrete failure scenario (inputs/state → wrong result), and a suggested fix. Report only; do not edit files. If nothing at high or above, say so explicitly."*

For large scopes (> ~30 files or `repo`), split by area and run several reviewer agents **in parallel** in one message.

## 2. Verify findings

Before fixing, check every critical/high finding yourself against the code:

- **CONFIRMED** — you can trace the failure scenario → fix it
- **PLAUSIBLE** — can't disprove, fix is cheap and safe → fix it
- **REJECTED** — reviewer misread the code, or it's intended behaviour (check comments, CLAUDE.md, ADRs, ticket AC) → drop it, note why

Reviewers hallucinate. Never fix a finding you haven't verified.

## 3. Fix

- Smallest correct change; match surrounding style. No drive-by refactors.
- If a fix would redesign something, conflicts with acceptance criteria, or needs a product decision → **stop and ask** instead of fixing.
- Add or adjust a test when the project has tests for that area and the bug is testable.

## 4. Re-check

- Re-run the **fast** baseline checks (slow ones run once at the end). A new failure → fix it before moving on (it counts toward this round).
- Commit the round if the user's git rules allow autonomous commits (respect their branch / trailer / ticket-prefix rules), e.g. `Fix review-loop round N findings`. Otherwise leave changes staged and say so.

## 5. Loop or stop

- **Stop — clean:** a fresh **Sonnet** review returns **no confirmed critical/high findings**. Then run the slow checks once.
- **Stop — cap:** round cap reached → report what's still open.
- **Stop — stuck:** the same finding survives two fix attempts, or fixes keep introducing new high findings → stop and ask.
- **Fix-induced finding:** a high finding caused by the previous round's own fix gets one more fix. If the next round finds another one in the same place, stop and report it instead of looping.
- Otherwise → back to step 1 with a new reviewer. Scope for later rounds = original scope **plus** everything you changed.
- **Narrow confirming round:** if the last round had at most 2 confirmed high findings and every fix stayed inside one section or function, the next round's scope can be the fixed hunks plus their enclosing section or function (and their callers, for code) instead of the whole scope. Any new high finding there → widen back to the full scope.

## 6. Report

Keep it scannable:

- **TL;DR** — one line: clean after N rounds / stopped at cap / stuck.
- **Table** per round: model · findings raised · confirmed · rejected · fixed.
- **Fixed** — `file:line` + one line each.
- **Rejected** — one line each with the reason.
- **Left open** — medium/low findings not fixed, and anything that needs a decision.
- **Checks** — final test/lint/build status, with pre-existing failures called out separately.
