# Implementation Plan

**Status:** Draft for review · **Prerequisite:** `docs/REQUIREMENTS.md`

This plan sequences v1 into eleven milestones. Each is independently reviewable, leaves
the suite green, and maps to a small cluster of commits. Nothing here is built until the
plan is agreed.

---

## 1. Architecture

```
React SPA (Vite + TypeScript)
        │  JSON over HTTPS, session cookie
        ▼
Rails 7 API-only
  ├── Controllers      thin: params → service/query → serializer
  ├── Services         write-side domain logic (RecordRaise, ImportEmployees)
  ├── Queries          read-side composable objects (EmployeeSearch, PayAnalytics)
  ├── Models           persistence + invariants only
  └── Serializers      explicit JSON shaping
        ▼
PostgreSQL 16
```

**Why service + query objects rather than fat models or fat controllers.** The
interesting logic here is neither CRUD nor presentation — it is *band resolution*,
*FX normalization*, and *point-in-time aggregation*. Isolating those makes them unit
testable without HTTP, and keeps `Employee` from accreting thirty methods. Controllers
stay thin enough to read in one screen.

**Why API-only + SPA rather than Rails views or Hotwire.** The stated stack is React,
and an HTTP boundary forces the API to be an actual contract with request specs — which
is what makes the test suite meaningful.

---

## 2. Data model

```
users            id, email, password_digest, role, name,
                 active, token_version, last_sign_in_at
departments      id, name, slug
pay_zones        id, name, slug
countries        code (PK), name, default_currency, pay_zone_id, region,
                 needs_review
employees        id, employee_number, first_name, last_name, email,
                 country_code, department_id, job_title, job_level,
                 hire_date, status, terminated_on
salaries         id, employee_id, amount_minor_units, currency,
                 effective_date, reason, created_by_id
salary_bands     id, job_title, job_level, pay_zone_id, currency,
                 min_minor_units, mid_minor_units, max_minor_units,
                 effective_from, effective_to
exchange_rates   id, currency, rate_to_usd, effective_date
audit_events     id, actor_id, auditable_type, auditable_id, action,
                 changes (jsonb), note, created_at
```

### Column types worth stating

| Column | Type | Why |
|---|---|---|
| `*_minor_units` | `bigint` | Exact integer arithmetic; `bigint` because minor units of a low-denomination currency overflow `int` at surprisingly ordinary salaries |
| `rate_to_usd` | `numeric(18,8)` | Exact decimal. A float rate compounds error across 10k conversions |
| `effective_date`, `effective_from/to` | `date` | These are business dates, not instants. A timestamp invites timezone bugs in "as of" comparisons |
| `created_at`, `last_sign_in_at` | `timestamptz` | These *are* instants, and must survive a region change |
| `role`, `status`, `region` | Postgres enum | Fixed, small, closed sets — the database should reject a typo, not store it |
| `changes` | `jsonb` | Schema-flexible by design; the audit table must not need a migration when another model gains a column |
| `currency` | `char(3)` | ISO 4217, validated against a known list at the model layer |

### Load-bearing decisions

**Salary is an append-only effective-dated series.** No `salary` column on `employees`.
A raise is an `INSERT`, never an `UPDATE`. Current pay is "the row with the greatest
`effective_date <= today`".

*Trade-off:* every read of "current salary" becomes a per-employee lookup rather than a
column read — a real cost, addressed in §5. We accept it because the alternative loses
history permanently, and history is the product.

**Money as `amount_minor_units` integers + an explicit `currency`.** Never floats.
Rendering and rounding happen at the edge, via `money-rails`.

The column is *not* named `amount_cents`, because "cents" encodes a 1/100 subunit that is
false for part of the data: JPY has no subunit at all (ISO 4217 exponent 0), while KWD,
BHD and JOD use three decimals. A column named `cents` holding a yen amount is ambiguous
to every future reader and silently wrong to any code that assumes it. Minor units are
whatever the currency's exponent says, and `money-rails` knows every exponent — so the
rule is uniform and the library enforces it.

*Trade-off:* raw integers are no longer comparable across currencies without knowing the
exponent. They never truly were; the old name just hid it. Every read and write goes
through the Money type, which is where the exponent lives.

**USD is derived at read time, not stored.** `exchange_rates` is the single source of
truth, and conversion happens in the query with an explicit rate date.

