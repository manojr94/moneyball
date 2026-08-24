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
