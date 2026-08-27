# Moneyball

Salary management for a ~10,000-employee multinational. Effective-dated pay history, multi-currency compa-ratio against salary bands, and compensation analytics — built as a portfolio project demonstrating production Rails + React patterns.

**Live demo:** [moneyball-api.onrender.com](https://moneyball-api.onrender.com) · **Note:** The API runs on Render's free tier and may take ~30 seconds to wake from sleep on first request. Subsequent requests are fast.

---

## Architecture

```
React SPA (Vite + TypeScript)
        │  JSON over HTTPS, JWT Bearer token
        ▼
Rails 7 API-only
  ├── Controllers      thin: auth → service/query → serializer
  ├── Services         write-side domain logic (RecordSalaryChange, ImportEmployees)
  ├── Queries          read-side composable objects (EmployeeQuery, PayAnalytics)
  ├── Models           persistence + invariants only
  └── Serializers      explicit JSON shaping
        ▼
PostgreSQL 16
```

## Key design decisions

**Salary is append-only.** A raise is an `INSERT`, never an `UPDATE`. Current pay is "the row with the greatest `effective_date ≤ today`". This makes every point-in-time question answerable and makes the audit trail structural.

**USD is derived at read time.** Salaries are stored in local currency. An append-only `exchange_rates` table supplies rates; the query caller provides an explicit `rate_date`. Nobody is paid in USD — the dollar figure is a lens for cross-country comparison, not a fact about a transaction.

**Money as integer minor units.** `amount_minor_units` + `currency`, never floats. The column name avoids "cents" because JPY has no subunit and KWD has three. The `money-rails` gem knows each currency's ISO 4217 exponent.

**Band resolution is a service object.** `BandResolver` handles the interesting edge cases explicitly: no matching band, country in no pay zone, band in a different currency than the salary, band changed mid-period. Each failure mode is a named symbol, not a boolean.

**Keyset pagination.** `OFFSET N` on a 10k-employee table scans N rows to discard them. Keyset pagination uses a cursor (opaque base64 JSON) encoding the last-seen sort value and id — an indexed range scan regardless of position.

## Documentation

| File | Purpose |
|---|---|
| [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) | Project goals and deliberate out-of-scope decisions |
| [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) | Schema, milestones, test strategy, performance plan |
| [`docs/CONTEXT.md`](docs/CONTEXT.md) | Decision log — why things are the way they are, including superseded decisions |
| [`docs/adr/`](docs/adr/) | Architecture Decision Records (effective-dated salary, FX derivation, BandResolver, JWT revocation, keyset pagination) |
| [`docs/MANUAL_TEST_PLAN.md`](docs/MANUAL_TEST_PLAN.md) | Per-milestone manual test coverage (M0–M11.5) |
| [`docs/M12_MANUAL_TEST_PLAN.md`](docs/M12_MANUAL_TEST_PLAN.md) | Production smoke test checklist |
| [`docs/REVIEW_CHECKLIST.md`](docs/REVIEW_CHECKLIST.md) | Pre-merge review checklist for invariants, edge cases, and security |

---

## Setup

### Prerequisites

- Ruby 3.3.6, Bundler
- Node 20+
- PostgreSQL 16

### Backend

```bash
cd backend
bundle install
bin/rails db:create db:migrate
bin/rails db:seed          # reference data + 10k synthetic employees
bin/rails s                # API on :3000
```

### Frontend

```bash
cd frontend
npm install
npm run dev                # SPA on :5173
```

The SPA reads `VITE_API_URL` (defaults to `http://localhost:3000`).

### Demo access

Access is invitation-only. Generate a token from the Rails console (or Render shell) and share the signup URL:

```bash
token = Invitation.create!.token
puts "https://your-app.pages.dev/signup?token=#{token}"
```

`demo_import.csv` (repo root) contains 25 synthetic employees for testing the import flow. After import, the Band Coverage tab shows the Designer L4 gap across pay zones.

---

## Docker (local)

```bash
# requires RAILS_MASTER_KEY from backend/config/master.key
RAILS_MASTER_KEY=$(cat backend/config/master.key) docker compose up
```

- API: `http://localhost:3000`
- SPA: `http://localhost:8080`

---

## Deployment (Render + Cloudflare Pages)

### API — Render (free tier)

1. Create a new **Web Service** on [render.com](https://render.com), connect this repo.
2. Set **Dockerfile path** to `backend/Dockerfile`, **Docker context** to `backend/`.
3. Add a **PostgreSQL** database (free tier) and link it — Render auto-sets `DATABASE_URL`.
4. Set environment variables:
   - `SECRET_KEY_BASE` — generate with `bundle exec rails secret`
   - `RAILS_MASTER_KEY` — contents of `backend/config/master.key`
5. After first deploy, seed: **Shell** → `bin/rails db:seed`

> **Free tier note:** the service sleeps after 15 minutes of inactivity. The first request after sleep takes ~30 seconds. Add a note to your demo page so reviewers aren't confused.

### Frontend — Cloudflare Pages (free, no card required)

1. Connect this repo on [pages.cloudflare.com](https://pages.cloudflare.com).
2. **Build command:** `cd frontend && npm ci && npm run build`
3. **Build output directory:** `frontend/dist`
4. **Environment variable:** `VITE_API_URL=https://your-render-api-url.onrender.com`

---

## Test suites

```bash
# Backend
cd backend && bundle exec rspec      # ~200 specs
cd backend && bundle exec rubocop    # zero offences

# Frontend
cd frontend && npm test              # 67 Vitest + Testing Library specs
cd frontend && npx tsc --noEmit      # zero type errors
```

---

## Milestones

| # | Milestone | What it delivered |
|---|---|---|
| M0 | Scaffolding & CI | Rails API, Vite SPA, RSpec, FactoryBot, RuboCop, ESLint, GitHub Actions |
| M1 | Geography & employees | `countries`, `departments`, `employees`, auto-create unconfigured countries |
| M2 | Money & FX | `money-rails`, append-only `exchange_rates`, `FxConverter` with as-of lookup |
| M3 | Salary history | `salaries`, `RecordSalaryChange`, point-in-time salary queries |
| M4 | Auth & roles | JWT auth, `hr_admin` / `viewer` roles, Pundit-style policies |
| M5 | Employee API | Filter, sort, keyset pagination; create/update endpoints |
| M6 | CSV import | Row validation, dry-run preview, atomic commit, 10k-row support |
| M7 | Analytics | Headcount/spend/median by region/country/department/level; explicit rate date |
| M8 | Bands & compa-ratio | `salary_bands`, `BandResolver`, compa-ratio, band coverage report |
| M9 | Frontend | Employee list, detail + salary timeline, raise form, analytics dashboard |
| M10 | Tailwind & UX | Tailwind v3, sortable columns, filter bar tooltips, band coverage copy |
| M11 | Seed & performance | 10k employees, streaming CSV import, batch inserts, benchmark harness |
| M11.5 | Cleanup | Department filter, extended sort, band create form, analytics refactor, invitations |
| M12 | Deploy & docs | Dockerfile, Render deployment, TypeScript migration, README, ADRs |
