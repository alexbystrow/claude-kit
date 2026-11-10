**ABC-265 is in PR #439 and the ticket is In Review. I added the export steps to the existing "Reports" page rather than writing a new guide, as your ticket comment suggested, because the old guide already covered most of the filters and a second page would drift.**

- **New on that page:**
  - which columns an export always contains
  - an export with no gaps: pick the date range first, then the filters, then check the row count
  - steps for when an export is too large
- ⚠️ **The app has no "last exported" field yet:** your comment asked for one. The page tells readers to note the date themselves.
- **Other gaps found in the app and the export service code while checking every claim on the page against the source:**
  - An export's name and filters can't be edited afterwards.
  - Deleting an export is permanent.
  - Old exports stay in the list with no marker, so the page says to put a date in every name.
- ⚠️ **Export timing was overstated:** two pages said "instant". It's usually seconds, but up to a minute for large ranges. I corrected both.
- The getting-started guide said exports had no guide yet; it now links to the new section.
- ✅ The audience test found no wrong facts, and the review loop came back clean after one round. Lint and formatting checks pass; CI runs the build and link check.
- **Left open, listed in the PR:**
  - The export dialog still says "instant".
  - I couldn't confirm which role may delete exports.
- Brain: nothing new.
- https://github.com/example-org/docs/pull/439
