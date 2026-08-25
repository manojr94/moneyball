# Manual Test Plan

Automated specs verify what we thought to specify. This plan targets what they
structurally cannot catch:

- **Unspecified behavior** — cases nobody wrote a requirement for, so no test exists.
- **Cross-feature interaction** — each milestone passes alone; the seams between them are
  untested.
- **Plausible-but-wrong output** — a compa-ratio of `0.0` is a passing number and a broken
  feature. Only a human notices the figure is absurd.
- **Realistic scale** — everything works at 10 rows. The product is 10,000.
- **Workflow friction** — whether an HR manager can actually get the job done.

## How to use this

Run the relevant section at the end of each milestone, and the whole thing before deploy
(M11). Record findings as GitHub issues labelled `manual-qa`, referencing the check number
— an issue is the durable artifact; a fixed check leaves no trace otherwise.

A check that passes but *felt* wrong is worth an issue too. "Technically correct, but I
had to think about it" is the most common real defect in this kind of tool.

## Seed data you need

Before most sections, ensure the demo data contains:

- An employee paid in **JPY** (zero-decimal currency) and one in **KWD** (three decimals)
- A country in a pay zone, and one deliberately **not** configured
- A job title/level combination with **no band**
- An employee with **three salary records** across different years
- An employee paid **far above** their band max, and one **far below** min
- A **terminated** employee
- At least one country whose **band currency differs** from the salary currency

If any of these are missing, the interesting paths are untested regardless of how many
checks you tick.

---

## M1. Geography, departments & employees (model/seed layer)

M1 has no API surface yet — manual checks target the database and seed output.
Run `bin/rails db:seed` before these checks.

| # | Check | Catches |
|---|---|---|
| M1.1 | Run `bin/rails db:seed` on a fresh database — does it complete without error? | Seed referencing a pay zone or country before it exists |
| M1.2 | In `psql`, check `SELECT count(*) FROM countries` — is it ≥ 50? Do all four regions appear? | Seed data truncated or region column left blank |
| M1.3 | Check that every country row has a non-null `pay_zone_id` and `needs_review = false` | Default zone assignment failing silently |
| M1.4 | In Rails console: `Employee.create!(employee_number: 'T001', first_name: 'A', last_name: 'B', email: 't@t.com', country_code: 'XX', department: Department.first, job_title: 'X', job_level: 'L1', hire_date: Date.today)` — does the save succeed and does `Country.find('XX').needs_review` return `true`? | The invariant: data entry never blocked by missing config |
| M1.5 | Run `bin/rails db:seed` a second time — does it stay idempotent (no duplicate-key errors)? | `find_or_create_by!` vs. `create!` — re-seeding a live database must be safe |

---

## 1. Money representation

The minor-units decision fails visibly here or nowhere.

| # | Check | Catches |
|---|---|---|
| 1.1 | Enter a JPY salary of 8,000,000. Does it display as **¥8,000,000** and not ¥80,000? | Exponent-0 currency treated as if it had cents |
| 1.2 | Enter a KWD salary with three decimals. Round-trips exactly? | Exponent-3 truncation |
| 1.3 | Enter `8,000,000` with commas, and `8 000 000` with spaces | Parser rejecting realistic human input |
| 1.4 | Enter a very large IDR figure (500,000,000) | `bigint` handling, display truncation |
| 1.5 | Enter `0`, a negative, and a non-numeric value | Guard behavior, and whether the error is *readable* |
| 1.6 | Save a salary, reload the page, compare to what you typed | Round-trip precision loss |

## M4. Auth & roles (API surface: `POST /session`, `DELETE /session`, `GET /me`)

Run `bin/rails s` before these checks. Use `curl` or a REST client.

