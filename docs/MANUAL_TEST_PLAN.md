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
| M1.5 | Attempt `Employee.first.destroy` in console — does it raise or return false? | Hard-delete path must not exist (no `dependent: :destroy` anywhere in the chain) |
| M1.6 | Run `bin/rails db:seed` a second time — does it stay idempotent (no duplicate-key errors)? | `find_or_create_by!` vs. `create!` — re-seeding a live database must be safe |

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
