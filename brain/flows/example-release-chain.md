---
summary: How a release in the API repo reaches the docs site (example note; replace it)
type: flow
verified: 2026-01-01
source: my-api/.github/workflows/release.yml:12, docs/scripts/sync.mjs
---

## Facts
- A tag in `my-api` runs `release.yml`, which dispatches `sync` in `docs` (my-api/.github/workflows/release.yml:12).
- The docs sync opens a bot PR; it gets no CI until it is reopened.

## How to apply
- After an API release, check the docs bot PR instead of syncing by hand.

## Related
- (links to other notes, as [[flows/name]])