| # | Check | Catches |
|---|---|---|
| M4.1 | `POST /session` with valid `email` and `password` — does it return 201 with a `token` field and a `user` object containing `email`, `name`, and `role`? | Sign-in not returning a usable token |
| M4.2 | `POST /session` with a wrong password — does it return 401? Does the error NOT reveal whether the email exists? | Credential enumeration via distinct error messages |
| M4.3 | `GET /me` with no `Authorization` header — does it return 401? | Missing-token guard not firing |
| M4.4 | `GET /me` with `Authorization: Bearer <valid token>` — does it return 200 with the correct user details? | Token not decoded or user not found |
| M4.5 | `DELETE /session` with a valid token — does it return 200? Then retry `GET /me` with the same token — does it now return 401? | `invalidate_tokens!` not bumping `token_version`, or version not checked on decode |
| M4.6 | Sign in as a viewer, copy the token. In the console, deactivate the user (`User.find_by(email: '...').deactivate!`). Retry `GET /me` with the old token — does it return 401? | `active` flag checked independently of `token_version` |
| M4.7 | Sign in as a viewer. `POST /probes/write` (test env only) or wait for M5 write endpoints — does it return 403? | Viewer not blocked by `authorize!(:write)` |
| M4.8 | Sign in as an hr_admin. `POST /probes/write` — does it return 200? | hr_admin incorrectly blocked |

---

## M5. Employee API (`GET /employees`, `GET /employees/:id`, `POST /employees`, `PATCH /employees/:id`)

Run `bin/rails s` before these checks. Use `curl` or a REST client with the token from M4.1.

| # | Check | Catches |
|---|---|---|
| M5.1 | `GET /employees` with no `Authorization` header — does it return 401? | Auth guard not applied to index |
| M5.2 | `GET /employees` as viewer — does it return 200 with a `data` array and a `meta` object containing `per_page` and `next_cursor`? | Basic index response shape |
| M5.3 | `GET /employees?status=active` as viewer — do all returned employees have `status: "active"`? | Status filter not applied |
| M5.4 | `GET /employees?status=bogus` — does it return 422 with an error message naming the valid statuses? | Invalid filter accepted silently |
| M5.5 | `GET /employees?per_page=3` — does `data` have 3 items and `next_cursor` a non-null value (assuming > 3 employees exist)? | Pagination not limiting results |
| M5.6 | Follow the cursor from M5.5: `GET /employees?per_page=3&cursor=<value>` — is the next page disjoint from the first (no shared IDs)? | Cursor producing duplicates or skipping records |
| M5.7 | Walk all pages with `per_page=5` until `next_cursor` is null. Does the total count match `Employee.count`? | Records dropped or duplicated across pages |
| M5.8 | `GET /employees?per_page=9999` — does `meta.per_page` cap at 100? | per_page clamping not enforced |
| M5.9 | `GET /employees?sort=last_name` — are employees returned in ascending last_name order? | Sort param ignored |
| M5.10 | `GET /employees/:id` as viewer for a valid id — 200 with the right employee? As viewer for id 0 — 404? | Show not finding the right record; missing not-found guard |
| M5.11 | `POST /employees` as viewer — does it return 403? | Write path not protected |
| M5.12 | `POST /employees` as hr_admin with all required fields — does it return 201 with the new employee, including a `department` object? | Create not persisting or not returning the right shape |
| M5.13 | `POST /employees` as hr_admin with `country_code: "ZZ"` (no country row) — does it return 201 and does `Country.find("ZZ").needs_review` return `true`? | Auto-create invariant not applied on API path |
| M5.14 | `POST /employees` as hr_admin omitting `last_name` — 422 with errors array? | Missing field validation not surfaced |
| M5.15 | `PATCH /employees/:id` as viewer — 403? | Write guard on update |
| M5.16 | `PATCH /employees/:id` as hr_admin with `{ "employee": { "job_title": "Director" } }` — 200 with updated `job_title`? Does the DB row match? | Partial update not applied |
| M5.17 | `PATCH /employees/:id` as hr_admin with `{ "employee": { "status": "terminated", "terminated_on": "2024-12-31" } }` — 200 with both fields updated? | Termination update path |
| M5.18 | `PATCH /employees/:id` as hr_admin with `{ "employee": { "terminated_on": "2024-12-31" } }` (no status change) — 422 with a validation error? | Cross-field validation not enforced via API |

---

