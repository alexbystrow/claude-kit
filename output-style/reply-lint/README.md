# reply-lint

Checks Claude's last chat reply against the `adhd` output style (`../adhd.md`). The style is
only an instruction ("nothing enforces it", Claude Code docs), so this Stop hook makes the misses visible. Python 3,
no dependencies.

- **Not registered as a hook any more (2026-11-04).** A Stop hook runs after the reply is on screen: it can't
  replace it, a block only makes Claude send a second copy below. Stdin hook mode still works (log to
  `~/.local/state/reply-lint/log.jsonl`, `REPLY_LINT_BLOCK=1` to block once per session), for a one-off measurement.
- **`reply-lint --report [days]`:** replies and violations per rule over the last N days (default 7).
- **`reply-lint --check FILE`:** the main use: score a test reply (A/B runs of style drafts); `./test.sh` runs the cases in `cases/`.

Rules follow v10.3 (2026-11-09). Rules checked (a code block counts as one line; `>` quotes and code spans are exempt,
so quoting a past reply or a UI label is fine):

| Rule | Fires when |
|---|---|
| `bold-first` | the first line is not bold (a reply that opens with a code block or quote is exempt) |
| `length` | more than 15 non-empty lines |
| `pr-report-long` | a reply with a GitHub PR link and more than 5 top-level bullets (v10.2) |
| `bullet-long` / `bold-many` | a bullet over 25 words / with 2+ bold phrases (`**Your step:**` counts as the one) |
| `table-wide` / `table-cell-long` | a table over 4 columns or 8 data rows / a cell over 12 words |
| `icon-other` | an emoji other than ✅ ⚠️ ❌ (✓ ✔ ✗ ✘ and arrows are text) |
| `second-summary` | a Takeaway, TL;DR, Summary or `---` + Full detail layer |
| `decision-question` | "I recommend N" with no line ending in `?` after it |
| `files-not-last` | any line after `Files:` (also `**Files:**`) |
| `narration` | process phrases: "I read it back", "I changed nothing", "I only fetched", "Let me" …; skipped on ❌/⚠️ lines, which state what a failure left |
| `money` / `time-form` | a €, £, USD, EUR or GBP figure, or $ with 2+ digits or a decimal (`$2` shell args pass) / an estimate like "which takes about 2 minutes" instead of `(~2 min)` (measured durations pass) |

Not linted (needs judgement): whether an icon carries meaning, one idea per bullet, the "every" list shape.

The hook never fails a session: bad JSON, a missing transcript, non-UTF-8 bytes or an unwritable state dir exit
quietly. It reads only the transcript's last 4 MB, sanitises the session id it uses as a file name, never blocks a
re-sent reply (`stop_hook_active`) but still logs it, and `--report` skips those re-sends. It claims the session's one
ask atomically (`asked/<session>`) before blocking, so an unwritable state dir never blocks at all. `test.sh` also
lints any example reply fenced in the style, which must stay clean.

Thresholds equal the style's targets (15 lines, 25 words) since 2026-11-09: the looser 20/30 let 2 of 7 over-long
replies through in a session review. Was registered in `~/.claude/settings.json` under `hooks.Stop` until 2026-11-04.
