#!/bin/bash
# Tests for statusline.sh: feeds sample status-line input and state files, checks the rows.
here=$(cd "$(dirname "$0")" && pwd)
export HOME=$(mktemp -d); mkdir -p "$HOME/.claude/model-band"
fail=0
plain() { sed -E $'s/\x1b\\[[0-9;]*m//g'; }
run() { "$here/statusline.sh" | plain; }
check() { # name, haystack, needle
  if printf '%s' "$2" | grep -qF -- "$3"; then :; else echo "FAIL $1: missing '$3'"; fail=1; fi
}
absent() { if printf '%s' "$2" | grep -qF -- "$3"; then echo "FAIL $1: unexpected '$3'"; fail=1; fi; }
rows() { printf '%s\n' "$1" | grep -c .; }
times() { printf '%s' "$1" | grep -o -F -- "$2" | wc -l | tr -d ' '; }
NOW=$(( $(date +%s) * 1000 ))
input='{"model":{"display_name":"Sonnet 5.5"},"rate_limits":{"five_hour":{"used_percentage":4}},"context_window":{"used_percentage":53},"session_id":"s1","cwd":"/tmp"}'
state() { # hidden updatedAtOffsetMs workersJson
  printf '{"v":1,"sessionId":"s1","updatedAt":%s,"hidden":%s,"lead":{"model":"claude-sonnet-5-5"},"advisor":{"calls":2,"ms":11000},"workers":%s}' "$(( NOW - $2 ))" "$1" "$3" > "$HOME/.claude/model-band/s1.json"
}
W1="{\"model\":\"claude-haiku-5-5\",\"label\":\"fix section filters\",\"startedAt\":$(( NOW - 72000 )),\"steps\":7}"
W2="{\"model\":\"claude-haiku-5-5\",\"label\":\"write the guide\",\"startedAt\":$(( NOW - 31000 )),\"steps\":1}"
D1="{\"model\":\"claude-haiku-5-5\",\"label\":\"old\",\"startedAt\":1,\"endedAt\":2,\"steps\":3}"

state false 1000 "[$W1,$W2,$D1]"; out=$(printf '%s' "$input" | run)
[ "$(rows "$out")" = 2 ] || { echo "FAIL running: expected 2 rows (bar + advisor), got $(rows "$out")"; fail=1; }
check running "$out" "♛ Sonnet 5.5"; check running "$out" "5h ▰▱▱▱▱ 4%"; check running "$out" "ctx ▰▰▰▱▱ 53%"
check running "$out" "◆ advisor ×2 · 0:11"; absent running "$out" "done"
absent running "$out" "Model:"; absent running "$out" "▸"; absent running "$out" "fix section filters"
[ "$(times "$out" "Sonnet 5.5")" = 1 ] || { echo "FAIL running: the model is shown $(times "$out" "Sonnet 5.5") times"; fail=1; }

state false 1000 "[$D1]"; out=$(printf '%s' "$input" | run)
[ "$(rows "$out")" = 1 ] || { echo "FAIL idle: expected 1 row"; fail=1; }
check idle "$out" "♛ Sonnet 5.5"; absent idle "$out" "done"; check idle "$out" "◆ ×2"; absent idle "$out" "▸"; absent idle "$out" "Model:"
[ "$(times "$out" "Sonnet 5.5")" = 1 ] || { echo "FAIL idle: the model is shown $(times "$out" "Sonnet 5.5") times"; fail=1; }

state true 1000 "[$W1]"; out=$(printf '%s' "$input" | run)
[ "$(rows "$out")" = 1 ] || { echo "FAIL hidden: expected 1 row"; fail=1; }
absent hidden "$out" "♛"; check hidden "$out" "Model: Sonnet 5.5"; [ "$(times "$out" "Sonnet 5.5")" = 1 ] || { echo "FAIL hidden: model twice"; fail=1; }

state false 1000000 "[$W1]"; out=$(printf '%s' "$input" | run)   # 1000 s old: stale
[ "$(rows "$out")" = 1 ] || { echo "FAIL stale: expected 1 row"; fail=1; }
absent stale "$out" "♛"

state false 1000 "[$W1]"; out=$(printf '%s' '{"model":{"display_name":"Sonnet 5.5"},"session_id":"other"}' | run)
absent other-session "$out" "♛"; absent other-session "$out" "5h "; check other-session "$out" "Model: Sonnet 5.5"

rm -f "$HOME/.claude/model-band/s1.json"; out=$(printf '%s' "$input" | run)
[ "$(rows "$out")" = 1 ] || { echo "FAIL no state: expected 1 row"; fail=1; }

