#!/bin/bash
# Claude Code status line: the usual powerline bar (model, 5-hour limit and context as traffic-light meters,
# then when the 5-hour window closes;
# the git branch is on the hint line under the prompt, which the mod shortens)
# in Nord Aurora colours, then the model band under it: the lead, the advisor and a done count. The band comes from the file the model-band mod writes for this session.
export LC_NUMERIC=C
US=$'\x1f'
input=$(cat)

IFS="$US" read -r model sess ctx sid resets < <(printf '%s' "$input" | jq -r '
  def pct: if . == null then "" else tostring end;
  [ (.model.display_name // ""), (.rate_limits.five_hour.used_percentage | pct),
    (.context_window.used_percentage | pct), (.session_id // ""),
    (.rate_limits.five_hour.resets_at | pct) ] | join("\u001f")' 2>/dev/null)

# the band: hidden flag, lead, advisor, done count, then one line per running worker
state_dir="$HOME/.claude/model-band"
find "$state_dir" -name '*.json' -mtime +1 -delete 2>/dev/null
band=0 lead="" adv_calls=0 adv_ms=0 done_n=0
w_model=() w_label=() w_start=() w_steps=()
now_ms=$(( $(date +%s) * 1000 ))
if [ -n "$sid" ] && [ -f "$state_dir/$sid.json" ]; then
  first=1
  while IFS= read -r line; do
    if [ "$first" = 1 ]; then
      first=0
      IFS="$US" read -r hidden lead adv_calls adv_ms done_n <<< "$line"
      [ "$hidden" = 0 ] && band=1
    else
      IFS="$US" read -r _ m l s n <<< "$line"
      w_model+=("$m"); w_label+=("$l"); w_start+=("$s"); w_steps+=("$n")
    fi
  done < <(jq -r --argjson now "$now_ms" '
    def nm: ([capture("(?<n>opus|sonnet|haiku|fable)-(?<a>[0-9]+)-(?<b>[0-9]+)")] | .[0]) as $m
            | if $m then (($m.n[0:1] | ascii_upcase) + $m.n[1:] + " " + $m.a + "." + $m.b) else . end;
    def us: join("\u001f");
    ([ (if ((.hidden // false) or ($now - (.updatedAt // 0) > 900000)) then 1 else 0 end),
       ((.lead.model // "") | nm), (.advisor.calls // 0), (.advisor.ms // 0),
       ([.workers[]? | select(.endedAt == null | not)] | length) ] | us),
    (.workers[]? | select(.endedAt == null) | ["W", (.model | nm), (.label // ""), (.startedAt // 0), (.steps // 0)] | us)
  ' "$state_dir/$sid.json" 2>/dev/null)
fi

SEP=$(printf '\xee\x82\xb0'); START=$(printf '\xee\x82\xba'); END=$(printf '\xee\x82\xb8')

seg_text=(); seg_bg=(); seg_fg=()
add() { seg_text+=("$1"); seg_bg+=("$2"); seg_fg+=("$3"); }
pct() { printf '%.0f' "$1"; }
# a 5-cell gauge: ▰ per filled fifth (rounded, at least one above 0), ▱ for the rest
meter() { local f i out=""; f=$(awk -v p="$1" 'BEGIN { f = int(p * 5 / 100 + 0.5); if (p > 0 && f < 1) f = 1; if (f > 5) f = 5; print f }')
  for ((i = 0; i < 5; i++)); do if (( i < f )); then out+="▰"; else out+="▱"; fi; done; printf '%s' "$out"; }
# traffic light for a usage: its own calm colour ($4 bg, $5 fg) so the two meters stay apart, yellow from $2, red from $3
tone() { awk -v p="$1" -v y="$2" -v r="$3" -v c="$4 $5" 'BEGIN { if (p >= r) print "167 231"; else if (p >= y) print "220 16"; else print c }'; }
usage() { local t; t=($(tone "$1" "$3" "$4" "$5" "$6")); add "$2 $(meter "$1") $(pct "$1")%" "${t[0]}" "${t[1]}"; }
clock() { local s=$(( $1 / 1000 )); [ "$s" -lt 0 ] && s=0; printf '%d:%02d' $(( s / 60 )) $(( s % 60 )); }
# when the 5-hour window closes: the clock time, or "in Nm" in the last hour; nothing once it has passed.
# resets_at is epoch seconds (milliseconds tolerated). Colour runs green to red with the 5h usage ($2).
closes() { local r=${1%.*} left label c; [ -z "$r" ] && return; [ "$r" -gt 100000000000 ] && r=$(( r / 1000 ))
  left=$(( r - $(date +%s) )); [ "$left" -le 0 ] && return
  if [ "$left" -lt 3600 ]; then label="in $(( (left + 59) / 60 ))m"; else label=$(date -r "$r" +%H:%M); fi
  c=($(awk -v p="${2:-0}" 'BEGIN { if (p >= 90) print "167 231"; else if (p >= 75) print "208 16"; else if (p >= 60) print "220 16"; else if (p >= 40) print "148 16"; else print "71 16" }'))
  add "⟳ $label" "${c[0]}" "${c[1]}"; }
short() { local t="$1" max="$2"; if [ "${#t}" -gt "$max" ]; then printf '%s…' "${t:0:$(( max - 1 ))}"; else printf '%s' "$t"; fi; }
emit() {
  local n=${#seg_text[@]} i out
  if [ "$n" -gt 0 ]; then
    out="\033[38;5;${seg_bg[0]}m${START}"
    for ((i = 0; i < n; i++)); do
      out+="\033[48;5;${seg_bg[i]};38;5;${seg_fg[i]}m ${seg_text[i]} "
      if (( i < n - 1 )); then
        out+="\033[38;5;${seg_bg[i]};48;5;${seg_bg[i+1]}m${SEP}"
      else
        out+="\033[0m\033[38;5;${seg_bg[i]}m${END}"
      fi
    done
    printf '%b\033[0m\n' "$out"
  fi
  seg_text=(); seg_bg=(); seg_fg=()
}

# colours are 256-colour codes: red 131, yellow 220, blue 68, teal 73, alert red 167, slate 59; text 231 white, 16 black, 253 light
running=${#w_model[@]}

# row 1: the bar you had. With the band on, its first segment is the lead (♛ Sonnet 5.5) instead of
# "Model: Sonnet 5.5", so the model is never shown twice; idle, the advisor joins the row. The window close is always last.
if [ "$band" = 1 ] && [ -n "$lead" ]; then
  add "♛ $lead" 131 231
elif [ -n "$model" ]; then
  add "Model: $model" 131 231
fi
# usage: the 5-hour rate limit (calm blue, yellow from 70%, red from 90%) and the context window (calm teal, 60%, 80%)
[ -n "$sess" ] && usage "$sess" 5h 70 90 68 231
[ -n "$ctx" ] && usage "$ctx" ctx 60 80 73 16
if [ "$band" = 1 ] && [ "$running" = 0 ]; then
  [ "$adv_calls" -gt 0 ] && add "◆ ×$adv_calls" 220 16
fi
closes "$resets" "$sess"
emit

# while workers run: one row with the advisor (the workers are in the agent panel)
if [ "$band" = 1 ] && [ "$running" -gt 0 ]; then
  [ "$adv_calls" -gt 0 ] && add "◆ advisor ×$adv_calls · $(clock "$adv_ms")" 220 16
  emit
fi

# background jobs (separate Claude sessions, written by bin/job-state.sh): one row each, four at most.
# A finished job's row disappears at once; a row not updated for 2 minutes counts as lost.
jobs_dir="$state_dir/jobs/$sid"
if [ -n "$sid" ] && [ -d "$jobs_dir" ]; then
  n=0
  while IFS="$US" read -r j_label j_model j_status j_start j_upd j_pct j_cost j_note; do
    [ -z "$j_label" ] && continue
    age=$(( now_ms - j_upd ))
    if [ "$j_status" = done ]; then continue; elif [ "$age" -gt 120000 ]; then j_status=lost; fi
    n=$(( n + 1 )); [ "$n" -gt 4 ] && continue
    case "$j_status" in
      working|gate|"asks Claude") sc="71 16" ;; done) sc="59 231" ;; blocked|lost|stuck) sc="167 231" ;; "asks you") sc="214 16" ;; *) sc="220 16" ;;
    esac
    add "⚙ $(short "$j_label" 24)" 97 231
    [ -n "$j_model" ] && add "$j_model" 131 231
    add "$(clock $(( now_ms - j_start )))" 220 16
    sc=($sc); add "$j_status" "${sc[0]}" "${sc[1]}"
    # progress (the job's own estimate): "40 %" and a 5-cell bar; no percentage, no segment
    [ -n "$j_pct" ] && add "$(pct "$j_pct") % $(meter "$j_pct")" 73 16
    # cost so far, dimmed: $0.021 under $1, $1.25 from $1; unknown, no segment
    [ -n "$j_cost" ] && add "$(LC_ALL=C awk -v c="$j_cost" 'BEGIN { printf (c < 1 ? "$%.3f" : "$%.2f"), c }')" 245 59
    [ -n "$j_note" ] && add "$(short "$j_note" 48)" 68 231
    emit
  done < <(for f in "$jobs_dir"/*.json; do [ -f "$f" ] && jq -r '[.label, .model, .status, (.startedAt|tostring), (.updatedAt|tostring), (if .pct == null then "" else (.pct | tostring) end), (if .cost == null then "" else (.cost | tostring) end), (.note // "")] | join("\u001f")' "$f" 2>/dev/null; done)
  [ "$n" -gt 4 ] && { add "+$(( n - 4 )) more jobs" 59 231; emit; }
  find "$jobs_dir" -name '*.json' -mmin +60 -delete 2>/dev/null
fi
exit 0
