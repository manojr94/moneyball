# M12 Manual Test Plan — Deploy & Docs

Tests to run against the **deployed instance** after M12 ships. The goal is a smoke test
confirming the production build behaves identically to local dev.

> **Cold-start note:** The API runs on Render's free tier and sleeps after 15 minutes of
> inactivity. The **first request after sleep takes ~30 seconds** — this is expected. All
> subsequent requests should respond in under 500ms.

---

## Prerequisites

- Demo URL (Render + Cloudflare Pages) recorded here: `__________________`
- Admin credentials: `admin@example.com` / `password`
- Viewer credentials: `viewer@example.com` / `password`

---

## M12.1 — Cold start

| Step | Expected |
|---|---|
| Open the demo URL with no prior visits (or in a private window) | May see a blank page or spinner for up to 30s |
| After the API wakes, the login page renders | Login form visible |

## M12.2 — Authentication

| Step | Expected |
|---|---|
| Sign in as `admin@example.com` | Redirected to `/employees`; nav shows Employees, Analytics, Bands, Import |
| Sign out | Redirected to `/login`; token removed from localStorage |
| Sign in as `viewer@example.com` | Redirected to `/employees`; **Import tab absent** from nav |
| Sign out as viewer | Redirected to `/login` |

## M12.3 — Employee list (admin)

| Step | Expected |
|---|---|
| Sign in as admin, navigate to `/employees` | Table loads; ~25 employees shown with pagination |
| Click **Next** | Next page loads without error |
| Click **Previous** | Returns to first page |
| Open **Filters**, set Status = "inactive" | Table reloads with inactive employees only |
| Click **Name** column header | Re-sorts by last name ascending; chevron appears |
| Click **Name** again | Re-sorts descending; chevron flips |

## M12.4 — Employee detail & salary timeline

| Step | Expected |
|---|---|
| Click any employee number | Detail page loads with employee info and salary timeline |
| Click **Record salary change** | Modal opens with amount, currency, date, reason fields |
| Submit a raise (e.g. 90000 USD) | Modal closes; salary timeline refreshes with new row at top |
| Sign out, sign in as viewer | Detail page visible but **Record salary change** button absent |

## M12.5 — Analytics

| Step | Expected |
|---|---|
| Navigate to `/analytics` | Pay table loads grouped by Region |
| Change **Group by** to Department | Table reloads with department rows |
| Change **As of** to a past date | Headcount and spend figures update |
| Switch to **Compa-ratio** tab | Compa-ratio table loads with avg ratio and bucket counts |
| Switch to **Band coverage** tab | Uncovered combinations listed (at least one row for Designer L4) |

## M12.6 — Salary bands

| Step | Expected |
|---|---|
| Navigate to `/bands` | Band table loads with effective bands for today |
| Change **Effective on** to a past date | Table updates |
| As admin, click **New band** | Form appears with all required fields |
| Submit a new band | Table refreshes with new row |
| Sign in as viewer; navigate to `/bands` | Table visible but **New band** button absent |

## M12.7 — CSV import (admin only)

| Step | Expected |
|---|---|
| Navigate to `/import` as viewer | Redirected to `/employees` |
| Sign in as admin; navigate to `/import` | File picker and Preview button visible |
| Upload `demo_import.csv` (repo root), click **Preview** | Preview shows row summary, no errors |
| Click **Confirm import** | Success message: "N employees added" |
| Upload a CSV with a bad row (e.g. invalid date), Preview | Row error listed; Confirm button absent |

## M12.8 — TypeScript build integrity

| Step | Expected |
|---|---|
| `cd frontend && npx tsc --noEmit` | Zero errors |
| `cd frontend && npm run build` | Build succeeds; `dist/` produced |
| `cd frontend && npm test` | 67 tests pass |

## M12.9 — Docker build

| Step | Expected |
|---|---|
| `docker build -t moneyball-api ./backend` | Image builds successfully using Ruby 3.3.6 and PostgreSQL libs |
| `docker build -t moneyball-web ./frontend` | Multi-stage nginx image builds; SPA assets in `/usr/share/nginx/html` |
