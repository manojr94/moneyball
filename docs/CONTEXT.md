# Project Context & Decision Log

Running notes for anyone (human or agent) picking up this project. Read
`docs/REQUIREMENTS.md` first — this file records the decisions *behind* it and the
state of play.

## Where we are

- Requirements one-pager written (`docs/REQUIREMENTS.md`).
- No application code written yet.
- Next deliverable: the implementation plan (milestones, schema, API surface, test
  strategy, commit sequence). **No code until that plan is agreed.**

## Product decisions (settled)

| Decision | Choice | Reasoning |
|---|---|---|
| **Analytics depth** | Basic aggregates **and** compa-ratio, sequenced in that order | Compa-ratio is a superset — it reuses the filtering, grouping, and pagination layer aggregates require. Building aggregates first means the harder feature lands on proven infrastructure. |
| **Access model** | Two roles: HR Admin (read/write) + Viewer (read-only) | Exercises real authorization design without the cost of a full permission system. Viewer maps to a genuine user (finance/exec stakeholder who needs reports, not edit rights). |
| **Deployment** | Public demo with seeded synthetic data | The project is portfolio work; a clickable demo is worth more than screenshots. Build 12-factor from day one so hosting is configuration, not a rewrite. |
| **Currency** | Store local currency; derive USD at read time from an append-only `exchange_rates` table, with the rate date as an explicit query parameter | ~~Snapshot the rate per record~~ — **superseded, see below.** Cross-country analytics needs a common unit, but the USD figure is a derivation, not a fact: nobody is paid in USD. One source of truth, and both "what we recorded then" and "what it is worth today" become answerable. |
| **Band scope** | Pay zones, with countries mapped into them | Per-country bands would run to thousands of hand-maintained rows at ACME's size — the spreadsheet problem rebuilt inside the app. A single-country zone still gives per-country precision where a market is genuinely distinct, so nothing is lost. |
| **Region tier** | Yes — a `region` column on `countries`, not a table | "EMEA vs APAC spend" is a week-one question. Regions are a fixed, short, behaviourless list, so a column suffices; adding it later would mean a migration plus a backfill of every country. |
| **Band denomination** | Local currency per band, normalized to USD at comparison time | Comp teams set bands in local terms, so currency is part of a band's identity. Normalizing at evaluation makes the currency-mismatch case defined behavior rather than an error. |
| **Geography setup** | Regions seeded from public data; pay zones defaulted and flagged `needs_review`; entry never blocked | Region is mechanical (ISO 3166 → UN geoscheme) so it should cost zero admin work. Zones are a judgement call, but a one-time one over ~20 countries. An HR manager onboarding a hire must never be stopped by a missing mapping. |
| **Encryption** | No column-level encryption on salary amounts | An encrypted column cannot be summed, averaged, percentile-ranked or range-queried. Encrypting amounts and computing compa-ratios are mutually exclusive, and analytics is why this app exists. Protection is at rest, in transit, in policy objects, and in the audit trail. |

## Superseded decisions

Kept deliberately. A log that shows only the current state is a specification, not a
record of thinking.

| Original | Revised to | What changed the answer |
|---|---|---|
| Snapshot `fx_rate` and `usd_amount_cents` onto each salary row | Derive USD at read time; `exchange_rates` append-only | Review challenged the column as duplicating the rates table. It did. The snapshot treated a derivation as a fact, and answered "what did we record then" when a manager asking about EMEA spend means "what is it worth now" — silently blending rates from whenever each row was entered. With rates immutable, a lookup reproduces the snapshot exactly, so the column was a cached copy of a query with one possible answer. |
| `amount_cents` as the money column | `amount_minor_units` + `money-rails` | "Cents" asserts a 1/100 subunit that is false for JPY (no subunit) and for KWD/BHD/JOD (three decimals). The name encoded a rule contradicted by the data, which is how a Tokyo salary ends up wrong by 100×. |