## M3. Salary history (model/service layer — console checks, no API yet)

M3 has no API surface. Manual checks verify the invariants at the Rails console.
Run `bin/rails c` and source an employee as `e = Employee.first` (or create one).

| # | Check | Catches |
|---|---|---|
| M3.1 | `RecordSalaryChange.call(employee: e, amount_minor_units: 8_000_00, currency: 'USD', effective_date: 1.year.ago.to_date, reason: 'new_hire', created_by_id: 1)` — does it return a persisted Salary? | Service raising unexpectedly on valid input |
| M3.2 | `RecordSalaryChange.call(employee: e, amount_minor_units: 9_000_00, currency: 'USD', effective_date: 3.months.ago.to_date, reason: 'merit', created_by_id: 1)` then `e.salary_on(6.months.ago.to_date)` — does it return the first (lower) salary? | Point-in-time lookup returning wrong row |
| M3.3 | `e.current_salary` — does it return the second (higher) salary? | `current_salary` not delegating to `salary_on(Date.current)` |
| M3.4 | `e.salary_on(2.years.ago.to_date)` — does it return `nil`? | Pre-history returning the earliest row instead of nil |
| M3.5 | `e.salaries.last.update!(amount_minor_units: 1)` — does it raise `ActiveRecord::RecordNotSaved`? | Immutability guard not firing |
| M3.6 | `e.salaries.last.destroy!` — does it raise `ActiveRecord::RecordNotDestroyed`? | Destroy guard not firing |
| M3.7 | `RecordSalaryChange.call(employee: e, amount_minor_units: 0, currency: 'USD', effective_date: Date.today, reason: 'merit', created_by_id: 1)` — does it raise `RecordSalaryChange::Error` mentioning "greater than 0"? | Zero-amount guard; no silent zero-salary record persisted |
| M3.8 | Same as M3.7 but with `currency: 'XYZ'` — does the error mention "currency"? | Unknown-currency guard |
| M3.9 | Insert two salaries on the same date: call M3.1 again with the same `effective_date`. `e.salary_on(that_date)` — does it return the **later-inserted** row (higher id)? | Same-day tiebreaker determinism |
| M3.10 | `Salary.where(id: Salary.last.id).update_all(amount_minor_units: 1)` — confirm it **succeeds** (callback bypass). Use `Salary.last.id` not `e.salaries.last.id` — the association cache retains unsaved records from failed service calls with `id: nil`, producing a false zero-row result. This is a documented gap: no application code takes this path, but a future data migration could. | Known scope of the immutability guard — callbacks only, not DB-level |

## 2. Effective dating

The load-bearing design decision, and the easiest to get subtly wrong.

| # | Check | Catches |
|---|---|---|
| 2.1 | Add a raise effective **next month**. Does "current salary" still show the old figure? | Future-dated records leaking into current |
| 2.2 | Add a raise effective **before** an existing record. Does history reorder correctly? | Insert-in-the-middle ordering |
| 2.3 | Add two records with the **same effective date**. Which wins? Is it stable across reloads? | Non-deterministic tie-breaking |
| 2.4 | Salary effective **before** the employee's hire date | Missing cross-field validation |
| 2.5 | View an employee's history — is it obvious which row is current? | Presentation of the core concept |
| 2.6 | Does a **terminated** employee still appear in current spend? | Status filtering in aggregates |

## 3. FX and rate dates

