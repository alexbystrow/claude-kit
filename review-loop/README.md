# review-loop

A Claude Code skill: review code and fix what's found, in rounds, until a fresh review finds no significant bugs.

- **Fresh reviewer every round,** so it never anchors on what was already fixed.
- **Bigger bugs only:** security, data loss, crashes, broken builds, wrong behaviour on a realistic path. Style and nits are listed, not fixed. A docs mode has its own bar (wrong fields, failing examples, broken links).
- **Verify before fixing:** every finding is traced against the code and marked confirmed, plausible or rejected. Reviewers hallucinate.
- **Cheap models first:** round 1 is a broad Haiku sweep; only a Sonnet round can end the loop as clean.
- **Stops** when a round is clean, at a cap of 5 rounds, or when a fix keeps coming back.

Scope defaults to the current branch's diff; it also takes a path, a PR number, a branch or `repo`.

## Install

```sh
ln -sfn "$PWD/review-loop" ~/.claude/skills/review-loop   # run from the claude-kit checkout
```

Then run `/review-loop`, or ask "review and fix until clean".
