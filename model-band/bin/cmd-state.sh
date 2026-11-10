#!/bin/bash
# A band row for a plain background command (no Claude session): one row while PID runs.
#   cmd-state.sh <lead-session-id> <slug> <label> <pid> [log-file] [pct]
# pct (optional): a whole number 0-100, or a file whose last "NN%" (or bare number) is the progress.
# The note is the log's last non-empty line. The row goes when the process ends, or
# however this script ends. Prints "<label>: finished" at the end (for a Monitor).
lead="$1" slug="$2" label="$3" pid="$4" log="${5:-}" pctsrc="${6:-}"
dir="$HOME/.claude/model-band/jobs/$lead"; mkdir -p "$dir"; f="$dir/$slug.json"
trap 'rm -f "$f" "$f.tmp"' EXIT
started=$(( $(date +%s) * 1000 ))
while kill -0 "$pid" 2>/dev/null; do
  note=""; [ -n "$log" ] && [ -f "$log" ] && note=$(grep -v '^[[:space:]]*$' "$log" | tail -n 1 | sed -E 's/^[0-9]{9,} //; s/^ *[✓●!] *//' | cut -c1-80)
  pct=""
  if [ -n "$pctsrc" ]; then
    if [ -f "$pctsrc" ]; then pct=$(tail -n 20 "$pctsrc" | grep -oE '[0-9]{1,3} ?%?' | tail -n 1 | tr -d ' %'); else pct=${pctsrc%\%}; fi
    case "$pct" in ''|*[!0-9]*) pct="" ;; *) [ "$pct" -gt 100 ] && pct=100 ;; esac
  fi
  jq -n --arg l "$label" --arg n "$note" --arg p "$pct" --argjson t "$started" --argjson u "$(( $(date +%s) * 1000 ))" \
    '{label:$l, model:"bash", status:"working", note:$n, startedAt:$t, updatedAt:$u} + (if $p == "" then {} else {pct: ($p|tonumber)} end)' > "$f.tmp" && mv "$f.tmp" "$f"
  sleep 5
done
echo "$label: finished"