state false 1000 "[$W1,$W1,$W1,$W1,$W1,$W2]"; out=$(printf '%s' "$input" | run)
[ "$(rows "$out")" = 2 ] || { echo "FAIL many: expected 2 rows"; fail=1; }; absent many "$out" "more workers"

# traffic light: the segment colour follows the usage (green, yellow, red); raw output keeps the colour codes
raw() { printf '%s' "$1" | "$here/statusline.sh"; }
lvl() { printf '{"model":{"display_name":"Sonnet 5.5"},"rate_limits":{"five_hour":{"used_percentage":%s}},"context_window":{"used_percentage":%s},"session_id":"x"}' "$1" "$2"; }
out=$(raw "$(lvl 72 84)")
check tone-5h-yellow "$out" $'48;5;220;38;5;16m 5h ▰▰▰▰▱ 72%'
check tone-ctx-red "$out" $'48;5;167;38;5;231m ctx ▰▰▰▰▱ 84%'
out=$(raw "$(lvl 95 10)")
check tone-5h-red "$out" $'48;5;167;38;5;231m 5h ▰▰▰▰▰ 95%'
check tone-ctx-calm "$out" $'48;5;73;38;5;16m ctx ▰▱▱▱▱ 10%'
out=$(raw "$(lvl 0 60)" | plain)
check zero "$out" "5h ▱▱▱▱▱ 0%"; check tone-5h-calm "$(raw "$(lvl 0 60)")" $'48;5;68;38;5;231m 5h'; check edge "$(raw "$(lvl 0 60)")" $'48;5;220;38;5;16m ctx'

# when the 5-hour window closes: last segment, clock time, "in Nm" in the last hour, gone once passed;
# its colour runs green, lime, yellow, orange, red with the 5h usage
win() { printf '{"model":{"display_name":"Sonnet 5.5"},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s}},"context_window":{"used_percentage":20},"session_id":"x"}' "$1" "$2"; }
T=$(( NOW / 1000 + 8000 )); out=$(raw "$(win 20 $T)")
check close-clock "$(printf '%s' "$out" | plain)" "⟳ $(date -r $T +%H:%M)"
check close-green "$out" $'48;5;71;38;5;16m ⟳ '
case "$(printf '%s' "$out" | plain)" in *"⟳ $(date -r $T +%H:%M) "$'\xee\x82\xb8') ;; *) echo "FAIL close-last: not the last segment"; fail=1 ;; esac
check close-ms "$(raw "$(win 20 $(( T * 1000 )))" | plain)" "⟳ $(date -r $T +%H:%M)"
out=$(raw "$(win 88 $(( NOW / 1000 + 2040 )))"); check close-countdown "$(printf '%s' "$out" | plain)" "⟳ in 34m"; check close-orange "$out" $'48;5;208;38;5;16m ⟳'
check close-lime "$(raw "$(win 45 $T)")" $'48;5;148;38;5;16m ⟳'; check close-yellow "$(raw "$(win 65 $T)")" $'48;5;220;38;5;16m ⟳'
check close-red "$(raw "$(win 95 $T)")" $'48;5;167;38;5;231m ⟳'
absent close-passed "$(raw "$(win 20 $(( NOW / 1000 - 5 )))")" "⟳"; absent close-none "$(raw "$(lvl 20 20)")" "⟳"
state false 1000 "[$D1]"; out=$(printf '{"model":{"display_name":"Sonnet 5.5"},"rate_limits":{"five_hour":{"used_percentage":4,"resets_at":%s}},"session_id":"s1"}' $T | run)
case "$out" in *"◆ ×2 "*" ⟳ "*) ;; *) echo "FAIL close-after-advisor: $out"; fail=1 ;; esac

# the branch is no longer in the status line (the mod puts it on the hint line)
repo="$HOME/repo"; git init -q -b feat/x "$repo"
out=$(raw "{\"model\":{\"display_name\":\"Sonnet 5.5\"},\"context_window\":{\"used_percentage\":11},\"session_id\":\"x\",\"cwd\":\"$repo\"}" | plain)
absent no-branch "$out" "feat/x"; check no-branch "$out" "ctx ▰▱▱▱▱ 11%"

out=$(printf '%s' 'not json' | run); [ -z "$out" ] || { echo "FAIL garbage: expected no output"; fail=1; }
out=$(printf '%s' '{}' | run); [ -z "$out" ] || { echo "FAIL empty: expected no output"; fail=1; }

[ "$fail" = 0 ] && echo "statusline: all checks passed"
exit $fail
