# Example: Fix a Logout-on-Refresh Authentication Bug

This walkthrough follows a bug-fix run: the debugger reproduces, isolates, and root-causes the problem before touching code, the tester locks the fix in with a regression test that would have caught the original bug, and the reviewer approves. It shows why AGEX routes bugs to the debugger instead of straight to the coder.

## Scenario

`notes-app` is an npm workspaces monorepo:

| Path | Contents |
|---|---|
| `web/` | React 18 single-page app built with Vite and TypeScript. In development, Vite proxies `/api` to `http://localhost:4000` |
| `api/` | Express 4 and TypeScript API on PostgreSQL, tested with Jest and supertest (`npm test --workspace api`). `npm run seed --workspace api` creates a local `demo` user |
| `deploy/nginx.conf` | Production: nginx serves the SPA and proxies `/api/` to the API, so both share one origin |

The authentication design is sound on paper:

- `POST /api/auth/login` returns a 15-minute JWT access token in the response body and sets a `refresh_token` cookie (`HttpOnly`, `SameSite=Strict`, `Secure` in production, 30 days). Refresh tokens are random values, stored hashed, and rotated on every use.
- The SPA keeps the access token only in memory (React state in `web/src/auth/AuthProvider.tsx`) so that injected scripts cannot read it from storage. On startup it calls `POST /api/auth/refresh` to restore the session.

Last week a commit titled "Serve the API under /api on the web origin" moved every route under an `/api` prefix. Since then, users report: "After logging in, refreshing the page sends me back to the login screen. It also happens if I leave the tab open for a while." All tests are green.

## The Command

```text
/agex Fix the auth bug where users are logged out after refreshing the page
```

## What AGEX Does

1. **Complexity classification: MEDIUM, task type bug.** One component (authentication, spanning the API's cookie handling and the SPA's session restore), a handful of files, and an unknown root cause. The routing table sends bugs to the debugger first, so the chain is debugger → tester (regression test) → reviewer, with no planner, researcher, or architect. During read-only orientation the orchestrator greps for `refresh` and hands the debugger starting points: `web/src/auth/AuthProvider.tsx`, `api/src/auth/auth.routes.ts`, and `api/src/auth/cookies.ts`.
2. **debugger → DebugReport, FIXED.** The debugger works through reproduce, isolate, diagnose, fix, verify:
   - **Reproduce.** It logs in with curl and a cookie jar, then calls the refresh endpoint with the same jar: 401 `missing_refresh_token`. The `Set-Cookie` header shows `Path=/auth/refresh`.
   - **Isolate.** Sending the same cookie with an explicit `Cookie` header makes the refresh succeed, so token validation and rotation work; only delivery fails. `git log -S "/api/auth"` finds the commit that moved the router mount to `/api/auth` without touching the cookie path. The existing test at `api/tests/auth.test.ts:88` sets the `Cookie` header by hand, which bypasses path matching; that is why CI stayed green.
   - **Diagnose.** A browser only sends a cookie when the request path starts with the cookie's `Path`. `/api/auth/refresh` does not start with `/auth/refresh`, so the cookie is never sent. Because the access token lives only in memory, every reload and every token expiry depends on that refresh call, and both end in a logout. The debugger also finds a latent bug with the same cause: the cookie never reached the logout endpoint either, so logout cleared the cookie but never revoked the token server-side.
   - **Fix.** A shared `AUTH_BASE_PATH` constant now drives both the router mount and the cookie path (`/api/auth`), so refresh and logout both receive the cookie and the two values cannot drift apart again. The debugger explicitly rejects the tempting workaround of storing the access token in `localStorage`: it would hide the symptom and expose the token to any cross-site scripting bug.
   - **Verify.** The curl sequence now returns 200 with a rotated cookie, and the API suite still passes 47 of 47.
3. **tester → TestReport, PASS.** The tester adds `api/tests/auth.refresh.test.ts`, which uses supertest's `request.agent(app)`. Its cookie jar applies `Path` matching the way a browser does, so these tests exercise real cookie delivery. It also updates the old hand-written `Cookie` header tests to use the agent. The API suite now passes 52 of 52.
4. **reviewer → ReviewVerdict, APPROVED.** No blocking issues. Two LOW, non-blocking notes: users who signed in before the deploy hold a cookie with the old path and must sign in once more, and no browser-level test covers the reload flow yet.
5. **Quality gate and AgexReport, DONE.** TestReport PASS, ReviewVerdict APPROVED, no security findings open. Three dispatches in total; neither feedback loop was needed.

## Illustrative Artifact Excerpts

The excerpts below are illustrative. They show the envelope, section order, and level of detail you should expect, abridged for length. They are not captured output from a recorded run. Token values are redacted to their first four characters.

### DebugReport

