# Moneyball — working notes for Claude

Salary management for a ~10,000-employee multinational: effective-dated pay history,
multi-currency, compa-ratio against pay bands. Rails API + React SPA + Postgres.

## Read first

| File | Holds |
|---|---|
| `docs/REQUIREMENTS.md` | Goal, scope, and what is deliberately out of scope |
| `docs/IMPLEMENTATION_PLAN.md` | Schema, milestones, test strategy, performance plan, branching |
| `docs/CONTEXT.md` | Decision log — *why* things are the way they are, including superseded decisions |

Read those rather than re-deriving. If a decision seems wrong, check `CONTEXT.md` before
changing it — it may already have been argued and settled.

## Invariants

Breaking any of these silently corrupts the data model. None are inferable from the
schema alone.

- **Never `UPDATE` a salary row.** A raise, a correction, a currency change — all are new
  effective-dated rows. Current pay is "greatest `effective_date <= target`".
- **Never edit or delete an `exchange_rates` row.** The table is append-only. A correction
  is a new row with a later `effective_date`. Historical reporting depends on this;
  an in-place edit silently rewrites past reports.
- **Never store a USD amount as a column.** USD is derived at read time from
  `exchange_rates`, with the rate date as an explicit parameter. Nobody is paid in USD.
- **Never handle money as a bare integer.** Always through the Money type. Minor units
  follow each currency's ISO 4217 exponent — JPY has none, KWD has three.
- **Never hard-delete a user or employee.** `audit_events` references them. Deactivate.
- **Never block data entry on missing configuration.** An employee in an unconfigured
  country saves; the country is auto-created and flagged `needs_review`.

## Vocabulary

- **Minor units** — the currency's smallest denomination per ISO 4217. Not "cents".
- **Pay zone** — what bands key on. Countries map into zones; comparable markets share one.
- **Region** — the analytics rollup (NA / LATAM / EMEA / APAC). Independent of pay zone:
  EMEA is one region spanning several zones.
- **Effective-dated** — a row valid from a date, superseded by a later row, never mutated.
- **Compa-ratio** — salary ÷ band midpoint. 1.0 means paid at midpoint.
- **Rate date** — which day's exchange rate a query converts at. Always explicit.

## Conventions

- **Tests**: RSpec, FactoryBot (factories, not fixtures). Every feature gets positive
  *and* negative cases. Edge cases named in the milestone table are requirements.
- **Commits**: Conventional Commits, one logical change each, suite green at every commit.
  Bodies explain *why* when the diff doesn't.
- **Branches**: one per milestone, `feat/mNN-slug`. PR per branch.
- **Merging**: rebase-and-merge. **Never squash** — it would collapse the incremental
  history this repository exists to demonstrate.

## Rules for agent sessions

- **Never push without explicit approval.** Commit locally; local commits stay amendable.
  Show the commit sequence before proposing a push.
- **Update the decision log.** Any design decision made during a milestone is appended to
  `docs/CONTEXT.md` with its reasoning *before* the PR opens. Superseded decisions are
  kept and marked, not deleted.
- **No new dependencies** without stating why in the commit body.
- **Model selection.** Default to Sonnet — the architecture is settled, so most milestones
  are implementation against a spec. Escalate to Opus for band resolution edge cases (M8),
  analytics query design (M7), import concurrency (M6), or any test failing twice for
  reasons you don't understand. Escalate on evidence of difficulty, not on a schedule.

## Commands

Filled in by M0. Until then, verify before relying on any of these.

```bash
# backend (from backend/)
bin/rails db:create db:migrate   # set up the database
bin/rails db:seed                # reference + demo data
bundle exec rspec                # test suite
bundle exec rubocop              # lint
bin/rails s                      # API on :3000

# frontend (from frontend/)
npm install
npm run dev                      # SPA on :5173
npm test
npm run lint
```
