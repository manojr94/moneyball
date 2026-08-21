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
pay_zones        id, name, slug
countries        code (PK), name, default_currency, pay_zone_id, region
employees        id, employee_number, first_name, last_name, email,
                 country_code, department_id, job_title, job_level,
                 hire_date, status, terminated_on
salaries         id, employee_id, amount_cents, currency, effective_date,
                 usd_amount_cents, fx_rate, reason, created_by_id
salary_bands     id, job_title, job_level, pay_zone_id, currency,
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
currency is part of its identity. `BandResolver` normalizes both sides to USD at
evaluation time using the salary's snapshotted rate, so the comparison is apples to
apples and the currency-mismatch case is defined behavior rather than an error.

**Audit as a single polymorphic table** rather than per-model versioning. One place to
answer "who changed what". `changes` as `jsonb` keeps it schema-flexible.

---

## 3. Milestones

| # | Milestone | Delivers | Key tests |
|---|---|---|---|
| **M0** | Scaffolding & CI | Rails API + Vite app, RSpec, FactoryBot, RuboCop, ESLint, GitHub Actions running both suites | CI green on an empty suite |
| **M1** | Geography, departments & employees | `pay_zones`, `countries` (seeded with zone + region), `departments`, `employees`; models, validations, factories | Validation positives/negatives, uniqueness, soft-delete via `status`, country→zone and country→region integrity |
| **M2** | Money & FX | `Money` value object, `exchange_rates`, `FxConverter` | Rounding, unknown currency, missing rate, zero/negative guards |
| **M3** | Salary history | `salaries`, `RecordSalaryChange` service, `current_salary` / `salary_on(date)` | Point-in-time correctness, same-day supersede, backdated insert, immutability |
| **M4** | Auth & roles | Session auth, `hr_admin` / `viewer`, Pundit-style policies | Viewer blocked from every write path; unauthenticated 401 vs. forbidden 403 |
| **M5** | Employee API | Index with filter/sort/keyset pagination, show, create, update | Filter combinations, empty results, invalid params, pagination boundaries |
| **M6** | Spreadsheet import | CSV/XLSX parse, row validation, dry-run preview, atomic commit | Malformed rows, partial failure → full rollback, duplicate detection, 10k-row import |
| **M7** | Analytics | Headcount, spend, min/median/avg/max grouped by region/country/department/level, point-in-time | Median correctness (even/odd/single), empty groups, mixed currencies, region rollup equals sum of its countries, historical date |
| **M8** | Bands & compa-ratio | `salary_bands` (zone-scoped), `BandResolver`, compa-ratio + distribution buckets | **No matching band**, country in no pay zone, band currency ≠ salary currency, band changed mid-period, boundary values (exactly min/mid/max) |
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
| Pay-zone assignment is a judgement call HR must make | Seed a sensible default zone map; expose zone on the country so it is visible and correctable rather than hidden in a migration |
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
