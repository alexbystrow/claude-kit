#!/bin/bash
# Agent panel rows (the subagent status line). Claude Code sends all visible rows as JSON on stdin and
# takes one {"id","content"} line back per row to override. Each row is powerline segments in the status
# line's colours, one colour per fact: model (red), description (purple), time (yellow), steps (green)
# and tokens (blue; for a Haiku worker amber from 60k and red from 80k, against the 100k rule).
# A step is one model response; the steps are joined from the file the model-band mod writes.
export LC_NUMERIC=C
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)
state="$HOME/.claude/model-band/$sid.json"
now_ms=$(( $(date +%s) * 1000 ))

printf '%s' "$input" | jq -c --slurpfile st <( [ -n "$sid" ] && [ -f "$state" ] && cat "$state" || echo '{}' ) --argjson now "$now_ms" '
  def nm: ([capture("(?<n>opus|sonnet|haiku|fable)-(?<a>[0-9]+)-(?<b>[0-9]+)")] | .[0]) as $m
          | if $m then (($m.n[0:1] | ascii_upcase) + $m.n[1:] + " " + $m.a + "." + $m.b) else . end;
  def esc: "\u001b";
  def paint($s): esc + "[48;5;\($s.bg);38;5;\($s.fg)m";
  def arrow($from; $to): esc + "[38;5;\($from);48;5;\($to)m";
  def end_($from): esc + "[0m" + esc + "[38;5;\($from)m" + esc + "[0m";
  def render($segs): ($segs | length) as $n
    | [ range(0; $n) as $i | $segs[$i] as $s
        | paint($s) + " " + $s.t + " "
          + (if $i < $n - 1 then arrow($s.bg; $segs[$i + 1].bg) else end_($s.bg) end) ]
    | add;
  def clock($ms): (($ms / 1000 | floor) | if . < 0 then 0 else . end) as $s
                  | "\($s / 60 | floor):\(($s % 60) | tostring | if length < 2 then "0" + . else . end)";
  def k($n): if $n >= 1000 then "\((($n / 100) | floor) / 10)k" else "\($n)" end;
  (.columns // 100) as $cols
  | ($st[0].workers // []) as $known
  | .tasks[]?
  | . as $t
  | ($known | map(select(.id == $t.id)) | .[0].steps // null) as $steps
  | ([8, ($cols - 70)] | max) as $room
  | ($t.model // "") as $mid
  | ($mid | nm) as $model
  | ($t.tokenCount // 0) as $tok
  | (if ($mid | test("haiku")) then (if $tok >= 80000 then {bg: 131, fg: 231} elif $tok >= 60000 then {bg: 172, fg: 16} else {bg: 68, fg: 231} end)
     else {bg: 68, fg: 231} end) as $tokcol
  | (if $t.status == "running" then {bg: 131, fg: 231, t: ("▸ " + (if $model == "" then ($t.agentType // "worker") else $model end))}
     else {bg: 59, fg: 253, t: ("✗ " + (if $model == "" then ($t.agentType // "worker") else $model end))} end) as $first
  | ([ $first,
       {bg: 139, fg: 16, t: (($t.label // $t.description // "")[0:$room])} ]
     + (if $t.status == "running" then [] else [{bg: 131, fg: 231, t: $t.status}] end)
     + [ {bg: 220, fg: 16, t: clock($now - $t.startTime)} ]
     + (if $steps then [{bg: 108, fg: 16, t: "\($steps) step\(if $steps == 1 then "" else "s" end)"}] else [] end)
     + [ ($tokcol + {t: ("↓ " + k($tok))}) ]) as $segs
  | { id: $t.id, content: render($segs) }
' 2>/dev/null
exit 0
