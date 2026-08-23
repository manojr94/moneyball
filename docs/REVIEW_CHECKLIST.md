# Review Checklist

For reviewing a milestone branch before its PR merges.

**Review in a session that did not write the code.** A session reviewing its own diff
rationalizes rather than reviews — it already believes the code is correct, because it
just decided that. Start fresh, and read the diff as though hunting for a bug you know
is there.

**Skip anything RuboCop or ESLint already enforces.** Style, formatting, and naming
conventions are CI's job. Review attention spent there is attention not spent on the
items below.

## 1. Invariants

These are the ways this design degrades silently. None produce a test failure on their
own, and none are visible in a schema — they only show up in a diff.

- [ ] Does anything **`UPDATE` a salary row**? Corrections are new effective-dated rows.
      Look for `update`, `update!`, `save` on an existing `Salary`, and `upsert`.
- [ ] Does anything **write to `exchange_rates` other than an insert**? The table is
      append-only. An `update` or `destroy` there rewrites history retroactively.
- [ ] Is a **USD amount stored** anywhere — a column, a cache, a memoized attribute? USD
      is derived at read time from an explicit rate date.
- [ ] Does the **rate date reach the query**, or does something default to "latest" and
      silently answer a different question than the caller asked?
- [ ] Does **money touch a bare integer** outside the Money type? Arithmetic on
      `amount_minor_units` directly is a bug even when the result looks right — it will
      be wrong for JPY or KWD.
- [ ] Is a **user or employee hard-deleted**? `audit_events` references them; deletion
      orphans the trail. Deactivate.
- [ ] Does any path **block on missing configuration**? An employee in an unconfigured
      country must save, with the country auto-created and flagged.

## 2. Tests

- [ ] Does every new behavior have a **negative case**, not just a happy path?
- [ ] Are the **edge cases named in the milestone table** actually covered, by name?
      They are requirements, not suggestions.
- [ ] Do tests assert on **values**, or merely that something didn't raise? A spec that
      only checks `response.status == 200` tests almost nothing.
- [ ] Is there a test that would **fail if the invariant above were violated**? For an
      effective-dated model, that means a test proving an update is rejected.
- [ ] Are factories building **realistic** data? A factory that only ever produces USD
      salaries hides every currency bug in the suite.

## 3. Queries and performance

- [ ] Does any new query run **inside a loop**? The append-only design makes N+1 the
      default failure mode, not an exotic one.
- [ ] Does every new query have an **index that serves it**, and is that index listed in
      the plan's table with its query?
- [ ] Is aggregation happening **in SQL**, or are rows being loaded into Ruby to be
      counted, summed, or sorted?
- [ ] Does pagination use **keyset**, not `OFFSET`?
- [ ] For anything touching all employees: was it run against the **10k seed**, or only
      against fixtures?

## 4. Migrations

- [ ] Is the migration **reversible**, or is `down` missing or lossy?
- [ ] Does it add a column with a default to a large table in a way that **locks**?
- [ ] Are new foreign keys **indexed**?
- [ ] Do new columns match the **types stated in the plan** — `bigint` for minor units,
      `numeric` for rates, `date` for effective dates, `timestamptz` for instants?

## 5. API and authorization

- [ ] Is authorization enforced **server-side**, not just by hiding UI controls?
- [ ] Is it checked at the **object level**, not only the endpoint level? Can a Viewer
      reach a record by guessing an ID?
- [ ] Does the endpoint **leak more than it should** — internal IDs, other employees'
      pay, full error backtraces?
- [ ] Are errors **actionable** to an HR manager, or do they surface as raw exceptions?

## 6. Process

- [ ] Are design decisions appended to **`docs/CONTEXT.md`** with reasoning?
- [ ] Does a milestone with user-visible behavior add checks to
      **`docs/MANUAL_TEST_PLAN.md`**?
- [ ] Is the commit count justified by **logical changes**, not by files touched?
- [ ] Do commit bodies explain **why** where the diff doesn't?
- [ ] Any **new dependency** — is the reason stated in the commit body?

## 7. Posting the review to GitHub

The intended workflow for a milestone review:

1. **Review first, fix second.** Run the review against the branch *before* committing fixes. This creates an authentic paper trail: findings visible as PR comments, fixes landing as a subsequent commit.
2. **Post findings as a PR review** using `curl` against the GitHub API (no `gh` CLI on this machine — see `~/.claude/CLAUDE.md` for the exact command and gotchas).
3. **Use `"event": "COMMENT"`**, not `"REQUEST_CHANGES"` — GitHub rejects the latter when reviewer and PR author are the same account.
4. **Test with a single comment before posting the full review.** A single bad line reference fails the entire batch silently.
5. **Commit and push the fixes** after the review is posted. The PR then shows: original code → review comments → fix commit.

## 8. The question worth asking last

> If this milestone is wrong, how would we find out?

If the answer is "a user notices a wrong number months later," the milestone needs a
test or an alarm it doesn't have yet. Silent wrongness is the characteristic failure of
a compensation system: every figure looks plausible, and nothing crashes.