| # | Check | Catches |
|---|---|---|
| 3.0a | In the Rails console: `FxConverter.convert(amount_minor_units: 100, from_currency: 'GBP', as_of: Date.today)` with no GBP rate seeded — does it raise `FxConverter::NoRateError` with a message naming the currency and date? | Service returning nil/0 instead of an explicit error; callers silently dropping employees from totals |
| 3.0b | In the Rails console: attempt `ExchangeRate.last.update!(rate_to_usd: 99)` and `ExchangeRate.last.destroy!` — do both raise? Then attempt `ExchangeRate.where(id: ExchangeRate.last.id).update_all(rate_to_usd: 99)` — confirm it succeeds (this bypass is documented and has no application path, but should be known) | Append-only guard scope — callbacks block ORM mutations; SQL-level bypass is a known gap |
| 3.1 | Run analytics at two different rate dates. Do the totals actually differ? | Rate date ignored — silently pinned to latest |
| 3.2 | Run a report dated **before any exchange rate exists** | Undefined behavior at the boundary |
| 3.3 | A currency with **no rate at all** — does the UI say "cannot convert", or show blank/0? | Silent exclusion from totals, which understates spend |
| 3.4 | Add a rate, re-run yesterday's report. Did it change? | Append-only violated, or lookup using the wrong date |
| 3.5 | Try editing an existing `exchange_rates` row through any available path | The append-only invariant actually holding |

## 4. Bands and compa-ratio

| # | Check | Catches |
|---|---|---|
| 4.1 | Employee in a country with **no pay zone** | Blank vs. error vs. crash |
| 4.2 | Title/level with **no band** — what does the profile show? | Missing-data presentation |
| 4.3 | Salary exactly at band **min**, **mid**, and **max** | Boundary bucketing (is min "below" or "within"?) |
| 4.4 | Band in EUR, salary in CHF — is the ratio plausible? | Currency normalization in the comparison |
| 4.5 | Someone paid **3× band max**. Is the ratio flagged, or just printed? | Absurd values presented as normal |
| 4.6 | Change a band, then recheck affected compa-ratios | Stale caching |
| 4.7 | Does the **coverage report** list every uncovered title/level/zone? Add a new title and recheck | Coverage report drifting from reality |

## 5. Import

The highest-risk surface — it writes in bulk.

| # | Check | Catches |
|---|---|---|
| 5.1 | 10,000-row file with **one bad row**. All-or-nothing, or 9,999 committed? | Transactional boundary — the spec says atomic |
| 5.2 | Import the **same file twice** | Duplicate detection |
| 5.3 | CSV exported from **Excel** (BOM, CRLF, quoted fields) | Encoding assumptions |
| 5.4 | Columns in a **different order**; **extra** columns present | Positional vs. named parsing |
| 5.5 | **Empty** file; **header-only** file | Degenerate inputs |
| 5.6 | Does the **dry-run preview** match what actually commits? | Preview/commit divergence — the worst failure here |
| 5.7 | Import a country not yet configured | Auto-create + `needs_review`, without blocking |

---

## M6. Spreadsheet import API (`POST /imports/employees`)

Run `bin/rails s` and obtain an hr_admin token via `POST /session`.
Write a small CSV to `/tmp/import.csv` for the multipart checks — see
`docs/CONTEXT.md` under "M6 decisions" for the schema.

| # | Check | Catches |
|---|---|---|
| M6.1 | `POST /imports/employees` with no `Authorization` header — 401? | Auth guard on import endpoint |
| M6.2 | As viewer, `POST /imports/employees` with a valid `csv` param — 403? | Write guard applied to import |
| M6.3 | As hr_admin, `POST /imports/employees` with no `file` or `csv` param — 422 with an error naming `file is required`? | Missing-input guard |
| M6.4 | As hr_admin, `POST /imports/employees -F file=@/tmp/import.csv` (multipart) with a valid one-row file — 200 with `dry_run: true`, `committed: false`, `summary.rows_valid: 1`? Confirm `Employee.count` is unchanged. | Dry-run default; nothing persisted; multipart upload works |
| M6.5 | Same request but with `-F dry_run=false` — 201 with `committed: true`, `summary.employees_created: 1`? Confirm `Employee.count` incremented. | Commit path; explicit dry_run=false flips to write mode |
| M6.6 | As hr_admin, POST a CSV where row 2 has a blank `first_name` and `dry_run=false` — 422 with `committed: false`, `errors[0].row == 2`, and `Employee.count` unchanged? | Atomic rollback surfaced correctly at the HTTP layer |
| M6.7 | As hr_admin, POST a CSV missing the `email` column — 422 with `header_error` naming `email`, no rows processed? | Header validation runs before row processing |
| M6.8 | Import a 10,000-row generated CSV (`bin/rails runner script/gen_import_csv.rb > /tmp/big.csv`). Time the request. Is it under 120 seconds? Does it stay under 500 MB RSS? *M10 will re-tighten this to <30s once stream + batch inserts land — see `docs/CONTEXT.md` under "M6 post-review fixes." Today's baseline is ~115s at ~11 ms/row.* | Regression guard on the current baseline; the aspirational target belongs to M10 |
| M6.9 | Import a CSV whose `salary_amount` cell is quoted with commas (`"80,000.00"`) — does the salary land as expected minor units? | Excel-formatted number pass-through (the actual export format HR sends) |
| M6.10 | Import a valid file, then import the exact same file again — first: 201; second: 422 with all rows flagged duplicate `has already been taken`? | Idempotency guard — a re-run is not a silent double-insert |

