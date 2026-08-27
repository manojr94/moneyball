# ADR 003 — Band resolution as an explicit service object

**Status:** Accepted

## Context

Compa-ratio (salary ÷ band midpoint) requires finding the right salary band for an employee. The lookup sounds simple — match on job title, level, and pay zone — but the edge cases are where the interesting logic lives:

- No band exists for this title/level/zone combination
- The employee's country has no pay zone assignment
- The band is denominated in a different currency than the salary
- The applicable band changed between the salary effective date and today

## Decision

Band resolution is encapsulated in `BandResolver`, a service object that takes an employee and a date and returns a `BandResolver::Result` struct:

```ruby
Result = Struct.new(:band, :compa_ratio, :bucket, :reason, keyword_init: true)
# reason: :ok | :no_salary | :unzoned_country | :no_band | :no_rate
```

Each failure mode is a named symbol, not a boolean `resolved?`. Callers (the analytics query, the coverage report) distinguish between failure modes — an unzoned country is a configuration gap, a missing band is a data gap, and the two require different responses in the UI.

Currency mismatches are resolved by normalizing both salary and band midpoint to USD at the same `rate_date` before computing the ratio.

## Consequences

**Good:**
- Every edge case has a name and a test. The behavior cannot accidentally change without a failing spec.
- The coverage report (`GET /analytics/band_coverage`) is a direct query for employees whose `BandResolver` result would be `:no_band` — the logic lives in one place.
- The service is unit-testable without HTTP or database fixtures beyond the minimal records it needs.

**Cost:**
- One `BandResolver` call per employee in the compa-ratio analytics path. The analytics query pre-resolves at the SQL level for bulk aggregation (`CompaRatioAnalytics`), reserving the Ruby service for single-employee display.

## Alternatives considered

**Scope or JOIN in the query** — works for the happy path but makes failure modes implicit (a missing row looks the same as a zero-ratio result). Named reasons require explicit branching that belongs in a service, not a query.