An earlier draft snapshotted `fx_rate` and `usd_amount_cents` onto each salary row. That
was wrong, for a reason worth recording: **nobody is ever paid in USD.** The employee
earns ¥8,000,000; the dollar figure exists only so an HR manager can compare Tokyo to
Berlin. It is a lens over the data, not a fact about a transaction — and derivations
belong in a lookup, not a column.

Snapshotting also answered only half the question. "What did we record then" and "what is
our EMEA payroll worth today" need different rates, and a frozen column silently answers
the first when the manager asked the second — blending rates from whenever each row
happened to be entered. With the rate date as a query parameter, both questions are
answerable and each query states which one it is asking.

*Requires:* `exchange_rates` is **append-only**. Rows are never updated or deleted; a
correction is a new row. That is what makes a historical lookup reproducible, and it is
what removed the need for the snapshot — a frozen copy of a query that always returns the
same answer is pure duplication.

*Trade-off:* a join on every conversion. Cheaper than it sounds: the common case joins to
the latest rate per currency, roughly twenty rows. Per-row historical lookups are rarer
and are what §5's materialized-view path exists for.

**Rate lookup is "most recent on or before", never exact-match.** Rates do not exist for
every date — weekends, holidays, feed gaps. A currency with no rate at all returns an
explicit "cannot convert" rather than a silent null, so a data gap is visible instead of
quietly dropping people from totals.

**Bands are effective-dated too**, for the same reason salaries are — band revisions are
a normal annual event, and compa-ratio history is meaningless if bands mutate in place.

**Bands key on pay zone, not country.** Per-country bands would mean roughly
`countries × levels × titles` rows — thousands at ACME's size — which recreates the
spreadsheet-maintenance problem inside the application. Zones collapse comparable
markets into one band, and a zone holding a single country reproduces per-country
behavior exactly where a market genuinely warrants it. Nothing is lost; the row count
becomes maintainable.

*Trade-off:* resolution gains a hop (employee → country → zone → band) and zone
assignment becomes a judgement HR has to make. Both are cheap next to hand-maintaining
thousands of band rows.

**`countries` is a reference table carrying two independent groupings.** `pay_zone_id`
drives band resolution; `region` drives analytics rollup. They are deliberately separate
fields rather than one hierarchy, because EMEA is a single reporting region spanning
several pay zones — collapsing them would force one of the two to be wrong. `region` is
a column rather than its own table: it is a fixed, short, behaviourless list.

**Bands carry their own currency.** Comp teams set bands in local terms, so a band's
currency is part of its identity. `BandResolver` normalizes both sides to USD at the
same rate date, so the comparison is apples to apples and the currency-mismatch case is
defined behavior rather than an error.

**Geography configures itself; it never blocks data entry.** `region` is seeded for every
ISO 3166 country from the UN geoscheme — public reference data, correct on day one, zero
admin work. Pay zones ship with sensible defaults that HR overrides only where they
disagree.

When an employee is created in a country not yet configured, the app creates the country
row, fills `region` from the seed, defaults `pay_zone_id` to its region's zone, and sets
`needs_review`. **The employee saves.** Configuration is a flag to be resolved later, not
a gate — an HR manager onboarding a new hire must never be stopped by a missing zone
mapping.

**Audit as a single polymorphic table** rather than per-model versioning. One place to
answer "who changed what". `changes` as `jsonb` keeps it schema-flexible.

### Indices, and the query each one serves

An index without a named query is speculation. These exist for specific paths:

| Index | Serves |
|---|---|
| `salaries(employee_id, effective_date DESC)` | "latest salary as of date" — the hottest path in the app |
| `exchange_rates(currency, effective_date DESC)` | as-of rate lookup; load-bearing now that USD is derived |
| `salary_bands(pay_zone_id, job_title, job_level, effective_from DESC)` | band resolution in `BandResolver` |
| `employees(country_code)`, `employees(department_id)` | analytics grouping |
| `employees(status) WHERE status = 'active'` | partial — nearly every query filters to active staff |
| `audit_events(auditable_type, auditable_id, created_at DESC)` | per-record audit trail |
| unique `employees(employee_number)`, unique `users(email)` | identity constraints, enforced in the database |

Foreign-key indices are assumed and not listed.

### Encryption: deliberately not at the column level

Salary data is sensitive, so column-level encryption looks like the obvious control. It
is incompatible with the product: an encrypted column cannot be summed, averaged,
percentile-ranked, range-queried, or usefully indexed. Even deterministic encryption buys
only equality matching. **Encrypting salary amounts and computing compa-ratios are
mutually exclusive**, and analytics is the reason this application exists.

