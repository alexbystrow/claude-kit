#!/usr/bin/env python3
"""Find brain notes that need a re-check. No model, no network, no writes.

A note is stale when its `verified` date is more than 90 days old, or when a file
named in its `source:` line has commits after that date (local HEAD; nothing is
fetched). Also checks the index budget and dead [[links]].
Prints one line per finding ("<note>\t<reason>") and exits 1 when there are any.
"""
import os
import re
import subprocess
import sys
from datetime import date, timedelta
from pathlib import Path

BRAIN = Path(os.environ.get('BRAIN_DIR', Path.home() / 'brain'))
REPOS = Path(os.path.expanduser(os.environ.get('BRAIN_REPOS', '~/code')))  # where your repos live
MAX_AGE = timedelta(days=90)
INDEX_LINES, INDEX_BYTES = 60, 8192

findings = []


def front(text):
    m = re.match(r'---\n(.*?)\n---\n', text, re.S)
    out = {}
    for line in (m.group(1).splitlines() if m else []):
        k, _, v = line.partition(':')
        out[k.strip()] = v.strip()
    return out


def resolve(token):
    """A source token like `my-api/x.yml:12` or `~/code/web/y.ts` -> (repo dir, file) or None."""
    token = re.sub(r':[\d,-]+$', '', token)
    p = Path(os.path.expanduser(token)) if token.startswith('~') else REPOS / token
    if not p.exists():
        return None
    try:
        top = subprocess.run(['git', '-C', str(p.parent if p.is_file() else p), 'rev-parse', '--show-toplevel'],
                             capture_output=True, text=True, check=True).stdout.strip()
    except subprocess.CalledProcessError:
        return None
    return top, str(p)


def changed_since(top, path, day):
    out = subprocess.run(['git', '-C', top, 'log', '--oneline', f'--after={day} 23:59:59', '--', path],
                         capture_output=True, text=True).stdout.strip()
    return len(out.splitlines()) if out else 0


notes = sorted(p for p in BRAIN.rglob('*.md') if p.parent != BRAIN and p.name != 'index.md' and 'inbox' not in p.parts and 'tools' not in p.parts)
names = {str(p.relative_to(BRAIN))[:-3] for p in notes}
today = date.today()

for p in notes:
    rel = str(p.relative_to(BRAIN))
    fm = front(p.read_text())
    try:
        v = date.fromisoformat(fm.get('verified', ''))
    except ValueError:
        findings.append((rel, 'no valid verified: date'))
        continue
    if today - v > MAX_AGE:
        findings.append((rel, f'verified {v}, older than 90 days'))
    for token in re.findall(r'[~\w./-]+\.(?:md|mjs|js|ts|yml|yaml|json|php|sh)(?::[\d,-]+)?', fm.get('source', '')):
        hit = resolve(token)
        if hit and (n := changed_since(*hit, v)):
            findings.append((rel, f'{token}: {n} commit(s) since {v}'))

index = (BRAIN / 'index.md').read_text()
# section indexes (facts/index.md, ...) count as listing their notes; only the main index has the budget
listing = index + ''.join(p.read_text() for p in BRAIN.glob('*/index.md'))
if len(index.splitlines()) > INDEX_LINES or len(index.encode()) > INDEX_BYTES:
    findings.append(('index.md', f'over budget: {len(index.splitlines())} lines, {len(index.encode())} bytes'))
for link in re.findall(r'\[\[([^\]|#]+)', listing + ''.join(p.read_text() for p in notes)):
    if link not in names and not (BRAIN / (link + '.md')).exists():
        findings.append(('index.md', f'dead link [[{link}]]'))
for n in names:
    if f'[[{n}]]' not in listing:
        findings.append((n + '.md', 'not listed in index.md'))

for note, why in dict.fromkeys(findings):
    print(f'{note}\t{why}')
sys.exit(1 if findings else 0)
