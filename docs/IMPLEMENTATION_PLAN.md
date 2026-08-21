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
users            id, email, password_digest, role, name
departments      id, name, slug
employees        id, employee_number, first_name, last_name, email,
                 country_code, department_id, job_title, job_level,
                 hire_date, status, terminated_on
salaries         id, employee_id, amount_cents, currency, effective_date,
                 usd_amount_cents, fx_rate, reason, created_by_id
salary_bands     id, job_title, job_level, country_code, currency,
                 min_cents, mid_cents, max_cents, effective_from, effective_to
exchange_rates   id, currency, rate_to_usd, effective_date
audit_events     id, actor_id, auditable_type, auditable_id, action,
                 changes (jsonb), note, created_at
```

### Load-bearing decisions

**Salary is an append-only effective-dated series.** No `salary` column on `employees`.
A raise is an `INSERT`, never an `UPDATE`. Current pay is "the row with the greatest
`effective_date <= today`".

*Trade-off:* every read of "current salary" becomes a per-employee lookup rather than a
column read — a real cost, addressed in §5. We accept it because the alternative loses
history permanently, and history is the product.

**Money as `amount_cents` integers + an explicit `currency`.** Never floats. Rendering
and rounding happen at the edge.

**FX rate snapshotted onto each salary row.** `usd_amount_cents` and `fx_rate` are
computed once at write time from `exchange_rates` and then frozen.

*Trade-off:* denormalized and technically stale. But converting at read time means last
quarter's report changes every time rates move, which makes reports untrustworthy and
un-reproducible. Frozen rates are auditable; live conversion is not.

**Bands are effective-dated too**, for the same reason salaries are — band revisions are
a normal annual event, and compa-ratio history is meaningless if bands mutate in place.

**Audit as a single polymorphic table** rather than per-model versioning. One place to
answer "who changed what". `changes` as `jsonb` keeps it schema-flexible.

---

## 3. Milestones

| # | Milestone | Delivers | Key tests |
|---|---|---|---|
| **M0** | Scaffolding & CI | Rails API + Vite app, RSpec, FactoryBot, RuboCop, ESLint, GitHub Actions running both suites | CI green on an empty suite |
| **M1** | Employees & departments | Migrations, models, validations, factories | Validation positives/negatives, uniqueness, soft-delete via `status` |
| **M2** | Money & FX | `Money` value object, `exchange_rates`, `FxConverter` | Rounding, unknown currency, missing rate, zero/negative guards |
| **M3** | Salary history | `salaries`, `RecordSalaryChange` service, `current_salary` / `salary_on(date)` | Point-in-time correctness, same-day supersede, backdated insert, immutability |
| **M4** | Auth & roles | Session auth, `hr_admin` / `viewer`, Pundit-style policies | Viewer blocked from every write path; unauthenticated 401 vs. forbidden 403 |
| **M5** | Employee API | Index with filter/sort/keyset pagination, show, create, update | Filter combinations, empty results, invalid params, pagination boundaries |
| **M6** | Spreadsheet import | CSV/XLSX parse, row validation, dry-run preview, atomic commit | Malformed rows, partial failure → full rollback, duplicate detection, 10k-row import |
| **M7** | Analytics | Headcount, spend, min/median/avg/max grouped by country/department/level, point-in-time | Median correctness (even/odd/single), empty groups, mixed currencies, historical date |
| **M8** | Bands & compa-ratio | `salary_bands`, `BandResolver`, compa-ratio + distribution buckets | **No matching band**, band/salary currency mismatch, band changed mid-period, boundary values (exactly min/mid/max) |
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
5. **Measure before optimizing further.** A materialized view or a `current_salary_id`
   cache column is the escape hatch if M10 benchmarks miss the target — but only with
   numbers justifying the added invalidation complexity.

Each is a documented step with a benchmark, not a premature optimization.

---

## 6. Commit conventions

Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`), one
logical change per commit, suite green at every commit. Bodies explain *why* when the
reasoning isn't obvious from the diff. Each milestone is a small reviewable series —
schema, then model, then service, then endpoint, then tests — so the history reads as a
narrative rather than a dump.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| Band resolution ambiguity (no band, currency mismatch) | Decide rules explicitly in M8 and encode them in named tests rather than letting behavior emerge |
| Effective-dated queries slow at 10k | M10 benchmarks with a documented escalation path (§5) |
| Import memory on large files | Stream rows; batch inserts; never load the whole sheet |
| Scope creep into payroll/equity | Non-goals are written down in the requirements; revisit only after v1 ships |

---

## 8. Open questions blocking the schema

1. Bands per **country**, or per **geographic zone**? (Assumed per-country — sets the
   `salary_bands` uniqueness constraint.)
2. Does analytics need a **region tier** above country? (Assumed no — adding it later
   means a `regions` table and a backfill.)