## Architectural decisions (proposed, not yet built)

1. **Salary is an append-only, effective-dated series** — a `salaries` table with
   `effective_date`, not a mutable `salary` column on `employees`. Makes point-in-time
   questions answerable, makes the audit trail structural rather than bolted on, and
   means no edit can destroy history. This is the load-bearing decision in the whole
   design; most other things follow from it.

2. **Money as integer minor units** (`amount_minor_units` + `currency`), never floats.
   Floating-point currency is a correctness bug, not a style preference. Minor units
   follow each currency's ISO 4217 exponent, which `money-rails` knows — so JPY (0
   decimals) and KWD (3) are handled by the library rather than by convention.

3. **Salary bands are first-class data** (`salary_bands`: role, level, pay zone,
   currency, min/mid/max, effective dates) rather than derived or hardcoded. Compa-ratio
   is meaningless without them, and they change over time like salaries do.

4. **Band resolution is an explicit service object**, not a scope or a join. The edge
   cases are the interesting part: no matching band, a country in no pay zone, band in a
   different currency than the salary, band changed mid-period. These deserve isolated,
   well-tested logic.

5. **`countries` is a reference table**, not a bare string column on `employees`. It
   carries `default_currency`, `pay_zone_id` (band resolution) and `region` (analytics
   rollup) — two independent groupings, kept as separate fields because EMEA is one
   region spanning several pay zones.

## Open questions

None outstanding against the schema — all three original questions are resolved in the
decision table above.

The next decision point is **M0**: the local `backend/` and `frontend/` scaffolding
already exists, so M0 should audit what is present and fill gaps (RSpec, FactoryBot,
linters, CI) rather than scaffold over a working setup. The plan as written assumes
greenfield; adapt it.

One open call for the owner, not blocking: the plan puts **auth at M4, before the
employee API at M5**, so no endpoint is ever written unprotected and retrofitted. That
means the first four milestones ship nothing demo-able. Swapping them trades security
posture for an earlier visible feature — recommendation is to keep the current order.

## M1 decisions (2026-08-24)

### Country code as string primary key

`countries.code` (ISO 3166-1 alpha-2) is the table's primary key rather than a surrogate
integer. The code is stable, globally unique, and already the natural join key — every
`employees.country_code` FK, every seed row, and every `find_or_create_unconfigured` call
uses the two-letter code directly. A surrogate key would add an extra column and an extra
join for no benefit; the code is the identity.

*Trade-off:* string PKs are marginally slower to join than integers at high cardinality.
Countries is a ~250-row reference table; the join is negligible.

### Postgres enums for region and employee status

`region_type` (`na/latam/emea/apac`) and `employee_status` (`active/inactive/terminated`)
are Postgres enum types rather than string columns with an `inclusion` validation.
The database rejects an invalid value at write time regardless of how the row was
inserted — a Rails validation can be bypassed (raw SQL, console, future migration),
a Postgres type constraint cannot.