The protection is layered elsewhere: encryption at rest (host-provided), TLS in transit,
authorization enforced in policy objects rather than controllers, and an audit trail on
every write. Recorded here so the absence reads as a decision rather than an oversight.

### Users carry three columns that auth actually needs

`active` — `audit_events` references users, so a user can never be hard-deleted; they are
deactivated.

`token_version` — JWT revocation. Without it, deactivating an HR admin leaves their
existing token valid until it expires, so a "removed" user keeps reading salary data.
Bumping the version invalidates every outstanding token for that user immediately.

`last_sign_in_at` — the first thing anyone asks for in an access review.

Password reset is deliberately absent: it needs email infrastructure, which is a v1
non-goal. Admins set passwords directly.

---

## 3. Milestones

| # | Milestone | Delivers | Key tests |
|---|---|---|---|
| **M0** | Scaffolding & CI | Rails API + Vite app, RSpec, FactoryBot, RuboCop, ESLint, GitHub Actions running both suites | CI green on an empty suite |
| **M1** | Geography, departments & employees | `pay_zones`, `countries` (region seeded from UN geoscheme, zones defaulted), `departments`, `employees`; auto-create unconfigured countries with `needs_review` | Validation positives/negatives, uniqueness, soft-delete via `status`, **employee in an unconfigured country still saves**, country→zone and country→region integrity |
| **M2** | Money & FX | `Money` via `money-rails`, append-only `exchange_rates`, `FxConverter` with as-of lookup | Zero-decimal (JPY) and three-decimal (KWD) currencies, rounding, unknown currency, **no rate on exact date → most recent prior**, no rate at all → explicit failure, zero/negative guards |
| **M3** | Salary history | `salaries`, `RecordSalaryChange` service, `current_salary` / `salary_on(date)` | Point-in-time correctness, same-day supersede, backdated insert, immutability |
| **M4** | Auth & roles | Session auth, `hr_admin` / `viewer`, Pundit-style policies | Viewer blocked from every write path; unauthenticated 401 vs. forbidden 403 |
| **M5** | Employee API | Index with filter/sort/keyset pagination, show, create, update | Filter combinations, empty results, invalid params, pagination boundaries |
| **M6** | Spreadsheet import | CSV/XLSX parse, row validation, dry-run preview, atomic commit | Malformed rows, partial failure → full rollback, duplicate detection, 10k-row import |
| **M7** | Analytics | Headcount, spend, min/median/avg/max grouped by region/country/department/level, point-in-time, **explicit rate date** | Median correctness (even/odd/single), empty groups, mixed currencies, region rollup equals sum of its countries, **same data at two rate dates gives different totals**, historical date |
| **M8** | Bands, compa-ratio & coverage | `salary_bands` (zone-scoped), `BandResolver`, compa-ratio + distribution buckets, **band coverage report** | **No matching band**, country in no pay zone, band currency ≠ salary currency, band changed mid-period, boundary values (exactly min/mid/max), coverage report lists every uncovered title/level/zone |
| **M9** | Frontend | Employee list, detail + salary timeline, raise form, analytics dashboard, band view | Component + interaction tests, loading/error/empty states |
| **M10** | Seed & performance | 10k employees / ~120k salary rows, benchmark harness, index tuning | Documented query timings against the <500ms target |
| **M11** | Deploy & docs | Dockerfile, hosted demo, README with architecture + decisions, ADRs | Smoke test against the deployed instance |

**Sequencing rationale.** M2 and M3 precede everything because the money and history
primitives are what every later feature reads. Auth (M4) lands before the API surface
(M5) so no endpoint is ever written unprotected and retrofitted. Analytics (M7) precedes
bands (M8) because compa-ratio reuses its grouping and filtering layer. The 10k seed
(M10) comes after the query paths exist so benchmarks measure something real.

---

## 4. Test strategy

Positive **and** negative cases at every layer — the negative cases are the ones that
demonstrate the design holds.

- **Models** — invariants, validations, scopes. Cheap, exhaustive.
- **Services / queries** — the real logic. `BandResolver` and `FxConverter` get the
  heaviest coverage because they own the ambiguous cases.
- **Requests** — the API contract: status codes, payload shape, authorization. Every
  write endpoint gets an explicit viewer-is-forbidden spec.
- **Frontend** — Vitest + Testing Library on behavior, not implementation.

**Negative cases treated as first-class**, not an afterthought: employee with no salary
record; salary with no applicable band; band in a currency the salary isn't in;
analytics over an empty group; import where row 9,998 of 10,000 fails; a viewer
attempting every mutation; a raise backdated before hire date.

