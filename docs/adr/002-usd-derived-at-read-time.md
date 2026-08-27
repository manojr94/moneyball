# ADR 002 — USD derived at read time, not stored

**Status:** Accepted (supersedes initial draft that snapshotted `fx_rate` and `usd_amount_cents`)

## Context

Employees are paid in local currency (EUR, JPY, GBP, …). Analytics and compa-ratio require a common unit for cross-country comparison. The first draft snapshotted `fx_rate` and `usd_amount_cents` onto each salary row at insert time.

## Decision

USD is never stored. The `exchange_rates` table is append-only (a correction is a new row with a later `effective_date`, never an update). The query caller supplies an explicit `rate_date`; the conversion is:

```sql
amount_minor_units / subunit_exponent * rate_to_usd
```

where `rate_to_usd` comes from the most recent rate on or before `rate_date`.

`exchange_rates` carries `created_at` but no `updated_at` — the schema makes immutability visible.

## Consequences

**Good:**
- "What was EMEA payroll worth at end-of-quarter rates?" and "what is it worth today?" are both answerable with the same data, by changing `rate_date`.
- No cached copy that drifts from the source of truth.
- Historical reports are reproducible: the same `rate_date` always produces the same USD figures.

**Cost:**
- Every conversion requires a join to `exchange_rates`. In practice this resolves to one rate per currency (a handful of rows joined to the full employee set), not one rate per salary row.
- An employee with no rate on or before `rate_date` is excluded from aggregates and surfaced in `meta.unconvertible_currencies`.

## Why the snapshot was wrong

The snapshot answered "what rate was in effect when we recorded this row" — not "what is this worth at a given date." Managers asking about EMEA spend mean the latter. The snapshot silently blended rates from whenever each row happened to be inserted, making the aggregate number unreproducible and uninterpretable.
