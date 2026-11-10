#!/bin/bash
# Lints every case and compares the rule ids with the expected ones; then feeds the hook bad input. Exit 1 on a mismatch.
cd "$(dirname "$0")" || exit 1
fail=0
expect() { got=$(./reply-lint --check "cases/$1" | cut -d: -f1 | sort -u | tr '\n' ' '); [ "$got" = "$2" ] && echo "ok   $1" || { echo "FAIL $1: got '$got', want '$2'"; fail=1; }; }
expect done-ok.md               "clean "
expect bold-first.md            "bold-first "
expect prose-short.md           "bold-first "
expect done-prose.md            "bold-first narration "
expect bullets.md               "bold-many bullet-long "
expect long.md                  "length "
expect table.md                 "table-wide "
expect table-cell.md            "table-cell-long "
expect two-tables.md            "clean "
expect pipe-in-span.md          "clean "
expect quote.md                 "clean "
expect short.md                 "clean "
expect shell-var.md             "clean "
expect files-not-last.md        "files-not-last "
expect bold-files.md            "files-not-last "
expect takeaway.md              "second-summary "
expect two-layer.md             "bullet-long length second-summary "
expect pr-report-long.md        "bullet-long length pr-report-long "
expect pr-report-ok.md          "clean "
expect icon-other.md            "icon-other "
expect icon-ok.md               "clean "
expect decision-no-q.md         "decision-question "
expect decision-ok.md           "clean "
expect narration.md             "narration "
expect narration2.md            "narration "
expect narration3.md            "narration "
expect no-fp-narration.md       "clean "
expect correction-narration.md  "clean "
expect failure-state.md         "clean "
expect nothing-changed-result.md "clean "
expect your-step-bold.md        "bold-many "
expect money.md                 "money "
expect money-eur.md             "money "
expect money-postfix.md         "money "
expect time-prose.md            "time-form "
expect measured-time.md         "clean "
expect tilde-fence.md           "clean "
expect nested-fence.md          "clean "
expect glob-bold.md             "clean "
# Any example reply fenced in the style must lint clean (v4 has none; older versions had one per shape).
ex=0; awk '/^```$/{f=!f; if(!f) n++; next} f{print > (ENVIRON["TMPDIR"] "/adhd-ex" n ".md")}' n=0 ../../output-styles/adhd.md 2>/dev/null
for f in "${TMPDIR:-/tmp}"/adhd-ex*.md; do [ -s "$f" ] || continue; ex=$((ex+1)); got=$(./reply-lint --check "$f"); [ "$got" = "clean" ] || { echo "FAIL style example $f: $got"; fail=1; }; rm -f "$f"; done
echo "ok   style examples ($ex)"
# Hook robustness: bad input must exit 0 silently, a violation logs only (blocks once with REPLY_LINT_BLOCK=1), a resent reply never blocks.
export REPLY_LINT_DIR=$(mktemp -d)
hook() { printf '%s' "$1" | REPLY_LINT_BLOCK=1 ./reply-lint 2>/dev/null; echo "rc=$?"; }
for bad in '' 'not json' '[1]' 'null' '{"last_assistant_message":["x"]}' '{"transcript_path":"/nonexistent"}' '{"session_id":"../x","last_assistant_message":"- ✅ a\n- ❌ b"}'; do
  r=$(hook "$bad" | tail -1); [ "$r" = "rc=0" ] && echo "ok   hook input ${bad:0:30}" || { echo "FAIL hook input $bad: $r"; fail=1; }
done
[ ! -e "$REPLY_LINT_DIR/x" ] && echo "ok   session id cannot escape the state dir" || { echo "FAIL path escape"; fail=1; }
m='{"session_id":"s1","last_assistant_message":"- ✅ a\n- ❌ b"}'
[ -z "$(printf '%s' "$m" | ./reply-lint)" ] && grep -q '"s1"' "$REPLY_LINT_DIR/log.jsonl" && [ ! -e "$REPLY_LINT_DIR/asked/s1" ] && echo "ok   default is log-only, never blocks" || { echo "FAIL default blocked"; fail=1; }
[ "$(hook "$m" | head -1 | jq -r .decision 2>/dev/null)" = "block" ] && echo "ok   first violation blocks" || { echo "FAIL no block"; fail=1; }
[ "$(hook "$m" | head -1)" = "rc=0" ] && echo "ok   second violation is silent" || { echo "FAIL second violation blocked"; fail=1; }
ro=$(mktemp -d); chmod 500 "$ro"; for i in 1 2; do r=$(printf '%s' "$m" | REPLY_LINT_DIR="$ro/state" ./reply-lint | head -1); [ -z "$r" ] || { echo "FAIL unwritable state blocks"; fail=1; }; done; echo "ok   unwritable state dir never blocks"; chmod 700 "$ro"; rm -rf "$ro"
[ "$(hook '{"session_id":"s2","stop_hook_active":true,"last_assistant_message":"- ✅ a\n- ❌ b"}' | head -1)" = "rc=0" ] && echo "ok   resent reply never blocks" || { echo "FAIL resent"; fail=1; }
printf '\xff\xfe{"type":"assistant"}\n%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"- ✅ a\n- ❌ b"}]}}' > "$REPLY_LINT_DIR/t.jsonl"
tj=$(jq -cn --arg p "$REPLY_LINT_DIR/t.jsonl" '{session_id:"s3",transcript_path:$p}')
[ "$(hook "$tj" | head -1 | jq -r .decision 2>/dev/null)" = "block" ] && echo "ok   non-UTF-8 transcript is read" || { echo "FAIL transcript"; fail=1; }
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"- ✅ a\n- ❌ b"}]}}' > "$REPLY_LINT_DIR/one.jsonl"
oj=$(jq -cn --arg p "$REPLY_LINT_DIR/one.jsonl" '{session_id:"s4",transcript_path:$p}')
[ "$(hook "$oj" | head -1 | jq -r .decision 2>/dev/null)" = "block" ] && echo "ok   one-line transcript is read" || { echo "FAIL one-line transcript"; fail=1; }
rm -rf "$REPLY_LINT_DIR"
exit $fail
