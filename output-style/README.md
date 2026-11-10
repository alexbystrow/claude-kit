# adhd output style

How Claude writes its replies: the answer first in bold, short bullets (aim 15 words, hard limit 25), icons only where they carry meaning (✅ ⚠️ ❌), about 15 lines. It never cuts safety caveats, how to undo a change, or the safer alternative. A second part, the investigation budget, keeps Claude from reading and deliberating more than the answer needs.

`reply-lint/` scores a reply against the style (`reply-lint --check reply.md`, `./test.sh` runs the cases).

## Install

```sh
mkdir -p ~/.claude/output-styles
ln -sfn "$PWD/output-style/adhd.md" ~/.claude/output-styles/adhd.md        # run from the claude-kit checkout
ln -sfn "$PWD/output-style/reply-lint" ~/.claude/reply-lint
```

Then pick it with `/output-style adhd`, or set `"outputStyle": "adhd"` in `~/.claude/settings.json`.