**Note.** Manual checks 5.1–5.7 above are largely covered by automated specs in
`spec/services/import_employees_spec.rb` (atomicity, dry-run parity, BOM/CRLF,
column order, extra columns, empty/header-only, duplicate detection,
unconfigured country auto-create). They are proposed for removal in the M6 PR
body — kept above until the PR is merged so the reviewer can trace what moved.

---

## M7. Analytics API (`GET /analytics/pay`)

Run `bin/rails s` and obtain a viewer token via `POST /session`. Use `curl` or a
REST client. Requires seeded employees, salaries, and exchange rates — a fresh
`bin/rails db:seed` is enough.

| # | Check | Catches |
|---|---|---|
| M7.1 | `GET /analytics/pay?group_by=region` with no `Authorization` header — 401? | Auth guard on analytics endpoint |
| M7.2 | As viewer, `GET /analytics/pay?group_by=region` — 200 with `groups[]` and `meta` (`as_of`, `rate_date`, `group_by`, `unconvertible_currencies`)? | Viewer read allowed; response shape |
| M7.3 | As viewer, `GET /analytics/pay?group_by=planet` — 422 with an error naming the allowed values? | Unknown `group_by` accepted silently |
| M7.4 | As viewer, `GET /analytics/pay?group_by=region&as_of=nope` — 422 with an error naming `as_of`? Same for `rate_date=nope`. | Malformed date accepted or crashing |
| M7.5 | As viewer, `GET /analytics/pay?group_by=region&region=antarctica` — 422? | Region allowlist not enforced |
| M7.6 | As viewer, `GET /analytics/pay?group_by=country&region=emea` — do all returned `key` values belong to countries in EMEA? | Filter not applied at the SQL level |
| M7.7 | As viewer, `GET /analytics/pay?group_by=region&as_of=2000-01-01` — 200 with empty `groups[]` (nobody hired yet)? | Historical date crashing or returning phantom rows |
| M7.8 | Add a salary in a currency with no exchange rate (`XCD`, say). Re-run M7.2 — does the group total exclude that employee **and** does `meta.unconvertible_currencies` include `"XCD"`? | Silent inclusion of unconvertible rows, or the meta hint missing |
| M7.9 | Compare the sum of `total_spend_usd_minor_units` across `group_by=country` versus the single row for `group_by=region` (filtered to that region). Do they match? | Rollup arithmetic drift between grouping levels |
| M7.10 | Run `group_by=region` twice: once with `rate_date=2024-01-01`, once with `rate_date=2024-06-01` (after seeding a rate change). Do EMEA totals differ? | `rate_date` param silently ignored |
| M7.11 | In `psql`, pick a department with ~5 employees. Compute their median USD-converted salary by hand and compare to `GET /analytics/pay?group_by=department`'s `median_usd_minor_units` for that department. | `percentile_cont` misuse or rounding drift |
| M7.12 | `GET /analytics/pay?group_by=department` — does each row's `label` show the department name (not the id)? Same for `group_by=country` (country name, not code). | Label lookup returning the raw key |

---

## M8. Bands, compa-ratio & coverage (`GET /salary_bands`, `POST /salary_bands`, `GET /analytics/compa_ratio`, `GET /analytics/band_coverage`)