*Trade-off:* adding an enum value requires a migration (`ALTER TYPE`). Both sets are fixed
and closed by design (CLAUDE.md: "Fixed, small, closed sets — the database should reject
a typo, not store it"), so this is not a practical concern.

### Auto-create unconfigured country lives on Employee as a before_validation callback

When an employee is saved with a `country_code` not yet in the `countries` table, the
callback calls `Country.find_or_create_unconfigured(country_code)` before validation
runs, so the `belongs_to :country` association is satisfied and the employee saves
without error. The logic sits on `Employee` rather than `Country` because it is triggered
by an employee event, and on `before_validation` (not `before_save`) so the association
is present when Rails checks it.

If the country code is not in `COUNTRY_DATA` (e.g. a test-only code like `XK`) and the
country row already exists, the callback is a no-op. If the code is unknown and the row
does not exist, `find_or_create_unconfigured` returns nil and the `belongs_to :country`
existence validation surfaces the problem ("must exist") — no silent failure.

### Post-review corrections (2026-08-23)

Three bugs found in adversarial review of the M1 diff, fixed before the PR opened:

**Race condition in `find_or_create_unconfigured`** — The original
`find_or_initialize_by` + `new_record?` + `save!` pattern is not atomic. Two concurrent
requests with the same unknown country_code would both see `new_record? == true` and
both call `save!`; the second raises `ActiveRecord::RecordNotUnique`. Fixed by rescuing
`RecordNotUnique` and re-finding — the concurrent winner's row is returned.

**No automated hard-delete guard on Employee** — The "never hard-delete" invariant was
only covered by manual test M1.5, with no regression spec. Added `before_destroy` that
adds a validation error and `throw :abort`, plus two automated specs (one for `destroy`
returning false, one for `destroy!` raising `RecordNotDestroyed`). SQL-level truncation
used by DatabaseCleaner bypasses ActiveRecord callbacks, so test teardown is unaffected.

**`created_at` / `updated_at` columns were `timestamp` not `timestamptz`** — The
implementation plan (line 68) requires `timestamptz` for instants. `t.timestamps` emits
`timestamp without time zone`. Since the branch was pre-PR with no external consumers,
the four `create_table` migrations were edited in place (no correction migration) and
the database rebuilt from scratch. An initializer
(`config/initializers/postgres_datetime.rb`) sets
`PostgreSQLAdapter.datetime_type = :timestamptz` so future `t.timestamps` calls in
later milestones produce the correct type without requiring explicit column declarations.

## M2 decisions (2026-08-24)

### `exchange_rates` has `created_at` but no `updated_at`

The table is append-only: a correction is a new row, never an edit. Including `updated_at`
would imply rows can be mutated; omitting it makes the immutability structural in the
schema rather than only enforced at the model layer. `created_at` is kept for "when was
this rate entered" — a legitimate audit question.

### `string limit: 3` instead of `char(3)` for the currency column

Rails does not expose `char(n)` as a migration column type on PostgreSQL. `string limit: 3`
maps to `character varying(3)` and carries the same length constraint while working with
the standard Rails column API. A check constraint on format (`/\A[A-Z]{3}\z/`) is enforced
at the model layer via `validates :currency, format:`.

### FxConverter converts only to USD

The only cross-currency comparison in v1 is normalization to a common unit for analytics
and compa-ratio. USD is the single target for all conversions; `exchange_rates` stores
`rate_to_usd` per row. A multi-target converter would require a cross-rate join
(`from → USD → to`) which is unneeded complexity for v1 and can be added when the need
arises.

### `Money::Currency.find` guards unknown currencies

`FxConverter` raises `UnknownCurrencyError` for any code the money gem does not
recognise. This is cheaper than an allowlist in application code and leverages the gem's
complete ISO 4217 dataset, which already includes all currencies the app will encounter.
A three-letter code that passes the database `format:` validation but is not an ISO
currency is still rejected here with an explicit error rather than a silent null.

### Rounding: `BigDecimal::ROUND_HALF_UP`

Configured globally in `config/initializers/money.rb` and applied explicitly in
`FxConverter` when truncating fractional USD cents. Standard accounting rounding — rounds
0.5 away from zero. The alternative (banker's rounding, `ROUND_HALF_EVEN`) is statistically
less biased but unusual for payroll applications where staff expect the conventional rule.

### `update_all` bypasses the append-only guard

`before_update` and `before_destroy` on `ExchangeRate` block mutations through the
ActiveRecord model lifecycle, but `ExchangeRate.update_all(...)` and
`ExchangeRate.where(...).update_all(...)` execute SQL directly and skip all callbacks.
This is a standard Rails limitation. Any future rate-correction tooling must use `INSERT`
(a new row with a later `effective_date`), never `update_all`. There is no application
path that calls `update_all` on this table; the guard exists to catch accidental
single-record mutations through the ORM.

### `config.default_currency = :usd` in money-rails initializer

`money-rails` requires a default currency to be configured; USD was chosen as the
technical default. This creates a latent footgun: `Money.new(amount)` without an explicit
currency silently produces a USD Money object, in tension with the invariant that nobody
is paid in USD. Every `Money.new` call in application code must pass an explicit currency
argument. USD as default is an initializer requirement, not a signal that USD is
semantically meaningful as a default salary currency.

## M3 decisions (2026-08-24)

### `monetize` macro skipped on Salary; `#amount` method used instead

`money-rails`' `monetize` macro assumes the storage column is named with a `_cents`
suffix (e.g. `price_cents` → `price` method). Our column is `amount_minor_units` — the
name that accurately reflects ISO 4217 semantics (cents is false for JPY and KWD). Using
`monetize :amount_minor_units, as: :amount, with_currency: :currency` triggers the
money-rails built-in numericality validator, which calls `Money::Currency.find(currency).subunit_to_unit`
before our own validations run. Because the validator fires on every save attempt, an
invalid-currency record raises `NoMethodError` on nil instead of returning a readable
validation error.

`FxConverter` already constructs `Money` objects manually via `Money.new(minor_units, currency)`.
`Salary` follows the same pattern: a simple `#amount` method returns the Money object without
involving the macro's validator machinery. Our own `currency_must_be_known` validation
produces a clear, user-readable error for unknown currencies.

*Trade-off:* no `amount=` setter or money-rails integration (e.g. `price_in_dollars`
helpers). Those aren't needed — the app reads and writes `amount_minor_units` directly
through `RecordSalaryChange`, and FX conversion uses `FxConverter`. If money-rails helpers
are needed later, the column can be aliased to `amount_cents` via a database view or the
gem can be configured with a custom column suffix.

### Same-day tiebreaker: later-inserted row (higher `id`) wins

Two salary rows can share an `effective_date` — a realistic scenario when an entry is
corrected the same day it was made. The `.as_of` scope orders by
`(effective_date DESC, id DESC)`, so the most recently inserted row wins. This is
deterministic and stable across reloads, and matches the mental model: the second entry
supersedes the first.

*Trade-off:* there is no way to distinguish "intentional same-day correction" from
"duplicate insert". A future UI could present same-date rows as candidates for deduplication.
No application logic blocks a second insert on the same date — that is intentional, since
a same-day correction is a valid business operation.

### `created_by_id` stored without FK constraint until M4

The `salaries` table includes `created_by_id` (bigint, nullable) to record which user
initiated each pay event. The `users` table does not exist until M4, so the FK constraint
is deferred. The column is nullable so M3 tests and seeds do not require a real user record.
The FK will be added in M4's migration alongside the users table. An index on `created_by_id`
is added in M3 so the FK migration in M4 is cheap (no table rewrite needed). M4's migration
must handle pre-existing rows with phantom `created_by_id` values (e.g. test seeds) before
enabling the constraint.

### `salary` rows are restricted from deletion via `has_many :salaries, dependent: :restrict_with_error`

Attempting to destroy an employee who has salary records returns a validation error rather
than cascading the delete. This upholds the "never hard-delete" and "salary rows are
immutable" invariants together: neither the employee nor their pay history can be silently
removed.

## M4 decisions (2026-08-25)

### JWT over session cookie

The implementation plan's architecture diagram mentions "session cookie", but the data
model explicitly includes `token_version` (an integer counter on `users`) for revocation.
`token_version` is a JWT pattern: each token embeds the version at encode time, and the
server rejects a token whose embedded version no longer matches the user's current counter.
This does not apply to cookie sessions, where revocation simply deletes the session row.

JWT was chosen because:
- `token_version` in the schema signals JWT semantics
- The API is consumed by a React SPA where a cookie requires extra CORS configuration
- Tokens are stateless — most requests validate without a DB read (only the payload user_id
  lookup is required; no separate session table)

*Trade-off:* JWTs cannot be invalidated mid-lifetime except via `token_version`. A bump to
`token_version` (sign-out, deactivation) invalidates all outstanding tokens for that user
immediately. The 24-hour expiry is short enough that this window is acceptable for v1.

### `jwt` gem added

`jwt` (~> 2.8) is the only new production dependency in M4. `bcrypt` was already present.
`has_secure_password` handles password verification; `jwt` handles token encode/decode.
No other auth library is needed given the two-role model.

### Pundit-style policies without the Pundit gem

The implementation plan specifies "Pundit-style policies". M4 implements the pattern
without adding the Pundit gem:

- `ApplicationPolicy` follows Pundit's interface: `initialize(user, record)`, `read?`,
  `write?` predicates.
- `ApplicationController#authorize!(action)` raises `NotAuthorizedError` if the policy
  denies the action; `rescue_from` renders 403 and halts the action chain.
- Raising rather than rendering inside `authorize!` is the key: a `render` call inside a
  helper method doesn't halt the action chain (only `before_action` renders do that
  automatically). Raising halts immediately regardless of call site.

A resource-specific policy (e.g. `EmployeePolicy`) can be added in later milestones by
overriding the policy class per controller.

### `ProbesController` for testing the 403 path

M4 has no write endpoints yet (those land in M5). To verify the 403 behavior without
waiting for M5, a minimal `ProbesController#write` action was added that calls
`authorize!(:write)` and returns `head :ok`. A route for it is registered only in the
test environment (`if Rails.env.test?`). The controller lives in `app/controllers/`
because Rails' Zeitwerk autoloader scans `app/` subdirectories — a file in `spec/support/`
would not be autoloaded and would require manual `require`. The probe controller is not
accessible in development or production.

### `salaries.created_by_id` FK constraint: phantom-value strategy

The M4 migration adds the FK from `salaries.created_by_id` to `users.id`. Pre-M4 seeds
and test factories used a phantom `created_by_id: 1`. The migration nullifies any
`created_by_id` values not present in `users` before enabling the constraint:

```sql
UPDATE salaries SET created_by_id = NULL
WHERE created_by_id IS NOT NULL
AND created_by_id NOT IN (SELECT id FROM users);
```

The `RecordSalaryChange` spec, which previously passed `created_by_id: 42`, was updated
to default to `nil` (nullable, optional) and to create a real user only in the test that
specifically asserts the ID is stored.

## M5 decisions (2026-08-25)

### `EmployeeQuery` as the index read path

Filtering, sorting, and pagination for `GET /employees` are handled by `app/queries/employee_query.rb`
rather than inlined in the controller, consistent with the architecture plan (§1: "Queries — read-side
composable objects"). The controller stays thin: it validates auth, delegates to the query, and serializes
the result.

### Keyset pagination over `OFFSET`

The implementation plan (§5) explicitly calls for keyset pagination because `OFFSET N` degrades linearly
— `OFFSET 9000` on a 10k-employee table scans 9000 rows to discard them. Keyset pagination uses a
cursor that encodes the last-seen sort value and id, turning the next-page lookup into an indexed range
scan regardless of position. The cursor is opaque to callers (base64-encoded JSON) so the format can
change without a client-side migration.

*Trade-off:* keyset cursors are forward-only (no "jump to page 47") and require a stable sort. Both are
acceptable: the employee list is unlikely to need random-access pagination, and the sort is always
stable (sort column + id as tiebreaker).

### OR-expanded cursor predicate rather than row-value comparison

The cursor WHERE clause is expressed as:
```sql
sort_col > ? OR (sort_col = ? AND employees.id > ?)
```
rather than the more compact Postgres row-value syntax `(sort_col, id) > (?, ?)`. Both are semantically
equivalent, but the OR form is explicit in `EXPLAIN` output and avoids any ORM type-casting ambiguity
when the sort column is a `date`. The performance profile is the same: both forms are index-eligible.

### `EmployeeSerializer` uses `as_json(only:)` for concision

`EmployeeSerializer.render` calls `employee.as_json(only: FIELDS)` rather than constructing an
explicit hash for each attribute. This keeps the method under RuboCop's `Metrics/MethodLength` limit
without splitting the serializer into arbitrary helper methods. The `FIELDS` constant is the canonical
allowlist — adding a column to the response requires only a change there. `department` is merged in
separately because it is a nested association, not a flat attribute.

*Trade-off:* `as_json` returns string-keyed hashes. This is correct for a JSON API (JSON always has
string keys) and is transparent to callers because `render json:` handles both string and symbol keys.

### `authorize!` updated to accept `policy_class:` keyword

`ApplicationController#authorize!` now accepts an optional `policy_class:` keyword argument
(defaulting to `ApplicationPolicy`). Controllers with resource-specific policies (starting with
`EmployeesController`) pass their own class. This avoids hardcoding `ApplicationPolicy` in
controllers and avoids adding per-controller `authorize!` overrides.

*Trade-off:* `ApplicationPolicy` remains the default, so any controller that does not specify
`policy_class:` continues to work unchanged.

### `RSpec/MultipleMemoizedHelpers` limit raised to 10

Request specs inherit four auth helpers (`admin`, `viewer`, `admin_headers`, `viewer_headers`) from
the outer describe block, leaving only one slot before the default limit of 5. Raising to 10 in
`.rubocop.yml` allows realistic integration test setup without requiring each inner describe to
re-declare auth. The cap at 10 still catches genuinely bloated contexts.

### `Employee.delete_all` in test setup (not `destroy_all`)

Sorting and pagination specs need a controlled, known employee set, so they clear existing records
before creating their own. `Employee.delete_all` (direct SQL) is used rather than `destroy_all`
(which calls each record's `before_destroy` callback — blocked by the hard-delete guard). This is the
same bypass DatabaseCleaner uses for test teardown; no application code takes this path.

## M6 decisions (2026-08-25)

### CSV only in v1; XLSX deferred

The implementation plan lists CSV/XLSX. M6 ships CSV only. XLSX would require a
new dependency (`roo` or `creek`) and streams zip/XML rather than lines, which is
a genuinely different code path. The practical Excel-export flow is "Save As →
CSV", which is what HR does today with the existing spreadsheets. When XLSX
becomes a hard requirement, the ImportEmployees service can accept a different
parser without changing the row-processing pipeline.

### Dry-run is commit-with-rollback

The service always wraps row processing in a single transaction. Dry-run mode
adds a mandatory `raise ActiveRecord::Rollback` at the end; commit mode raises
the same rollback only if any error was recorded. Both modes therefore run
every validation, every callback, and every uniqueness check against the state
that would exist mid-import — so a dry-run preview cannot succeed on a case
that a commit would reject. This is the "preview matches commit" guarantee
called out in manual test 5.6, and it is structural rather than a paired code
path we have to keep in sync.

*Trade-off:* dry-run pays the write cost (INSERTs happen, then roll back).
For a 10k-row file this is a few seconds of wasted work, which we accept as
the price of the invariant.

### Row loop runs to completion; commit rolls back at the end

If row 42 fails validation, rows 43–10,000 are still processed so the response
can list every problem in one upload. On commit mode, the transaction rolls
back at the end if any errors were recorded — no partial commit is possible.

*Alternative considered:* halt on first error. Rejected because it forces HR
to fix-and-re-upload one error at a time, which is exactly the manual toil the
import is supposed to replace.

### Errors capped at 100 in the response

A 10k-row file with pervasive errors could produce a multi-megabyte response
otherwise. The service continues processing past the cap so `rows_invalid`
stays accurate; only the `errors` array stops accumulating. Configurable via
`ImportEmployees::MAX_ERRORS`.

### Countries auto-create; departments do not

Countries follow the M1 invariant: an unknown `country_code` in an import row
creates a `Country` flagged `needs_review` and the row saves. Departments do
not have this rule — they are a deliberately curated list (~10–20 rows at
ACME's scale), and typos in import files should surface as errors rather than
silently spawning `Enginering` / `enginering` / `Enegineering` rows. Unknown
department names are rejected at row validation.

### Header-based parsing; column order agnostic; extra columns ignored

The parser resolves fields by header name, not by position. This survives
Excel exports that reorder columns and files with extra columns (`notes`,
`cost_center`) that we don't consume. Missing required columns fail the
entire file before any row is processed. BOM bytes at the file start are
stripped so Excel-on-Windows exports parse correctly.

### `department_name` (not `department_id`) in the CSV schema

HR exports from spreadsheets carry department *names*, not database IDs.
Requiring an id would force a manual lookup step before every import. Names
are matched case-insensitively (`Engineering` == `engineering`). The
department cache in `ImportState` reduces 10k row imports to one DB query per
distinct department name.

### Salary is optional per row; `Money.from_amount` handles minor units

If any `salary_*` column is populated on a row, salary_amount and
salary_currency are both required (effective_date defaults to hire_date, and
reason is hard-coded to `new_hire`). Amounts are supplied as major-unit
decimals ("80000" or "80000.00"); conversion to minor units goes through
`Money.from_amount(BigDecimal(...), currency).fractional`, which correctly
handles JPY (exponent 0), USD (exponent 2), and KWD (exponent 3) without the
service knowing which is which. Thousands-separator commas are stripped.

### MAX_ROWS = 10,000

Matches the implementation plan's scale target. A larger cap invites
long-running requests that hold a transaction open for minutes; splitting
files is a small ask compared to timing out mid-import. Anything larger goes
back to the operator to split — the message names the cap so the failure is
self-explanatory.

### Multipart file upload with a `csv` string fallback

`POST /imports/employees` accepts either `params[:file]` (standard multipart
upload from a browser or `curl -F`) or `params[:csv]` (a raw string in a JSON
body). The string form exists for scripts and tests that don't want to
construct a multipart body. Both paths funnel into the same service call.

### `dry_run` defaults to true

A missing, empty, or unrecognized `dry_run` param means preview. Only the
literal string `"false"` triggers a commit. This is a "safe by default"
choice — a client that forgets the flag gets a preview, not a surprise 10k-
row insertion.

### HTTP status codes

- Dry-run always returns **200** regardless of row validity (the preview
  itself succeeded; errors are data in the body, not a failure of the
  request).
- Commit with all rows valid returns **201 Created**.
- Commit with any row error returns **422 Unprocessable Content** and rolls
  back.
- Missing file, missing required columns, or a malformed CSV returns **422**
  before any row processing.

### `ImportEmployees` split into `Parser`, `RowImporter`, `ImportState`, `RowAttrs`

The outer class orchestrates the transaction and returns the `Result`. Row
parsing and header validation live in `Parser`. Per-row logic (extraction,
duplicate check, employee save, optional salary) lives in `RowImporter`.
Cross-row bookkeeping (counts, seen-so-far maps, error cap, department
cache) lives in `ImportState`. Splitting kept each unit within the standard
RuboCop metrics without loosening the limits, and each collaborator has one
reason to change.

### M6 post-review fixes (2026-08-25)

Five findings from the M6 review (PR #10) were addressed before merge:

- **Concurrent import → 500** — `RowImporter#call` now rescues
  `ActiveRecord::RecordNotUnique` and records it as a row error. Rails'
  uniqueness validation is not race-safe: two imports of the same
  `employee_number`/`email` both pass the `SELECT` check, and the loser's
  `INSERT` used to escape the transaction as an unhandled exception. Now the
  outer transaction rolls back cleanly with a `"conflicts with an existing
  record"` row error. Spec added; simulates the race via
  `allow_any_instance_of(Employee).to receive(:save)`.
- **Email case inconsistency** — `RowAttrs.extract` now downcases email
  (moved from `STRING_FIELDS` to a new `DOWNCASE_FIELDS`). Before this,
  in-file dedupe compared `.downcase` but persistence kept the original case
  and the DB unique index is case-sensitive, so cross-file `Alice@x.com` +
  `alice@x.com` would both persist. Downcasing on ingest keeps in-file
  dedupe, persistence, and the DB check aligned. Two specs added: mixed-case
  in-file, and mixed-case across imports.
- **Stream + batch deferred to M10** — the plan's §risks entry ("Stream rows;
  batch inserts; never load the whole sheet") is not yet honoured; `CSV.parse`
  loads the whole table and each row inserts individually. Manual test M6.8
  (<30s, <500 MB RSS for 10k rows) is the guard until M10 revisits it as an
  automated benchmark. Deferring rather than doing it now because streaming
  changes the header-validation contract (headers arrive with the first row,
  not up-front) and batch inserts bypass the per-row validations that this
  service relies on.
- **`maybe_create_salary` mixed return type** — replaced
  `return error(...) && false` with `error(...); return false` so both
  branches return the same boolean. Behaviour unchanged.
- **Test literal `'\n'` bug** — the "missing required columns" request spec
  used a single-quoted `'employee_number\nEMP001'` (literal backslash-n).
  Rewritten with an interpolated newline and a real second column.

## Working agreements

- **Nothing is pushed to GitHub without explicit approval.** The commit history is a
  deliverable in its own right and must read cleanly.
- Local commits are treated as **draft** until approved — they can be amended,
  squashed, reordered, or split before anything is published.
- Before any push, the full commit sequence (messages + diffstat) is reviewed.

## Environment note

The stack (Rails API + PostgreSQL, React SPA) is scaffolded locally under `backend/`
and `frontend/`. Work on this project from a **local** Claude Code session so the agent
can read the real tree, run migrations, and run tests directly. Cloud sessions only see
what has been pushed to GitHub.

## M0 decisions (2026-08-23)

### Database: SQLite → PostgreSQL 16

The scaffolded app used SQLite. Swapped to PostgreSQL (`gem "pg"`, `database.yml`
rewritten for env-driven `DATABASE_URL`). The plan's query design depends on
PostgreSQL-only features that SQLite cannot provide: `DISTINCT ON` (§5 hot path for
current salary), `percentile_cont` (M7 median), `jsonb` (`audit_events.changes`),
native `enum` types (`role`, `status`, `region`), and `numeric(18,8)` for
`exchange_rates.rate_to_usd`. SQLite's lack of exact decimal arithmetic makes
`rate_to_usd` a float — silently wrong for every money conversion. The switch to
PostgreSQL is the only path that makes the full schema buildable without compromising
the data model.

### Test framework: Minitest → RSpec + FactoryBot

Scaffolded `backend/test/` (Minitest) removed; `backend/spec/` created with `rspec-rails`
and `factory_bot_rails`. The conventions in CLAUDE.md mandate RSpec throughout; the two
frameworks cannot coexist cleanly. FactoryBot replaces fixtures — factories compose
better and make the negative-case specs named in each milestone table legible without
fixture archaeology.

### Ruby version pinned to 3.3.6

`backend/.ruby-version` and the Gemfile `ruby` directive updated to match the local
runtime (`ruby -v` → 3.3.6). The original scaffold specified 3.1.4, which is EOL and
mismatched the installed runtime, causing `Bundler::RubyVersionMismatch` on every
`rails` invocation. CI pins to `ruby-version-file: backend/.ruby-version` so the
version is declared once and the CI matrix tracks it automatically.
