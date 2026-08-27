# ADR 001 — Effective-dated, append-only salary history

**Status:** Accepted

## Context

ACME manages compensation for ~10,000 employees across multiple countries. HR needs to answer "what was this person paid in Q3 2023?" and produce point-in-time analytics. The naive approach — a mutable `salary` column on the `employees` table — destroys the answer to every historical question the moment someone gets a raise.

## Decision

Compensation is an append-only series of rows in a `salaries` table. Every salary event (new hire, raise, correction, role change) is an `INSERT` with an `effective_date`. No row is ever `UPDATE`d or hard-deleted.

Current salary for an employee is defined as: **the row with the greatest `effective_date ≤ target_date`**.

```sql
SELECT DISTINCT ON (employee_id) *
FROM salaries
WHERE employee_id = $1 AND effective_date <= $2
ORDER BY employee_id, effective_date DESC, id DESC
```

Same-day corrections use `id DESC` as a tiebreaker — the later-inserted row supersedes the earlier one.

## Consequences

**Good:**
- Every point-in-time question is answerable without storing derived data.
- The audit trail is structural, not bolted on — history cannot be rewritten.
- `RecordSalaryChange` is a simple `INSERT`; there is no update/rollback logic.

**Cost:**
- "Current salary for all employees" requires a `DISTINCT ON` query, not a column read. Addressed with an index on `(employee_id, effective_date DESC)` and Postgres's `DISTINCT ON` which uses that index efficiently.
- No deduplication guard for same-date entries. A future UI could surface same-date rows as candidates for review.

## Alternatives considered

**Mutable `salary` column on `employees`** — rejected. Answering historical questions would require a separate audit log, and the audit log would become the source of truth anyway. Better to make the primary table the audit log.

**Event sourcing with a separate audit table** — more complex than needed. The effective-dated series _is_ the event log; a separate audit table would duplicate it.