Run `bin/rails s` and `bin/rails db:seed` before these checks. Obtain an hr_admin token
via `POST /session` and a viewer token from the same endpoint with a viewer account.

| # | Check | Catches |
|---|---|---|
| M8.1 | `GET /salary_bands` with no `Authorization` — 401? | Auth guard on bands endpoint |
| M8.2 | `GET /salary_bands` as viewer — 200 with an array of bands including `pay_zone_name`? | Viewer read allowed; response shape |
| M8.3 | `GET /salary_bands?job_title=Engineer&job_level=L3` — does the result contain only L3 Engineer bands? | Filter applied |
| M8.4 | `POST /salary_bands` as viewer — 403? | Write guard on bands |
| M8.5 | `POST /salary_bands` as hr_admin with valid JSON — 201 with the new band? | Create path |
| M8.6 | `POST /salary_bands` again with the same `(pay_zone_id, job_title, job_level, effective_from)` — 422? | Idempotency guard |
| M8.7 | `POST /salary_bands` with `max_minor_units < min_minor_units` — 422 with an error mentioning `min`? | Ordering validation |
| M8.8 | After creating a new band for an existing (zone, title, level), check that the previous band now has `effective_to` set. | Auto-close logic |
| M8.9 | `GET /analytics/compa_ratio` with no token — 401? | Auth guard |
| M8.10 | As viewer, `GET /analytics/compa_ratio?group_by=region` — 200 with `groups[]` and `meta` containing `as_of`, `rate_date`, `group_by`, `unconvertible_currencies`, `uncovered_combinations`? | Response shape |
| M8.11 | Each group row has `key`, `label`, `headcount`, `covered_headcount`, `avg_compa_ratio` (4dp string or null), `below`, `within`, `above`, `unresolved`? | Row shape |
| M8.12 | An employee whose salary currency has no rate — is the employee excluded and the currency listed in `meta.unconvertible_currencies`? | Missing-rate surfaced |
| M8.13 | An employee in a country with no pay zone — is `unresolved` incremented (not a crash)? | Unzoned graceful handling |
| M8.14 | `GET /analytics/band_coverage` with no token — 401? | Auth guard |
| M8.15 | As viewer, `GET /analytics/band_coverage` — 200 with `{ uncovered: [...], unzoned: [...] }`? | Response shape |
| M8.16 | After seeding, is at least one entry in `uncovered` (Designer L4 has no band in seed data)? | Coverage report non-empty |
| M8.17 | Does `unzoned` list employees whose country has no pay zone? | Unzoned surface |
| M8.18 | Create a band for an uncovered combination; re-run coverage — does the row disappear? | Coverage report reflects reality |

**Proposed automated checks for removal in this PR:**
- §4 checks 4.1–4.7 are now covered by automated specs:
  - 4.1 (unzoned country) → `spec/services/band_resolver_spec.rb` `:unzoned_country` describe
  - 4.2 (no band) → `spec/services/band_resolver_spec.rb` `:no_band` describe
  - 4.3 (boundary values at min/mid/max) → `spec/services/band_resolver_spec.rb` `bucket boundary values` describe
  - 4.4 (band currency ≠ salary currency) → `spec/services/band_resolver_spec.rb` `band currency differs` describe
  - 4.5 (far above/below) → `spec/services/band_resolver_spec.rb` boundary `:above`/`:below` checks
  - 4.6 (band changed mid-period) → `spec/models/salary_band_spec.rb` + `band_resolver_spec.rb`
  - 4.7 (coverage report accuracy) → `spec/requests/band_coverage_spec.rb` `contain_exactly` check
  These are proposed for removal in the PR body, not deleted here.

**Note.** Manual checks 7.1, 7.2, 7.3, 7.5, 7.6, 7.7, and 7.11 (median-by-hand) from
§7 above are now covered by automated specs in
`spec/queries/pay_analytics_spec.rb` (region rollup = sum of countries;
per-country sum matches total; median for odd/even/single groups; empty
groups; per-country headcount matches employee list; point-in-time date before
any hire). Proposed for removal in the M7 PR body — kept above until the PR is
merged so the reviewer can trace what moved.

