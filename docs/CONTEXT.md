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
