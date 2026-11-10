#!/bin/bash
# Weekly brain upkeep (launchd: launchd/brain-check.plist).
# 1. tools/check.py finds stale notes for free. 2. Only if it finds any, Sonnet re-checks
# exactly those notes against their sources, fixes or deletes them and commits.
# 3. A macOS notification says what happened. Schedule: login + hourly, once per week (see below). Force a run: BRAIN_FORCE="note path" or a ~/brain/.force file.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"
export BRAIN_MAINT=1   # the stop hook skips maintenance runs
REPOS="${BRAIN_REPOS:-$HOME/code}"   # where your repos live; check.py reads the same variable
cd "$HOME/brain" || exit 1
LOG="$HOME/Library/Logs/brain-check.log"

# Runs at login and hourly; does real work once per ISO week, at the first chance after Monday 09:00
# (shifting the clock back 9 h makes Monday before 09:00 still count as last week). A forced run always goes.
week=$(date -v-9H +%G-W%V)
if [ -z "${BRAIN_FORCE:-}" ] && [ ! -f .force ] && [ "$(cat .last-run 2>/dev/null)" = "$week" ]; then
  exit 0
fi
echo "$week" > .last-run
echo "== $(date '+%F %T')" >>"$LOG"

findings=$(python3 tools/check.py)
force="${BRAIN_FORCE:-}"
[ -f .force ] && force="$force $(cat .force)" && rm -f .force
[ -n "$force" ] && for n in $force; do findings+=$'\n'"$n"$'\t'"forced re-check"; done
findings=$(sed '/^$/d' <<<"$findings")
if [ -z "$findings" ]; then
  echo "clean" >>"$LOG"
  exit 0
fi
echo "$findings" >>"$LOG"
before=$(git rev-parse HEAD)

prompt="You are the weekly upkeep run for ~/brain. Follow ~/brain/RULES.md exactly.
These findings came from tools/check.py (note<TAB>reason):

$findings

For each note listed: read it, then check every claim against its sources (the files under $REPOS, gh for GitHub facts). Only verify what is listed, do not browse further.
- Still true: set verified: to today's date.
- Partly wrong: fix the claims, set verified: to today.
- Source gone or a repo doc now owns it: delete the note.
- index.md findings: fix the index (budget, dead links, missing lines).
Keep index.md in step. Then commit in ~/brain to main with a short message (no attribution trailer).
Never edit anything outside ~/brain. Finish with ONE line: 'Brain: N re-checked, N fixed, N deleted'."

summary=$(printf '%s' "$prompt" | claude -p --model sonnet --add-dir "$REPOS" \
  --allowedTools "Read,Grep,Glob,Edit(~/brain/**),Bash(git:*),Bash(gh:*),Bash(cmp:*),Bash(ls:*),Bash(python3 tools/check.py)" \
  2>>"$LOG" | tail -1)
echo "$summary" >>"$LOG"
[ "$(git rev-parse HEAD)" = "$before" ] && [ -z "$summary" ] && summary="Brain upkeep failed, see ~/Library/Logs/brain-check.log"
osascript -e "display notification \"${summary//\"/}\" with title \"Brain upkeep\"" 2>/dev/null