---

## 6. Authorization

Test the API directly, not just the UI. A hidden button is not access control.

| # | Check | Catches |
|---|---|---|
| 6.1 | As **Viewer**, confirm edit controls are absent from the UI | Presentation layer |
| 6.2 | As **Viewer**, call a write endpoint directly (curl/devtools). Does it 403? | Authorization enforced server-side |
| 6.3 | **Deactivate** a user while they have an active session. Next request? | `token_version` revocation actually working |
| 6.4 | Log in as Viewer, copy the token, deactivate, retry with the old token | Revocation vs. mere expiry |
| 6.5 | Access an employee record by guessing its ID as Viewer | Object-level authorization |
| 6.6 | Log out — is the token unusable afterwards? | Session termination |

## 7. Analytics arithmetic

Verify the numbers, not just that numbers appear.

| # | Check | Catches |
|---|---|---|
| 7.1 | Sum per-country spend. Does it equal total spend? | Rows dropped by a join |
| 7.2 | Sum per-region. Equal to total, and to the sum of its countries? | Rollup double-counting or omission |
| 7.3 | Take a department of ~5 people; compute median **by hand** and compare | `percentile_cont` misuse |
| 7.4 | Filter to one department; does headcount match the employee list? | Filter divergence between views |
| 7.5 | A group with **zero** employees — blank, zero, or error? | Empty-group handling |
| 7.6 | A group with exactly **one** employee — is median = that salary? | Degenerate median |
| 7.7 | Point-in-time report for a date before anyone was hired | Empty historical window |

## 8. Scale

Run against the full 10,000-employee seed, not a subset.

| # | Check | Catches |
|---|---|---|
| 8.1 | Employee list — load time, pagination beyond page 100 | Keyset pagination actually in use |
| 8.2 | Analytics across all 10k, grouped by country | The N+1 the design was built to avoid |
| 8.3 | Import 10k rows — wall-clock time, memory | Streaming vs. loading the sheet |
| 8.4 | Compa-ratio across all 10k | Per-row band resolution |
| 8.5 | Two browser tabs running heavy reports simultaneously | Connection pool exhaustion |

## M9. Frontend

The SPA runs on `:5173` against the API on `:3000`. Start both servers before testing.

### M9.1 Authentication

| # | Check | What to look for |
|---|---|---|
| M9.1 | Sign in as admin → redirected to employee list | URL changes, nav shows user name |
| M9.2 | Sign in as viewer → employee list loads | No "Record salary change" button visible |
| M9.3 | Invalid credentials → error shown | Error message appears without full-page reload |
| M9.4 | Sign out → redirected to login | Cannot navigate to /employees without re-logging in |
| M9.5 | Access /employees directly without token → redirected to /login | |

### M9.2 Employee list

| # | Check | What to look for |
|---|---|---|
| M9.6 | Employee list loads with active filter by default | Table renders, spinner disappears |
| M9.7 | Switch filter to "All statuses" → terminated employees appear | Status badges show correct color |
| M9.8 | Change sort to "Hire date" → order changes | List reloads, visually confirms new order |
| M9.9 | Next page button advances to next page | Page counter increments, different employees shown |
| M9.10 | Previous button is disabled on page 1 | Confirm it is greyed out |
| M9.11 | Click an employee number → navigate to detail page | URL changes to /employees/:id |
| M9.12 | Empty result (filter matching no one) → empty state message shown | Not a blank screen |

### M9.3 Employee detail & salary timeline

| # | Check | What to look for |
|---|---|---|
| M9.13 | Detail page shows name, department, title, level, country, status | All fields populated |
| M9.14 | Salary timeline shows all records newest-first | Most recent row is visually distinguished |
| M9.15 | Employee with no salary → "No salary records" empty state | Not a crash or blank |
| M9.16 | Breadcrumb link returns to employee list | No full reload |

### M9.4 Raise form (admin only)

