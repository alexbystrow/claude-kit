# Brain

Shared notes that every Claude Code session on your machine reads. Project memory sees one repo; the brain holds what crosses repos or outlives a session: release chains, which service reads which spec, tooling quirks. It is a plain folder of Markdown (works as an Obsidian vault) in a local git repo.

## How it works

- **Read:** `index.md` is imported into every session from `~/.claude/CLAUDE.md`. A note opens only when its index line matches the task.
- **Write:** each note is one topic, every claim dated (`verified:`) and sourced (`source:`). Rules in `RULES.md`.
- **Reminder:** `hooks/brain-stop.sh` (a Stop hook) asks each session once, after 15+ tool calls, whether it verified something worth a note. It never loops.
- **Upkeep:** `tools/check.py` finds stale notes with no model (older than 90 days, a source file changed since `verified`, index over budget, dead links). `tools/weekly.sh` runs it once a week and only then lets Sonnet re-check exactly those notes.

## Install

```sh
mkdir -p ~/brain && cd ~/brain && git init
cp -R /path/to/claude-kit/brain/{RULES.md,index.md,flows,facts,decisions,inbox,tools} .
cp /path/to/claude-kit/brain/vault.gitignore .gitignore
git add -A && git commit -m "Start brain"
cp /path/to/claude-kit/brain/hooks/brain-stop.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/brain-stop.sh
```

Add to `~/.claude/CLAUDE.md`:

```markdown
## Brain (shared notes, ~/brain)
Cross-repo knowledge lives in `~/brain`. Its index is imported below.
- Read: open a note only when its index line matches the task; check its `verified` date and `source` first.
- Write: add or fix a note when you verify a fact that crosses repos and no repo file owns it. Follow `~/brain/RULES.md`, update `index.md` in the same change, commit to `main`.

@~/brain/index.md
```

Add the hook and the folder to `~/.claude/settings.json`:

```json
"permissions": { "additionalDirectories": ["~/brain"] },
"hooks": {
  "Stop": [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/brain-stop.sh" }] }]
}
```

Weekly upkeep (macOS, optional): set `BRAIN_REPOS` to the folder that holds your repos (default `~/code`), replace `/Users/YOU` in `launchd/brain-check.plist`, then:

```sh
cp launchd/brain-check.plist ~/Library/LaunchAgents/local.brain-check.plist
launchctl load ~/Library/LaunchAgents/local.brain-check.plist
```

Needs `jq`, `python3` and the `claude` CLI. The upkeep run calls `claude -p --model sonnet` only when `check.py` finds something.
