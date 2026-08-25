# M8 Implementation Plan — Bands, compa-ratio & coverage

**Status:** Handoff to implementor · **Prerequisite:** M0–M7 merged to `main`
**Branch:** `feat/m08-bands`

---

## Read first
- `docs/IMPLEMENTATION_PLAN.md` §2 (schema), §3 (M8 row + M7 as pattern reference), §7 (risks table row 1 & 2), §8 (band decisions).
- `docs/CONTEXT.md` "M7 decisions" — mirror the aggregate-SQL style and the read-side query-object pattern.
- `app/queries/pay_analytics.rb`, `app/services/fx_converter.rb`, `app/policies/*.rb`, `spec/queries/pay_analytics_spec.rb` (structural template).
- `CLAUDE.md` invariants — bands become another effective-dated series; **do not `UPDATE` min/mid/max on an existing row**.

## Design decisions to lock in before coding

1. **`salary_bands` schema** — matches plan §2 verbatim. Both `effective_from` (required) and `effective_to` (nullable = still current). New band supersedes prior by inserting a new row **and** setting the previous row's `effective_to` — this single field write is the sole permitted mutation on the table (documented in CONTEXT.md); a `before_update` guard allows only `effective_to` transitioning from NULL to a later date.
2. **Uniqueness invariant** — no two rows with the same `(pay_zone_id, job_title, job_level)` may have overlapping `[effective_from, effective_to)` windows. Enforce with a PostgreSQL `EXCLUDE USING gist (... WITH =, daterange(effective_from, effective_to, '[)') WITH &&)` constraint plus the `btree_gist` extension. This is the "band changed mid-period" edge case: two versions coexist, one supersedes the other on its `effective_from`.
3. **Currency lives on the band, per plan §2.** Comp teams set bands in local terms. `BandResolver` normalizes salary and band to USD at the caller-supplied `rate_date`. The currency-mismatch case is defined behavior, not an error.
4. **`BandResolver`** — pure lookup, no policy. Interface: `BandResolver.resolve(employee:, on_date:, rate_date: on_date)` returns a `Result` value object with `:band`, `:reason` (`:ok | :unzoned_country | :no_band | :no_rate | :no_salary`), `:compa_ratio` (BigDecimal, nil if unresolved), `:bucket` (`:below | :within | :above | nil`), `:salary_usd_minor_units`, `:band_min/mid/max_usd_minor_units`. Never raises for missing data — returns a `Result` with a reason. Raises only for programmer error (nil employee etc.).
5. **Bucket boundaries** — `:below` if salary < min; `:within` if min ≤ salary ≤ max (inclusive on both ends); `:above` if salary > max. Compare in USD minor units, so rounding is deterministic. Compa-ratio = `salary_usd / mid_usd` (BigDecimal, unrounded; presenters round to 2dp).
6. **Coverage report** — enumerates every `(pay_zone_id, job_title, job_level)` combination for which at least one active (`status='active'`, hired, not terminated) employee exists but no band covers `today`. Groups without a pay zone (unzoned country) surface separately under `unzoned`.
7. **Compa-ratio aggregate** — single-pass SQL in a new `CompaRatioAnalytics` query object, mirroring `PayAnalytics`. Shares `GROUPS`/`FILTERS` allowlists (extract to a small module or duplicate — implementor's call, but prefer duplication over premature abstraction). Group rows return `headcount`, `covered_headcount`, `avg_compa_ratio` (numeric, 4dp), `below/within/above` bucket counts, `unresolved` (unzoned + no_band + no_rate combined). Meta echoes `as_of`, `rate_date`, `group_by`, `unconvertible_currencies` **plus** `uncovered_combinations` (a count, not the list — coverage report gives the list).
8. **API surface** — four endpoints:
   - `GET /salary_bands` (viewer) — filter `pay_zone_id`, `job_title`, `job_level`, `effective_on` (default today). Returns flat list with band + zone name.
   - `POST /salary_bands` (hr_admin) — creates a new band; if a previous band matches `(pay_zone_id, job_title, job_level)` with `effective_to IS NULL`, closes it by setting `effective_to = new.effective_from`. Idempotency: 422 if a band with identical `(pay_zone_id, job_title, job_level, effective_from)` already exists.
   - `GET /analytics/compa_ratio` (viewer) — same params as `/analytics/pay` plus the response shape above.
   - `GET /analytics/band_coverage` (viewer) — no filters (report is the whole picture); returns `{ uncovered: [{pay_zone_id, pay_zone_name, job_title, job_level, employee_count}], unzoned: [{country_code, job_title, job_level, employee_count}] }`.

## Concrete deliverables

### Migration (`db/migrate/20260826000001_create_salary_bands.rb`)
```ruby
enable_extension 'btree_gist' unless extension_enabled?('btree_gist')
create_table :salary_bands do |t|
  t.string :job_title, null: false
  t.string :job_level, null: false
  t.references :pay_zone, null: false, foreign_key: true
  t.string :currency, limit: 3, null: false
  t.bigint :min_minor_units, null: false
  t.bigint :mid_minor_units, null: false
  t.bigint :max_minor_units, null: false
  t.date :effective_from, null: false
  t.date :effective_to
  t.timestamps
end
add_index :salary_bands,
          [:pay_zone_id, :job_title, :job_level, :effective_from],
          order: { effective_from: :desc },
          name: 'index_salary_bands_on_zone_title_level_from'
execute <<~SQL
  ALTER TABLE salary_bands
  ADD CONSTRAINT salary_bands_no_overlap
  EXCLUDE USING gist (
    pay_zone_id WITH =, job_title WITH =, job_level WITH =,
    daterange(effective_from, effective_to, '[)') WITH &&
  );
  ALTER TABLE salary_bands
  ADD CONSTRAINT salary_bands_ordered CHECK (
    min_minor_units <= mid_minor_units AND mid_minor_units <= max_minor_units
  );
SQL
```

### `app/models/salary_band.rb`
- `belongs_to :pay_zone`
- Validations: presence on all required fields, `currency` format `/\A[A-Z]{3}\z/`, `currency_must_be_known` mirroring Salary, `effective_to` (when set) > `effective_from`, `min ≤ mid ≤ max`.
- `before_update` guard: allow only `effective_to` moving from NULL → later date; block any other column change with a validation error + `throw :abort`. Mirror ExchangeRate/Salary guard style.
- `scope :covering, ->(date) { where('effective_from <= ? AND (effective_to IS NULL OR effective_to > ?)', date, date) }`.

### `app/services/band_resolver.rb`
- Small `Result = Struct.new(...)`.
- Lookup order: pay_zone via `employee.country.pay_zone_id` (nil → `:unzoned_country`), then `SalaryBand.covering(on_date).find_by(pay_zone_id:, job_title: employee.job_title, job_level: employee.job_level)` (nil → `:no_band`), then `FxConverter` for salary and band values (raises `NoRateError` → return `:no_rate`).
- Uses `employee.salary_on(on_date)`; nil salary → `Result` with `:no_salary` reason.

### `app/queries/compa_ratio_analytics.rb`
- Structure parallels `PayAnalytics`. Two aggregates: an unconvertible-currency probe (reuse M7 logic — extract to a `CurrencyResolution` module only if the duplication is exact) and a big grouped aggregate joining `salaries`, `employees`, `countries`, `pay_zones`, `salary_bands`, and the rates/subunits CTEs.
- Band join: `LEFT JOIN salary_bands sb ON sb.pay_zone_id = countries.pay_zone_id AND sb.job_title = employees.job_title AND sb.job_level = employees.job_level AND sb.effective_from <= :as_of AND (sb.effective_to IS NULL OR sb.effective_to > :as_of)`.
- `LEFT JOIN` (not INNER) so unresolved employees still count toward `headcount`.
- Bucket via `CASE WHEN sb.id IS NULL THEN 'unresolved' WHEN salary_usd < band_min_usd THEN 'below' WHEN salary_usd > band_max_usd THEN 'above' ELSE 'within' END`.
- Compa-ratio: `AVG(salary_usd::numeric / NULLIF(band_mid_usd, 0))` — Postgres AVG already ignores NULLs, so unresolved rows drop out cleanly.
- Output row keys: `key`, `label`, `headcount`, `covered_headcount`, `avg_compa_ratio` (4dp string), `below`, `within`, `above`, `unresolved`.

### `app/queries/band_coverage.rb`
- Not aggregate-heavy — one query for uncovered `(pay_zone, title, level)` combos with a headcount, one for unzoned (`countries.pay_zone_id IS NULL`) combos. Both filter to active + hired-by-today + not-terminated employees, matching PayAnalytics' population definition.

### Controllers & policies
- `SalaryBandsController` (index, create) + `SalaryBandPolicy < ApplicationPolicy` (inherit defaults; read for all authenticated, write for hr_admin).
- Extend `AnalyticsController` with `compa_ratio` and `band_coverage` actions, each calling `authorize!(:read)`.
- Routes: `resources :salary_bands, only: %i[index create]`; `get '/analytics/compa_ratio', to: 'analytics#compa_ratio'`; `get '/analytics/band_coverage', to: 'analytics#band_coverage'`.

### Seeds (`db/seeds.rb` append)
- Add ~6 bands: two levels × three zones (Engineering L3/L5 in default-na, default-emea, default-apac). Currencies: USD, EUR, JPY. Enough to exercise mixed-currency compa-ratio without ballooning to hundreds of rows.
- Ensure at least one active employee exists in a title/level with **no** band (so coverage report is non-empty).
- Idempotent via `find_or_create_by!` on `(pay_zone_id, job_title, job_level, effective_from)`.

### Factory (`spec/factories/salary_bands.rb`)
- Sensible defaults; provide `:current` (effective_from: 2 years ago, effective_to: nil) and `:closed` (effective_to set) traits.

## Test coverage — must exercise every M8 "Key tests" cell

Map each into a named spec:

| Milestone-table edge case | Spec location | Assertion |
|---|---|---|
| No matching band | `band_resolver_spec.rb` + `compa_ratio_analytics_spec.rb` | Result reason `:no_band`; aggregate bucket = `unresolved` |
| Country in no pay zone | `band_resolver_spec.rb` | Reason `:unzoned_country`; band_coverage lists it under `unzoned` |
| Band currency ≠ salary currency | `band_resolver_spec.rb` | Both normalized to USD at same rate_date; compa-ratio matches hand-computed value |
| Band changed mid-period | `salary_band_spec.rb` + `band_resolver_spec.rb` | Two rows with adjacent `[effective_from, effective_to)` windows; resolver picks the correct one for a date on each side of the boundary; overlap constraint rejects a bad insert |
| Boundary values | `band_resolver_spec.rb` | Salary exactly at min → `:within`; at max → `:within`; at max+1 minor unit → `:above`; at min-1 → `:below`; at mid → compa-ratio = 1.0 exactly |
| Coverage report lists every uncovered title/level/zone | `band_coverage_spec.rb` | Given N zones × M titles × K levels with a mix of coverage, the response enumerates precisely the uncovered non-empty combinations — verify with `contain_exactly` on the exact set |

Plus non-key negatives:
- Salary in a currency with no rate → resolver `:no_rate`; aggregate excludes from `covered_headcount`, currency in `unconvertible_currencies`.
- Attempt to `UPDATE` a band's `min_minor_units` → `RecordNotSaved`.
- Attempt to insert an overlapping band → `RecordNotUnique`.
- `POST /salary_bands` as viewer → 403.
- `POST /salary_bands` with `max < min` → 422.
- `GET /analytics/compa_ratio` unauth → 401.
- Region rollup for compa-ratio: sum of `headcount` across `group_by=country` for a region equals `group_by=region` for that region (same invariant PayAnalytics has).

## Commit sequence (targeting ~5 commits — the M7 shape)

1. `feat: SalaryBand schema and model — effective-dated, zone-scoped, currency-carrying`
   - Migration, model, factory, model spec.
2. `feat: BandResolver — pay zone → band → USD-normalized compa-ratio`
   - Service + spec covering all `:reason` branches and boundary values.
3. `feat: SalaryBands API — GET /salary_bands, POST /salary_bands (hr_admin)`
   - Controller, policy, routes, request spec.
4. `feat: GET /analytics/compa_ratio — grouped distribution with band coverage`
   - Query object, controller action, route, query + request specs. Reuses M7's group/filter allowlists.
5. `feat: GET /analytics/band_coverage — uncovered combinations report`
   - Query object, controller action, route, request spec.
6. `chore: seed salary bands and document M8 decisions`
   - Seeds append, `docs/CONTEXT.md` M8 section, `docs/MANUAL_TEST_PLAN.md` M8 section (new checks for the three endpoints; propose §4 checks 4.1–4.7 for removal against the newly automated coverage).

Squash 5 & 6 into 4 if that reads cleaner; do **not** split by file.

## Definition of done

- `bundle exec rspec` green; `bundle exec rubocop` zero offences (both required, in that order — a failing spec often explains a lint error).
- All Milestone-table key tests are named specs.
- `docs/CONTEXT.md` gains a "M8 decisions" section covering: the `effective_to` mutation carve-out (why not fully append-only), the GIST overlap constraint, bucket boundary inclusivity, the `Result` struct shape, and the seed choice.
- `docs/MANUAL_TEST_PLAN.md` gains an M8 API section with concrete `curl` checks for each endpoint (mirror the M7 section's structure) and proposes automated §4 checks for removal in the PR body.
- Branch: `feat/m08-bands`. **Do not push** — surface the commit sequence and ask for approval per CLAUDE.md.
- Write a `backend/m8_manual_test.sh` helper mirroring the existing `m5_/m6_/m7_manual_test.sh` files.

## Things to ask before starting, not decide silently

- Whether to enforce full immutability (append-only, no `effective_to` writes at all — derive it in queries) or keep the `effective_to` write carve-out. This plan says the carve-out; if it feels wrong on encountering the guard, escalate rather than switch.
- Whether the `POST /salary_bands` endpoint should auto-close the previous band or require the client to pass `effective_to` on the prior row (i.e. two-step). Plan says auto-close; confirm with owner if the request-spec fixtures feel awkward.
- Whether compa-ratio should be embedded in `GET /employees/:id`. Plan says **no** for M8 — keep it a separate aggregate query; per-employee embedding can land in M9 with the profile UI.