| # | Check | What to look for |
|---|---|---|
| M9.17 | "Record salary change" button appears for admin | Button visible in page header |
| M9.18 | Button absent for viewer | No button in DOM |
| M9.19 | Fill form → submit → new row appears in timeline | Salary count increases, new date at top |
| M9.20 | Submit with empty amount → HTML5 required validation fires | Form does not submit |
| M9.21 | Submit with invalid currency (e.g. "XY") → error shown from API | Error message rendered |
| M9.22 | Cancel button closes form without saving | Timeline unchanged |

### M9.5 Analytics dashboard

| # | Check | What to look for |
|---|---|---|
| M9.23 | Pay tab loads by region on default date | Table shows NA/LATAM/EMEA/APAC rows |
| M9.24 | Switch group-by to Department → table refreshes | Row keys are department names |
| M9.25 | Change rate date to 1 year ago → totals differ from today | Demonstrates rate-date sensitivity |
| M9.26 | Compa-ratio tab → table shows median compa-ratio column | Ratio looks plausible (0.8–1.2) |
| M9.27 | Band coverage tab → uncovered combinations listed | Designer L4 visible if using seed data |
| M9.28 | Band coverage "all covered" message if coverage is complete | Not a blank or crash |
| M9.29 | API error (kill server mid-load) → error message shown | Not a blank screen |

### M9.6 Band view

| # | Check | What to look for |
|---|---|---|
| M9.30 | Band view loads with today's date | Seeded bands appear with min/mid/max formatted |
| M9.31 | Change effective date to past date before seed bands → empty state | Not a crash |
| M9.32 | Open band shows "open" in the "To" column | Not null or blank |
| M9.33 | Amounts formatted with correct decimals | JPY bands have no decimal; KWD have 3 |

## 9. Cross-feature scenarios

The seams. Run these end-to-end in one sitting.

1. **Raise flows through**: add a salary → check the employee profile → check department
   analytics → check the compa-ratio → check the audit log. All consistent?
2. **Band revision flows through**: change a band's midpoint → recheck affected employees'
   compa-ratios → recheck the distribution buckets.
3. **New country**: add an employee in an unconfigured country → confirm the save succeeds
   → confirm the country appears flagged → assign a zone → confirm the compa-ratio now
   resolves.
4. **Import then edit**: import a batch → manually edit one imported record → confirm the
   audit trail shows both the import and the edit, distinguishably.
5. **Deactivate**: deactivate an employee → confirm they leave current spend but remain in
   a historical report covering their tenure.

## 10. The smell test

Not checks — questions to ask while using the app for twenty minutes as an HR manager.

- Could I answer "what do we pay senior engineers in Germany?" without help?
- Does any number on screen look implausible? Trace one back to its source data.
- If I make a mistake, can I tell? Can I undo it?
- Is it obvious which figures are converted and which are as-entered?
- Would I trust this enough to stop using the spreadsheet?

That last one is the actual acceptance criterion. Everything above serves it.

---

## Maintaining this plan

This was written before any code existed, so parts of it are guesses. It is expected to
change as milestones land.

**A bug found here becomes an automated spec.** That is the point of the exercise:
manual testing *discovers* gaps, the suite *guards* them. A check that has been turned
into a regression spec has done its job and should be proposed for removal — otherwise
this document grows to three hundred items nobody executes.

So it should shrink where behavior got automated and grow where new surfaces appeared. A
plan that only ever grows is a plan being ignored.

**Updated per milestone, not at the end.** The agent that just built a milestone knows
which edges it created; reconstructing eleven milestones of drift in one pass produces a
worse plan for more effort. Adding checks is part of a milestone's definition of done.

**Adding and removing are not symmetric.** Adding a check is cheap and safe. Removing one
asserts that a risk no longer exists — a judgement the plan's owner makes, not the agent
that happened to touch the area. Removals are proposed in the PR body with reasoning,
never applied unilaterally.

**Automatable checks should leave.** If a check can be driven reliably by a request spec
or a browser test, it belongs in the suite, not here. What remains is what needs human
judgement — which is most of §10, and the reason that section has no pass criteria.
