# ADR 004 — JWT authentication with token_version revocation

**Status:** Accepted

## Context

The API is consumed by a React SPA. Auth must support two roles (hr_admin, viewer) and immediate revocation when a user is deactivated or signs out.

## Decision

Authentication uses JWT (via the `jwt` gem). Each token embeds `user_id`, `role`, and `token_version`. The `users` table carries a `token_version` integer counter. Validation rejects any token whose embedded version does not match the current counter.

Revocation bumps `token_version` — invalidating all outstanding tokens for that user immediately, before they expire. The 24-hour token lifetime means the window between bump and expiry is at most one day if revocation fails.

Authorization uses Pundit-style policy objects without the Pundit gem. `ApplicationPolicy` exposes `read?` and `write?` predicates; `ApplicationController#authorize!` raises `NotAuthorizedError` (→ 403) if the policy denies the action.

## Consequences

**Good:**
- Most requests validate without a DB read — only the `user_id` lookup is required.
- Deactivating a user immediately invalidates their token via `token_version` bump.
- No session table to maintain.
- Two-role model is simple enough for hand-rolled policies; Pundit's full machinery is not needed.

**Cost:**
- JWTs cannot be selectively invalidated (e.g. "revoke this device but not that one") without per-token storage, which defeats the stateless benefit. Acceptable at this scale.
- `update_all` or direct SQL can bypass the `token_version` guard — documented as a known limitation.

## Alternatives considered

**Cookie session** — `token_version` in the schema is a JWT pattern; it does not apply to cookie sessions (which revoke by deleting the session row). Cookie sessions also require extra CORS configuration for a cross-origin SPA.

**Pundit gem** — adds a dependency and convention overhead that is not justified for two roles. The pattern is identical; the gem is optional.