```markdown
<!-- agex:artifact type=DebugReport version=1 -->
## DebugReport: Refresh cookie never sent after the API moved under /api
**Producer:** debugger · **Status:** FIXED · **Confidence:** HIGH

### Symptom
After a page reload the SPA redirects to /login. The access token lives only in React state
(web/src/auth/AuthProvider.tsx:22); on mount the SPA calls POST /api/auth/refresh
(web/src/auth/AuthProvider.tsx:41), which returns 401, and the provider redirects (line 47).
The same happens when the 15-minute access token expires. Node 20, Express 4.21.

### Reproduction
- Command: `curl -s -D - -c /tmp/agex-jar -H 'Content-Type: application/json' -d '{"username":"demo","password":"demo-password"}' http://localhost:4000/api/auth/login`
- Observed output: `Set-Cookie: refresh_token=9f3c****; Max-Age=2592000; Path=/auth/refresh; Expires=Tue, 27 Oct 2026 09:12:44 GMT; HttpOnly; SameSite=Strict`
- Command: `curl -s -i -b /tmp/agex-jar -X POST http://localhost:4000/api/auth/refresh`
- Observed output: `HTTP/1.1 401 Unauthorized` with body `{"error":"missing_refresh_token"}`

### Isolation
- The jar holds the cookie but curl, like a browser, only sends it when the request path starts with
  the cookie Path (RFC 6265, section 5.1.4). Sending the same value in an explicit Cookie header
  returns 200, so validation and rotation work; only delivery fails.
- `git log -S "/api/auth" --oneline -- api/src` → a41c9e2 "Serve the API under /api on the web origin":
  it changed the mount at api/src/app.ts:31 but not the cookie path at api/src/auth/cookies.ts:12.
- api/tests/auth.test.ts:88 sets the Cookie header by hand, bypassing path matching, so CI stayed green.
- The logout route never received the cookie either (before or after a41c9e2), so logout cleared the
  cookie but never revoked the refresh token server-side.

### Root Cause
`api/src/auth/cookies.ts:12` — the refresh cookie Path is hardcoded to /auth/refresh. Since a41c9e2
mounts the auth router at /api/auth, the browser never sends the cookie to /api/auth/refresh. The
access token is deliberately kept in memory only, so every reload and every expiry depends on that
refresh call, and both end in a logout.

### Fix Applied
- `api/src/auth/paths.ts` — new; exports AUTH_BASE_PATH = '/api/auth'
- `api/src/app.ts` — mounts the auth router at AUTH_BASE_PATH instead of a string literal
- `api/src/auth/cookies.ts` — one shared refreshCookieOptions object with path AUTH_BASE_PATH, used by
  setRefreshCookie and clearRefreshCookie, so refresh and logout both receive the cookie and clearing
  targets the same path it was set with
- Not changed: web/src/auth/AuthProvider.tsx. Moving the access token to localStorage would hide the
  symptom and expose the token to any XSS; the in-memory design is correct.

### Verification
- Before: `curl -s -i -b /tmp/agex-jar -X POST http://localhost:4000/api/auth/refresh` → 401 {"error":"missing_refresh_token"}
- After: the same login and refresh sequence → 200 with a new accessToken and a rotated cookie with Path=/api/auth
- Related suite: `npm test --workspace api` → 47 passed, 0 failed, 0 skipped (47 before the fix too: no test covered cookie delivery)

### Regression Risk
Contained to auth cookies. Users who signed in before the deploy hold a cookie with Path=/auth/refresh
that is never sent; they must sign in once more. Requested from tester: regression tests that rely on a
cookie jar honoring Path, including logout revocation.
```

### TestReport

```markdown
<!-- agex:artifact type=TestReport version=1 -->
## TestReport: Regression tests for refresh-cookie delivery and logout revocation
**Producer:** tester · **Status:** PASS · **Confidence:** HIGH

### Test Suites Executed
- `npm test --workspace api -- auth.refresh` (exit code 0)
- `npm test --workspace api` (exit code 0)

### Pass/Fail Summary
| Suite | Passed | Failed | Skipped |
|---|---|---|---|
| api/tests/auth.refresh.test.ts | 5 | 0 | 0 |
| api, all suites | 52 | 0 | 0 |

### Tests Added or Updated
- `api/tests/auth.refresh.test.ts` — added; uses request.agent(app), whose cookie jar applies Path matching:
  login sets refresh_token with Path=/api/auth, HttpOnly, and SameSite=Strict; refresh through the agent
  returns 200 and a new access token; a rotated-out token is rejected; logout revokes the token so a
  later refresh returns 401; refresh without a cookie returns 401
- `api/tests/auth.test.ts` — updated; the refresh tests at lines 88-120 now use the agent instead of a
  hand-written Cookie header

### Edge Cases Covered
- Reusing a refresh token after rotation
- Refreshing after logout
- Missing cookie
- Exact Path attribute: the assertion would reject the pre-fix value Path=/auth/refresh recorded in the DebugReport

### Failure Traces
None

### Coverage
not measured (no coverage script or collectCoverage setting in api/jest.config.ts)