---

## 5. Performance

The append-only design makes "current salary for 10,000 employees" the hot path. Naively
that is either N+1 or a self-join per row.

**Approach, in order:**

1. **Index** `salaries (employee_id, effective_date DESC)`.
2. **`DISTINCT ON`** — Postgres-specific and index-aligned:
   `SELECT DISTINCT ON (employee_id) * FROM salaries WHERE effective_date <= $1
   ORDER BY employee_id, effective_date DESC`. One pass, no correlated subquery.
3. **Keyset pagination** rather than `OFFSET` — `OFFSET 9000` degrades linearly.
4. **Aggregate in SQL, not Ruby** — `percentile_cont` for median; never load 10k rows to
   average them.
5. **Join rates once, not per row.** Deriving USD means a join, but "current spend"
   resolves to one rate per currency — a CTE of roughly twenty rows joined to the
   employee set, not a lookup per salary. Only point-in-time historical reports need a
   per-row rate, and those are the rarer path.
6. **Measure before optimizing further.** A materialized view or a `current_salary_id`
   cache column is the escape hatch if M10 benchmarks miss the target — but only with
   numbers justifying the added invalidation complexity.

Each is a documented step with a benchmark, not a premature optimization.

---

## 6. Branching & commit conventions

**One branch per milestone, one PR per branch** — twelve in total, matching §3. Each
milestone was scoped to be independently testable and independently valuable, which is
exactly the property that makes a good PR boundary. Branches are named for their
milestone so the sequence is self-evident:

```
feat/m00-tooling      feat/m04-auth          feat/m08-bands
feat/m01-geography    feat/m05-employee-api  feat/m09-frontend
feat/m02-history      feat/m06-import        feat/m10-performance
feat/m03-audit        feat/m07-analytics     feat/m11-deploy
```

**`main` is protected**: no direct pushes, PR with green CI required to merge. The one
exception is M0 itself, which lands before protection is switched on — it is the commit
that *creates* the CI workflow, so it cannot be gated by it. Protection goes on
immediately after M0 merges, and every subsequent milestone passes through it.

**Rebase-and-merge, never squash.** This matters more than it looks. Squash-merging
twelve PRs would collapse the entire build into twelve commits and discard the
incremental history — the thing this repository exists to demonstrate. Rebase-and-merge
keeps every individual commit *and* keeps `main` linear, so `git log` reads as one
continuous narrative while the PR list preserves the milestone grouping.

**Commits** follow Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `refactor:`,
`chore:`), one logical change each, suite green at every commit. Bodies explain *why*
when the reasoning isn't obvious from the diff. Within a milestone the series runs
schema → model → service → endpoint → tests, so each PR reads as a narrative rather
than a dump.

**PR descriptions carry the reasoning**: what changed, what was traded off, what was
deliberately left out. On a solo repository the PR body is where design rationale lives
that would otherwise be lost in a chat log — and it is the first thing a reviewer reads.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| Band resolution ambiguity (no band, unzoned country, currency mismatch) | Rules decided in §2 and encoded as named tests in M8, rather than letting behavior emerge from whatever the query happens to return |
| Pay-zone assignment is a judgement call HR must make | Seed a default zone map and flag unconfigured countries with `needs_review`; never block data entry on it. The M8 coverage report turns setup into a visible, finite task |
| Deriving USD at read time adds a join to every conversion | Cheap in the common case (latest rate per currency, ~20 rows). Historical per-row lookups escalate to the materialized view in §5 |
| An in-place edit to `exchange_rates` would silently rewrite history | Append-only is a stated invariant in `CLAUDE.md`, enforced by model-level guards and covered by a negative test |
| Effective-dated queries slow at 10k | M10 benchmarks with a documented escalation path (§5) |
| Import memory on large files | Stream rows; batch inserts; never load the whole sheet |
| Scope creep into payroll/equity | Non-goals are written down in the requirements; revisit only after v1 ships |

---

## 8. Resolved design questions

| Question | Decision |
|---|---|
| Bands per country or broader? | **Pay zones**, with countries mapped in. A single-country zone reproduces per-country behavior where a market warrants it. |
| Region tier for analytics? | **Yes** — a `region` column on `countries`, not a separate table. |
| Band denomination? | **Local currency per band**, normalized to USD at comparison time. |

No open questions remain against the schema. The next decision point is M0: how the
existing local `backend/` and `frontend/` scaffolding maps onto this plan — audit what
is present and fill gaps, rather than scaffolding over working setup.
