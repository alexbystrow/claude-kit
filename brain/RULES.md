# Brain rules

Copy this file to `~/brain/RULES.md` and adjust it. Claude reads it before writing a note.

## What goes in
- Facts and flows that **cross repos** or **outlive one session**, which no repo file owns.
- Each claim **verified from a source** (a file path with line, a URL, a command) on a date.

## What never goes in
- **Secrets**: no token values, no `.env` content. Variable NAMES are fine.
- **Copies of a repo's AGENTS.md, a skill, or ~/.claude/CLAUDE.md**: link to them instead. Two copies drift.
- **Things that change every release**: version numbers, command counts, allowlist contents, ticket numbers as facts.
- **Private content**: PR/ticket text, client data, people's handles.
- **Preferences about how to work with you**: those stay in ~/.claude/CLAUDE.md or per-project memory.

## Conflicts
The repo's AGENTS.md wins for that repo. ~/.claude/CLAUDE.md wins over the brain. A brain note never overrides either; if it contradicts one, fix or delete the note.

## Note shape
Frontmatter `summary`, `type` (flow | fact | decision), `verified: YYYY-MM-DD`, `source:` (paths or URLs). Body: `## Facts` (one checkable claim per bullet), `## How to apply`, `## Related` with `[[wikilinks]]`. At most about 60 lines.

## Write protocol
- **Before adding**, grep `~/brain` for the subject; update the existing note instead of making a second one.
- **Every add, rename or delete updates `index.md` in the same change.** One line per note.
- **Index budget: 60 lines or 8 KB, whichever comes first** (it loads into every session; past about 60 lines an index stops being read). Over budget: split into section indexes (`facts/index.md`, `flows/index.md`), the main index keeps one line per section; delete or merge notes only when they are stale or duplicate.
- **Stale**: a note verified more than 90 days ago, or whose source changed, is re-checked before use, then its `verified` date is bumped or the note is fixed.
- **Delete** when the source is gone or a repo doc now owns the fact. 
- `inbox/` is for unsorted captures; sort or delete within a week.

## Git
Local git repo, **no remote**, commits straight to `main` (a personal notes repo, nothing to review). Commit after each change with a short message saying what changed; no Co-Authored-By or other attribution. Never add a remote without your OK.

## Reminder
A Stop hook (`~/.claude/hooks/brain-stop.sh`, in ~/.claude/settings.json) asks each session once, after 15+ tool calls, whether it verified something worth a note here. It never loops (skips when a stop hook already continued, and marks the session after asking).

## Weekly upkeep
launchd job `local.brain-check` (`launchd/brain-check.plist` in claude-kit) runs `tools/weekly.sh` at login and hourly; it does the work once per week, at the first chance after Monday 09:00 (`.last-run` holds the week), so a Mac that was off on Monday morning still gets its check: `tools/check.py` finds stale notes for free (older than 90 days, a source file with commits since `verified`, index over budget, dead links); only if it finds any, Sonnet re-checks exactly those and commits. Log: `~/Library/Logs/brain-check.log`. Force one: `echo facts/x.md > ~/brain/.force` then `launchctl kickstart gui/$(id -u)/local.brain-check`.
