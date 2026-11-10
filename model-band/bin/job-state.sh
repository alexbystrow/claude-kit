#!/bin/bash
# Keeps one background job ("⚙ job · …", a separate Claude session) visible in the model band of the lead session.
# Run by the lead as a Monitor:
#   job-state.sh <lead-session-id> <slug> <label> <model> <job-session-name> [progress-file]
# Every 15 s it writes ~/.claude/model-band/jobs/<lead-session-id>/<slug>.json (label, model, startedAt,
# status from `claude agents --json`, last progress line, pct from the newest "[NN%]" report in progress.md, cost from jobs.json), which bin/statusline.sh draws as a row.
# Prints one line per change (status or new report) for the Monitor. When the job session ends it deletes the
# row's file (the row disappears from the band at once), prints that, and exits.
lead="$1" slug="$2" label="$3" model="$4" name="$5" progress="${6:-}"
dir="$HOME/.claude/model-band/jobs/$lead"; mkdir -p "$dir"; f="$dir/$slug.json"
started=$(( $(date +%s) * 1000 )); prev="" prev_note="" seen=0 waited=0
[ -f "$f" ] && started=$(jq -r '.startedAt // empty' "$f" 2>/dev/null || echo "$started")
trap 'rm -f "$f" "$f.tmp"' EXIT   # however this script ends (job over, killed, Monitor stopped), its row goes
jobs_json="${JOBS_DIR:-$HOME/.local/state/claude-jobs}/jobs.json"
write() { jq -n --arg l "$label" --arg m "$model" --arg s "$1" --arg n "$2" --arg p "$3" --arg c "$4" --argjson t "$started" \
  --argjson u "$(( $(date +%s) * 1000 ))" '{label:$l, model:$m, status:$s, note:$n, startedAt:$t, updatedAt:$u} + (if $p == "" then {} else {pct: ($p|tonumber)} end) + (if $c == "" then {} else {cost: ($c|tonumber)} end)' > "$f.tmp" && mv "$f.tmp" "$f"; }
while true; do
  st=$(claude agents --json 2>/dev/null | jq -r --arg n "$name" '[.[] | select(.name == $n)][0] | if . == null then "" else (if .state == "blocked" then "blocked" elif .status == "busy" then "working" else (.state // .status) end) end')
  note="" pct=""
  # the job's cost so far (jobs.json .jobs[<slug>].costNow, USD); none known, no field
  cost=$(jq -r --arg s "$slug" '.jobs[$s].costNow // empty | select(type == "number")' "$jobs_json" 2>/dev/null)
  # what the job tool knows beats "working": a question waiting for you, a hung session, a running gate
  # a job's question goes to the lead ("asks Claude"); only what the lead forwarded is yours ("asks you")
  jst=$(jq -r --arg s "$slug" '.jobs[$s] | if . == null then "" elif .forOwner then "asks you" elif .blocked then "asks Claude" elif .stuck then "stuck" elif .status == "checking" then "gate" else "" end' "$jobs_json" 2>/dev/null)
  jq_q=$(jq -r --arg s "$slug" '.jobs[$s] | (.forOwner.why // .blocked) // empty' "$jobs_json" 2>/dev/null)
  if [ -n "$progress" ] && [ -f "$progress" ]; then
    note=$(tail -n 1 "$progress" | sed -E 's/^[0-9-]+ [0-9:]+ //; s/^\[[0-9]{1,3}%\] ?//')
    # the percentage of the newest report that carries one ("<time> [40%] text" in progress.md)
    pct=$(grep -oE '^[0-9-]+ [0-9:]+ \[[0-9]{1,3}%\]' "$progress" | tail -n 1 | grep -oE '[0-9]{1,3}%' | tr -d '%')
    [ -n "$pct" ] && [ "$pct" -gt 100 ] && pct=100
  fi
  # a just-started session takes a few seconds to show in `claude agents`: wait up to 60 s for it
  if [ -z "$st" ] && [ "$seen" = 0 ] && [ "$waited" -lt 60 ]; then waited=$(( waited + 5 )); sleep 5; continue; fi
  if [ -z "$st" ]; then rm -f "$f"; echo "$label: finished"; exit 0; fi
  seen=1
  [ -n "$jst" ] && st=$jst
  [ -n "$jq_q" ] && note="asks: $jq_q"
  write "$st" "$note" "$pct" "$cost"
  [ "$st" != "$prev" ] && echo "$label: $st"
  [ -n "$note" ] && [ "$note" != "$prev_note" ] && [ -n "$prev_note$prev" ] && echo "$label report: $note"
  prev=$st prev_note=$note
  sleep 15
done
