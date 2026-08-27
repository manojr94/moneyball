# ADR 005 — Keyset pagination over OFFSET

**Status:** Accepted

## Context

The employee list supports sorting by multiple columns across ~10,000 rows. `OFFSET N` requires the database to scan and discard N rows on every page request — `OFFSET 9000` on a 10k table scans 9,000 rows to return 25. Performance degrades linearly with page depth.

## Decision

Pagination uses a keyset cursor: an opaque, base64-encoded JSON blob containing the last-seen sort value and `id`. The next-page query becomes:

```sql
WHERE (sort_col > ?) OR (sort_col = ? AND employees.id > ?)
```

This is an indexed range scan regardless of page depth. The cursor is opaque to callers — format can change without a client-side migration.

The OR-expanded form is used instead of Postgres row-value syntax `(sort_col, id) > (?, ?)`. Both are semantically equivalent and index-eligible; the OR form is explicit in `EXPLAIN` output and avoids ORM type-casting ambiguity on `date` columns.

`id` as tiebreaker guarantees a stable sort when the primary sort column has duplicates.

## Consequences

**Good:**
- Page-N performance is identical to page-1 performance regardless of N.
- No "total pages" count needed — the API returns `next_cursor: null` when the last page is reached.

**Cost:**
- Cursors are forward-only — no "jump to page 47." Acceptable: random-access pagination on an employee list is not a real use case.
- Sort direction must be consistent: a cursor encodes a position in a specific sort order. Changing sort column resets to page 1 (correct behavior; implemented in the frontend).
- Bidirectional pagination (previous page) requires storing the cursor stack on the client. The frontend maintains a `cursors[]` array for this.

## Alternatives considered

**OFFSET pagination** — simple to implement, breaks at scale. Rejected from the start given the 10k-employee requirement.

**Relay-style cursor with total count** — adds a `COUNT(*)` query per page; expensive on large tables and unnecessary when total count is not surfaced in the UI.
