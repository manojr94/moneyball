# Moneyball — Salary Management for ACME

**Status:** Draft v1 · **Owner:** HR Systems · **Last updated:** 2026-08-21

## 1. Goal

ACME's HR team manages compensation for ~10,000 employees across multiple countries in
spreadsheets. Files are emailed, forked, and manually reconciled; there is no reliable
history of what someone was paid and when, no safe concurrent editing, and answering a
question like *"are our engineers in Germany underpaid relative to band?"* takes days of
manual work.

Moneyball replaces those spreadsheets with a web application that gives HR managers a
single authoritative record of compensation, and lets them answer questions about how the
organization pays people without exporting anything.

**Success looks like:** an HR manager can migrate the existing spreadsheets in, record a
raise in under a minute, and answer a pay question in under a minute — with a complete,
auditable history of every change.

## 2. Scope & Features (v1)

| # | Feature | What it delivers |
|---|---------|------------------|
| F1 | **Employee records** | Create, view, update, and deactivate employees: name, email, country, department, job title, level, hire date, employment status. |
| F2 | **Effective-dated salary history** | Compensation is an append-only series of records (amount, currency, effective date, reason), not a mutable field. "What did this person earn in March 2025?" is always answerable, and no edit destroys history. |
| F3 | **Multi-currency support** | Salaries stored in local currency *and* normalized to USD using the exchange rate captured at the time of the record, so cross-country comparison is possible without rewriting history when rates move. |
| F4 | **Search, filter & pagination** | Server-side filtering by country, department, level, and status across 10k+ employees, with sorting and pagination. |
| F5 | **Spreadsheet import** | Bulk CSV/XLSX import with row-level validation, a dry-run preview, and an all-or-nothing commit — the migration path off Excel. |
| F6 | **Compensation analytics** | Aggregate views: headcount, total spend, and min / median / average / max pay, grouped by region, country, department, or level, with a point-in-time filter. |
| F7 | **Salary bands & compa-ratio** | Bands (min/mid/max per role, level, and pay zone) as first-class data; each employee's compa-ratio against their band, with distribution buckets to surface who sits below, within, or above range. |
| F8 | **Roles & authentication** | Two roles: **HR Admin** (full read/write) and **Viewer** (read-only analytics, no PII edits). Authenticated sessions; authorization enforced server-side. |
| F9 | **Audit trail** | Every salary and band change records who changed what, when, and why. |

## 3. Out of Scope (v1) — and why

| Deliberately excluded | Reasoning |
|---|---|
| **Payroll execution / payslips / tax** | Moneyball is a system of record for *compensation decisions*, not a payroll engine. Payroll is jurisdiction-specific, heavily regulated, and a separate product category — ACME's existing payroll provider stays authoritative. We integrate later via export, not by rebuilding it. |
| **Pay equity / demographic gap analysis** | High value, but requires protected-attribute data (gender, ethnicity) with its own legal, consent, and access-control obligations. Modeling that carelessly is worse than not shipping it. Deferred until the data model and permissions are proven. |
| **Live FX rate feed** | v1 uses rates stored per salary record, seeded from a static table. A live feed adds an external dependency and failure mode for marginal v1 benefit; the schema already accommodates it. |
| **Approval workflows (multi-step raise sign-off)** | Requires org-hierarchy modeling and a state machine. v1 targets the HR team as the trusted editor; workflow becomes valuable only once more roles exist. |
| **Bonuses, equity, benefits** | Real parts of total compensation, but each has distinct lifecycle and vesting semantics. v1 proves the model on base salary; the effective-dated design extends to them without rework. |
| **Self-service employee portal** | Different audience, different threat model, and 10,000 more users. v1's user is the HR manager. |
| **Org hierarchy / manager reporting lines** | Not needed to answer v1's questions, and correctly modeling a mutable org tree is a project in itself. |

## 4. Constraints & Non-Functional Requirements

- **Scale:** correctness and responsiveness at 10,000 employees with multi-year salary
  history (~100k+ salary records). List and analytics queries target < 500ms.
- **Auditability:** no destructive edits to compensation history.
- **Data integrity:** monetary values stored as integer minor units, never floats.
- **Stack:** Ruby on Rails (API-only) + PostgreSQL; React SPA frontend.
- **Deployment:** a publicly reachable demo with seeded, synthetic data.

## 5. Geographic model

Countries are a reference table carrying two independent groupings, because compensation
and reporting do not slice the world the same way:

- **Pay zone** — what salary bands are keyed on. Countries with comparable markets share
  a zone (`Western Europe`), and a zone may hold a single country where that market is
  distinct (`Switzerland`). This keeps the band count in the dozens rather than the
  thousands, which is what makes bands maintainable by hand.
- **Region** — the analytics rollup (NA / LATAM / EMEA / APAC). EMEA is one region but
  several pay zones, which is precisely why these are separate fields.

Bands are denominated in their own local currency; comparison against a salary is
normalized to USD at evaluation time.
