#!/bin/bash
# Stop hook: once per session, after real work, ask Claude whether it verified a
# cross-repo fact worth keeping in ~/brain. Never loops: it skips when a stop hook
# already continued this turn, and leaves a per-session marker after asking once.
input=$(cat)
[ -n "$BRAIN_MAINT" ] && exit 0
[ "$(jq -r '.stop_hook_active // false' <<<"$input")" = "true" ] && exit 0
sid=$(jq -r '.session_id // empty' <<<"$input")
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
[ -z "$sid" ] || [ ! -f "$transcript" ] && exit 0
marker="${TMPDIR:-/tmp}/claude-brain-stop/$sid"
[ -e "$marker" ] && exit 0
# Real work = at least 15 tool calls in this session.
uses=$(grep -o '"type":"tool_use"' "$transcript" | wc -l | tr -d ' ')
[ "$uses" -lt 15 ] && exit 0
mkdir -p "$(dirname "$marker")" && touch "$marker"
# additionalContext, not decision:block: same continuation, shown as "Stop hook feedback"
# in the transcript instead of a "Stop hook error" banner (hooks docs, 2026-11-10).
jq -n '{hookSpecificOutput: {hookEventName: "Stop", additionalContext: "Brain check (asked once per session): did this session verify a fact that crosses repos or outlives the session, which no repo file owns? If yes, add or update a note in ~/brain following ~/brain/RULES.md (update index.md, commit to main) and say so in one line. If no, or you already did, end the turn without any text and without tool calls."}}'