### Recommendation for Coder
None: all tests pass
```

### ReviewVerdict

```markdown
<!-- agex:artifact type=ReviewVerdict version=1 -->
## ReviewVerdict: Refresh cookie path fix and regression tests
**Producer:** reviewer · **Status:** APPROVED · **Confidence:** HIGH

### Summary
Reviewed the three-file fix and the new and updated tests. The root cause is addressed at its source,
the fix is minimal, and the tests exercise real cookie delivery. Two LOW notes, both non-blocking.

### Issues
| ID | Severity | Category | Location | Problem | Remediation |
|---|---|---|---|---|---|
| R-1 | LOW | edge-case | `api/src/auth/cookies.ts:12` | Sessions created before the deploy hold a cookie with Path=/auth/refresh that is never sent again | Non-blocking: tell users in the release notes that they will be asked to sign in once |
| R-2 | LOW | tests | `web/src/auth/AuthProvider.tsx:41` | No browser-level test covers reload, silent refresh, and restored session end to end | Non-blocking: add a Playwright test for this flow when E2E tests are introduced |

### Checks Performed
- [x] Logic and off-by-one
- [x] Null/undefined handling
- [x] Concurrency and shared state
- [x] Error handling
- [x] Security (OWASP Top 10)
- [x] Performance
- [x] Edge cases
- [x] Test adequacy
- [x] Project conventions

### What Is Good
- The cookie path derives from the same constant as the router mount, so they cannot drift apart again.
- The fix also closes the latent logout-revocation gap.
- The access token stays in memory; no storage-based workaround was introduced.
```

### AgexReport (abridged)

```markdown
<!-- agex:artifact type=AgexReport version=1 -->
## AgexReport: Users logged out after page refresh
**Producer:** orchestrator · **Status:** DONE · **Confidence:** HIGH

### Task
Fix the auth bug where users are logged out after refreshing the page. MEDIUM, routed as a bug.

### Outcome
Sessions survive page reloads and access-token expiry again, and logout now revokes the refresh token.

### Agents Deployed
| # | Agent | Artifact | Status | Cycle |
|---|---|---|---|---|
| 1 | debugger | DebugReport | FIXED | n/a |
| 2 | tester | TestReport | PASS | n/a |
| 3 | reviewer | ReviewVerdict | APPROVED | n/a |

### Changes
- Added: api/src/auth/paths.ts, api/tests/auth.refresh.test.ts
- Modified: api/src/app.ts, api/src/auth/cookies.ts, api/tests/auth.test.ts

### Verification Evidence
- `npm test --workspace api` → 52 passed, 0 failed, 0 skipped
- DebugReport: curl refresh 401 before the fix, 200 after
- ReviewVerdict: APPROVED (2 LOW, non-blocking)

### Open Issues & Escalations
- R-1 (LOW): existing sessions must sign in once after deploy.
- R-2 (LOW): no end-to-end test of the reload flow.

### Next Steps
1. Review `git diff` and commit the fix together with its tests.
2. Add a release note that users will be asked to sign in once.
```

## Expected Outcome

- **Changed:** `api/src/app.ts` and `api/src/auth/cookies.ts`; **added:** `api/src/auth/paths.ts`. No frontend changes.
- **Tests:** `api/tests/auth.refresh.test.ts` added, `api/tests/auth.test.ts` updated; the API suite grows from 47 to 52 tests.
- **Behavior:** after logging in, a hard reload keeps you signed in; leaving the tab open past 15 minutes no longer logs you out; logging out revokes the refresh token on the server.

Verify it yourself:

```bash
npm test --workspace api
npm run dev --workspace api
npm run dev --workspace web
```

Run the two `dev` commands in separate terminals, sign in as `demo`, and reload the page: you stay signed in. In the browser's developer tools, the `refresh_token` cookie now shows the path `/api/auth`.

## Variations and Tips

- **Give the debugger evidence.** A stack trace, a failing test id, or exact reproduction steps shorten the reproduce and isolate phases: `/agex Fix the failing test "refresh rotates the token" in api/tests/auth.test.ts`.
- **Diagnose without changing anything.** `/agex-research Why are users logged out after a page reload?` sends the read-only researcher instead, and you get a ResearchBrief with `path:line` evidence to decide on yourself.
- **When the bug cannot be reproduced,** the debugger returns NOT_REPRODUCED with every attempt it made instead of guessing at a fix, and the orchestrator brings that to you. Add what you know (browser, environment, logs) and run again.
- **Add the end-to-end test later.** `/agex-test the sign-in, reload, still-signed-in flow with Playwright` writes it if Playwright is already installed. The tester never installs dependencies itself; if Playwright is missing, it returns ERROR with the install command for you to run.
- **Audit the neighborhood.** Authentication bugs travel in groups. `/agex-secure api/src/auth` runs a focused security audit of the auth module.

For the artifact formats used above, see the [Handoff Protocol](../../docs/HANDOFF-PROTOCOL.md); for the other walkthroughs, see the [Examples index](../../docs/EXAMPLES.md).
