#!/bin/bash
# Tests for subagent-row.sh with a real captured row input (fixtures/row-sample.json).
here=$(cd "$(dirname "$0")" && pwd)
export HOME=$(mktemp -d); mkdir -p "$HOME/.claude/model-band"
fail=0
plain() { sed -E $'s/\x1b\\[[0-9;]*m//g'; }
check() { if printf '%s' "$2" | grep -qF -- "$3"; then :; else echo "FAIL $1: missing '$3' in: $2"; fail=1; fi; }
NOW=$(( $(date +%s) * 1000 ))
sample=$(cat "$here/fixtures/row-sample.json")
sid=$(printf '%s' "$sample" | jq -r .session_id)
mk() { printf '%s' "$sample" | jq -c --argjson now "$NOW" --arg st "$1" --argjson tok "$2" '.tasks[0].startTime = ($now - 72000) | .tasks[0].status = $st | .tasks[0].tokenCount = $tok'; }

# 1. a running Haiku worker at 63,957 tokens: red model, purple description, yellow time, green steps, amber tokens
printf '{"v":1,"workers":[{"id":"a8c7106d18faf07e5","steps":7}]}' > "$HOME/.claude/model-band/$sid.json"
out=$(mk running 63957 | "$here/subagent-row.sh")
[ "$(printf '%s\n' "$out" | grep -c .)" = 1 ] || { echo "FAIL running: expected 1 line"; fail=1; }
printf '%s' "$out" | jq -e '.id == "a8c7106d18faf07e5" and (.content | type == "string")' >/dev/null || { echo "FAIL running: not an {id,content} line"; fail=1; }
raw=$(printf '%s' "$out" | jq -r .content); txt=$(printf '%s' "$raw" | plain)
check running "$txt" "▸ Haiku 5.5"; check running "$txt" "Docs survey"; check running "$txt" "1:1"; check running "$txt" "7 steps"; check running "$txt" "↓ 63.9k"
for c in '48;5;131;38;5;231m ▸ Haiku' '48;5;139;38;5;16m Docs' '48;5;220;38;5;16m 1:' '48;5;108;38;5;16m 7 steps' '48;5;172;38;5;16m ↓ 63.9k'; do
  printf '%s' "$raw" | grep -qF $'\x1b['"$c" || { echo "FAIL running: missing colour/segment '$c'"; fail=1; }
done

# 1b. the token segment by size: Haiku under 60k blue, from 80k red; a non-Haiku model stays blue
tokcode() { mk running "$1" | jq -c "${2:-.}" | "$here/subagent-row.sh" | jq -r .content | grep -o $'\x1b\[48;5;[0-9]*;38;5;[0-9]*m ↓' | grep -o '48;5;[0-9]*'; }
[ "$(tokcode 22400)" = "48;5;68" ] || { echo "FAIL tokens 22.4k should be blue"; fail=1; }
[ "$(tokcode 88100)" = "48;5;131" ] || { echo "FAIL tokens 88.1k should be red"; fail=1; }
[ "$(tokcode 88100 '.tasks[0].model = "claude-opus-5-5"')" = "48;5;68" ] || { echo "FAIL opus tokens should stay blue"; fail=1; }

# 2. no state file: no steps segment, still a row
rm -f "$HOME/.claude/model-band/$sid.json"
txt=$(mk running 500 | "$here/subagent-row.sh" | jq -r .content | plain)
check nostate "$txt" "Haiku 5.5"; check nostate "$txt" "↓ 500"
if printf '%s' "$txt" | grep -q "step"; then echo "FAIL nostate: unexpected steps"; fail=1; fi

# 3. a failed worker is marked and says so in red
txt=$(mk failed 1200 | "$here/subagent-row.sh" | jq -r .content | plain); check failed "$txt" "✗ Haiku 5.5"; check failed "$txt" "failed"; check failed "$txt" "↓ 1.2k"
mk failed 1200 | "$here/subagent-row.sh" | jq -r .content | grep -qF $'\x1b[48;5;131;38;5;231m failed' || { echo "FAIL failed: status not red"; fail=1; }

# 4. no tasks, garbage, empty: no output and exit 0
out=$(printf '{"tasks":[],"session_id":"x"}' | "$here/subagent-row.sh"); [ -z "$out" ] || { echo "FAIL empty tasks"; fail=1; }
out=$(printf 'not json' | "$here/subagent-row.sh"); [ $? = 0 ] && [ -z "$out" ] || { echo "FAIL garbage"; fail=1; }

# 5. a long label is cut to the row width
long=$(mk running 5 | jq -c '.columns = 80 | .tasks[0].label = "a very very long label that goes on and on and on and on and on and on"')
txt=$(printf '%s' "$long" | "$here/subagent-row.sh" | jq -r .content | plain)
if printf '%s' "$txt" | grep -qF "on and on and on and on and on and on"; then echo "FAIL long label not cut"; fail=1; fi

[ "$fail" = 0 ] && echo "subagent-row: all checks passed"
exit $fail
