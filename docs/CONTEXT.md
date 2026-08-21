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
| **Currency** | Store local currency + USD normalization, with the FX rate snapshotted per record | Cross-country analytics needs a common unit, but converting at read time would make historical reports silently change as rates move. Snapshotting keeps past figures stable. |
| **Band scope** | Pay zones, with countries mapped into them | Per-country bands would run to thousands of hand-maintained rows at ACME's size — the spreadsheet problem rebuilt inside the app. A single-country zone still gives per-country precision where a market is genuinely distinct, so nothing is lost. |
| **Region tier** | Yes — a `region` column on `countries`, not a table | "EMEA vs APAC spend" is a week-one question. Regions are a fixed, short, behaviourless list, so a column suffices; adding it later would mean a migration plus a backfill of every country. |
| **Band denomination** | Local currency per band, normalized to USD at comparison time | Comp teams set bands in local terms, so currency is part of a band's identity. Normalizing at evaluation makes the currency-mismatch case defined behavior rather than an error. |

## Architectural decisions (proposed, not yet built)

1. **Salary is an append-only, effective-dated series** — a `salaries` table with
   `effective_date`, not a mutable `salary` column on `employees`. Makes point-in-time
   questions answerable, makes the audit trail structural rather than bolted on, and
   means no edit can destroy history. This is the load-bearing decision in the whole
   design; most other things follow from it.

2. **Money as integer minor units** (`amount_cents` + `currency`), never floats.
   Floating-point currency is a correctness bug, not a style preference.

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
