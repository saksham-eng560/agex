# Example: Build a REST API with JWT Authentication

This walkthrough follows a COMPLEX `/agex` run from start to finish: planning, research, design, two coders working in parallel, a coder-tester feedback loop, a coder-reviewer feedback loop, and documentation. It shows how the orchestrator keeps parallel work safe, how failure traces flow back to the coder, and why the final report can be trusted.

## Scenario

You maintain `todo-api`, a small Node.js service that so far only answers a health check. The repository contains:

| Path | Contents |
|---|---|
| `package.json` | `"type": "module"`; Express 5, TypeScript 5, Vitest, supertest, ESLint; scripts `dev` (`tsx watch src/server.ts`), `typecheck` (`tsc --noEmit`), `lint` (`eslint .`), `test` (`vitest run`) |
| `tsconfig.json` | `strict: true`, with `module` and `moduleResolution` set to `NodeNext` |
| `src/app.ts` | Creates the Express app, registers `express.json()` and `GET /health` |
| `src/server.ts` | Reads `PORT` and calls `app.listen` |
| `tests/health.test.ts` | One supertest test for `GET /health` |
| `CLAUDE.md` | Conventions: validate request input with zod at the HTTP boundary; keep route handlers thin and put logic in services; throw `HttpError` and let a single error middleware format responses; put tests in `tests/` |

There is no database yet. You want a real API: users register and log in with a username and password, receive a JWT, and manage only their own todos, with every request validated and every behavior covered by tests.

## The Command

```text
/agex Build a REST API for a todo app with JWT authentication, input validation, and tests
```

With a plugin install the same command is `/agex:agex` (typing `/agex` autocompletes it).

## What AGEX Does

`/agex` turns your main conversation into the orchestrator, so you watch every dispatch and any escalation comes straight to you. Before the model reads the prompt, the command injects your task, the first lines of `CLAUDE.md`, `git status`, and the list of project files.

1. **Complexity classification: COMPLEX.** The task introduces a new data model (users and todos), a new API surface, authentication (a cross-cutting security concern), and clearly more than five files. The orchestrator announces the chain planner → researcher → architect → parallel coders → tester ⇄ coder → reviewer ⇄ coder → documenter. Because `.agex/` exists in the project, it also appends `DISPATCH`, `ARTIFACT`, and `CYCLE` events to `.agex/session.log`.
2. **planner → TaskPlan, READY.** Nine steps in eight waves. Storage is not specified in the request, so instead of blocking on NEEDS_INPUT the planner records an assumption: SQLite through `better-sqlite3`, hidden behind repository modules so it can be swapped later. It puts the registration/login step and the todo CRUD step in the same parallel wave and notes that a user-facing API needs a documentation step.
3. **researcher → ResearchBrief, COMPLETE.** Evidence the coders will need, each with `path:line` or a documentation link:
   - `tsconfig.json` uses `NodeNext`, so relative imports in TypeScript source must end in `.js`.
   - Express 5 forwards rejected promises from async handlers to the error middleware, so no `asyncHandler` wrapper is needed.
   - `jsonwebtoken`'s `verify` accepts an `algorithms` option; pinning `['HS256']` rules out algorithm confusion.
   - bcrypt only uses the first 72 bytes of a password, so the password schema should cap length at 72.
4. **architect → TechnicalRFC, PROPOSED.** Four work units. WU-1 builds the shared foundations, including the token helpers and the `requireAuth` middleware, and installs every new dependency, so `package.json` and the lockfile are touched by one unit only. That leaves WU-2 (registration and login) and WU-3 (todo CRUD scoped to the owner) with disjoint files, both marked `Parallel-safe: yes`. WU-4 is the only unit that edits `src/app.ts` after them, so no two coders ever touch the same file.
5. **coder (WU-1) → CodeDiff, IMPLEMENTED.** `npm run typecheck` and `npm run lint` exit 0, and `npm test` still passes the single health test.
6. **coder (WU-2) and coder (WU-3) in parallel → two CodeDiffs, both IMPLEMENTED.** The orchestrator sends both Agent calls in one message. Each packet carries only its own work unit, the RFC's interface definitions, and the list of files that coder may touch.
7. **coder (WU-4) → CodeDiff, IMPLEMENTED.** Mounts `/auth`, mounts `/todos` behind `requireAuth`, and registers the error middleware last.
8. **tester → TestReport, FAIL (first test run; the coder-tester loop begins).** The tester writes integration tests for auth, todos, and validation: 42 tests, 40 passing. Both failures share one cause: `PATCH` and `DELETE` on another user's todo return 200 and 204 instead of 404, because the update and delete statements in `src/todos/todo.repository.ts` filter on `id` but not on `user_id`. That is a real authorization hole (any logged-in user could edit or delete anyone's todos), caught before review.
9. **coder (WU-3) → CodeDiff, IMPLEMENTED (coder-tester cycle 1 of 3).** The orchestrator logs `CYCLE loop=coder-tester n=1/3` and hands the coder the Failure Traces verbatim. The coder scopes both statements by `user_id` and returns 404 when no row changed. Only WU-3's counter moves; WU-2 has no failures and keeps its full budget.
10. **tester → TestReport, PASS (closes coder-tester cycle 1).** 42 of 42 pass. The loop closes after one cycle, with two to spare.
11. **reviewer → ReviewVerdict, CHANGES_REQUESTED (first review; the coder-reviewer loop begins).** Two MEDIUM issues in WU-2 and one LOW: a duplicate username surfaces as a 500 instead of a 409, and login reveals which usernames exist through different error codes and response timing. The LOW item (a missing index) is non-blocking.
12. **coder (WU-2) → CodeDiff, IMPLEMENTED (coder-reviewer cycle 1 of 3).** Maps the unique-constraint error to `409 USERNAME_TAKEN`, and makes login return one `401 INVALID_CREDENTIALS` body for both cases while comparing against a dummy hash when the user does not exist.
13. **tester → TestReport, PASS.** A review-driven fix must be re-tested before the quality gate can pass. The tester adds regression tests for both review issues: 44 of 44 pass.
14. **reviewer and documenter in parallel.** They share no files and neither changes code, so they run in the same turn. The reviewer returns APPROVED, closing coder-reviewer cycle 1, with the LOW item listed as non-blocking. The documenter returns a DocUpdate, COMPLETE: it creates `docs/API.md` and adds Configuration and Running Locally sections to `README.md` without rewriting what was there.
15. **Quality gate and AgexReport, DONE.** The latest TestReport is PASS, the latest ReviewVerdict is APPROVED, no security findings are open, and every acceptance criterion in the RFC is checked. The run used 15 dispatches, exactly the soft budget; a 16th would have required asking you first.

## Illustrative Artifact Excerpts

The excerpts below are illustrative. They show the envelope, section order, and level of detail you should expect, abridged for length. They are not captured output from a recorded run.

### TechnicalRFC (abridged)

```markdown
<!-- agex:artifact type=TechnicalRFC version=1 -->
## TechnicalRFC: Todo REST API with JWT auth on SQLite
**Producer:** architect · **Status:** PROPOSED · **Confidence:** HIGH

### Context & Goals
Add username/password auth issuing HS256 JWTs (15 minute expiry) and owner-scoped todo CRUD
to the Express 5 app in src/app.ts:4. All input is validated with zod (CLAUDE.md:6).

### Non-Goals
- Refresh tokens, password reset, and roles.
- A migration framework; the schema is created idempotently at startup.

### Component Architecture
- config (src/config.ts, new) — parses env with zod; JWT_SECRET must be at least 32 characters
- db (src/db.ts, new) — opens better-sqlite3 and creates users and todos tables
- auth (src/auth/*, new) — tokens, register/login service, routes
- todos (src/todos/*, new) — repository scoped by user_id, service, routes

### Data Flow
~~~mermaid
flowchart LR
    Client --> Router --> Validate[validate zod] --> RequireAuth[requireAuth] --> Service --> Repository --> SQLite
~~~

### Interface & Type Definitions
- createApp(deps: { db: Database; config: AppConfig }): Express
- signAccessToken(userId: number, config: AppConfig): string
- verifyAccessToken(token: string, config: AppConfig): { userId: number }  (algorithms: ['HS256'])
- Error body: { "error": { "code": string, "message": string, "details"?: unknown[] } }
- POST /auth/register → 201 | 400 | 409; POST /auth/login → 200 | 400 | 401
- GET/POST /todos, GET/PATCH/DELETE /todos/:id → 401 without a valid token; 404 for other users' todos

### Implementation Sequence
- **WU-1: Shared foundations**
  - Files: src/config.ts, src/db.ts, src/errors.ts, src/middleware/validate.ts, src/auth/tokens.ts, src/middleware/requireAuth.ts, src/app.ts, src/server.ts, package.json
  - Change: config, schema, HttpError + error middleware, validation middleware, token helpers, requireAuth; install all new dependencies
  - Depends On: none
  - Acceptance Criteria: typecheck and lint pass; GET /health still returns 200; the server refuses to start without JWT_SECRET
  - Parallel-safe: no
- **WU-2: Registration and login**
  - Files: src/auth/auth.schemas.ts, src/auth/user.repository.ts, src/auth/auth.service.ts, src/auth/auth.routes.ts
  - Change: bcrypt hashing (cost from config: 12 in production, 4 in tests), register and login, exported authRouter
  - Depends On: WU-1
  - Acceptance Criteria: register returns 201 without the hash; login returns { accessToken, tokenType, expiresIn }
  - Parallel-safe: yes
- **WU-3: Todo CRUD scoped to the owner**
  - Files: src/todos/todo.schemas.ts, src/todos/todo.repository.ts, src/todos/todo.service.ts, src/todos/todo.routes.ts
  - Change: every query filters by user_id; list supports completed, limit (max 100), offset
  - Depends On: WU-1
  - Acceptance Criteria: another user's todo returns 404 for GET, PATCH, and DELETE
  - Parallel-safe: yes
- **WU-4: Router wiring**
  - Files: src/app.ts
  - Change: mount /auth and /todos (behind requireAuth); register the error middleware last
  - Depends On: WU-2, WU-3
  - Acceptance Criteria: all routes reachable; unknown routes return 404 in the error body format
  - Parallel-safe: no

### Test Requirements
- Integration tests with supertest against createApp on an in-memory database (":memory:").
- Cross-user isolation, expired and foreign-signed tokens, and title lengths 0, 1, 200, 201.

### Alternatives Considered & Risks
- Alternative: PostgreSQL — rejected for now; no database is provisioned and the repository layer keeps it swappable.
- Risk: parallel coders both editing package.json — mitigation: WU-1 installs every dependency.
```

### TestReport, first test run

```markdown
<!-- agex:artifact type=TestReport version=1 -->
## TestReport: Integration tests for auth, todos, and validation
**Producer:** tester · **Status:** FAIL · **Confidence:** HIGH

### Test Suites Executed
- `npm run typecheck` (exit code 0)
- `npm test` (exit code 1)

### Pass/Fail Summary
| Suite | Passed | Failed | Skipped |
|---|---|---|---|
| tests/health.test.ts | 1 | 0 | 0 |
| tests/auth.test.ts | 12 | 0 | 0 |
| tests/todos.test.ts | 19 | 2 | 0 |
| tests/validation.test.ts | 8 | 0 | 0 |

### Tests Added or Updated
- `tests/helpers.ts` — builds the app on an in-memory database; registers and logs in a user
- `tests/auth.test.ts` — register, login, expired token, missing and malformed Authorization header
- `tests/todos.test.ts` — CRUD, pagination, completed filter, cross-user isolation
- `tests/validation.test.ts` — schema violations return 400 with field details

### Edge Cases Covered
- Titles of 0, 1, 200, and 201 characters
- Expired token and a token signed with a different secret
- Reading, editing, and deleting a todo owned by another user
- Non-numeric and non-existent todo ids

### Failure Traces
1. `tests/todos.test.ts > PATCH /todos/:id > returns 404 for a todo owned by another user`
   - Expected: 404, the other user's todo unchanged
   - Actual: 200, the other user's title overwritten
   - Trace excerpt: AssertionError: expected 200 to be 404 // Object.is equality (tests/todos.test.ts:148:30)
   - Suspected location: `src/todos/todo.repository.ts:47` (the UPDATE filters on `id = ?` only, with no user_id condition)
2. `tests/todos.test.ts > DELETE /todos/:id > returns 404 for a todo owned by another user`
   - Expected: 404, the row still present
   - Actual: 204, the row deleted
   - Trace excerpt: AssertionError: expected 204 to be 404 // Object.is equality (tests/todos.test.ts:171:30)
   - Suspected location: `src/todos/todo.repository.ts:58` (DELETE FROM todos WHERE id = ?)

### Coverage
not measured (no coverage provider such as @vitest/coverage-v8 is installed; the tester does not add dependencies)

### Recommendation for Coder
- Add `AND user_id = ?` to update and delete in src/todos/todo.repository.ts, as findById already does at line 31, and return 404 when `changes === 0`.
```

### ReviewVerdict, first review

```markdown
<!-- agex:artifact type=ReviewVerdict version=1 -->
## ReviewVerdict: Todo API with JWT auth, full diff
**Producer:** reviewer · **Status:** CHANGES_REQUESTED · **Confidence:** HIGH

### Summary
Reviewed WU-1 through WU-4 and the new tests. Structure follows the RFC and CLAUDE.md, ownership
checks are consistent after the coder-tester fix, and token verification pins HS256. Two MEDIUM issues
in the auth service must be fixed before approval.

### Issues
| ID | Severity | Category | Location | Problem | Remediation |
|---|---|---|---|---|---|
| R-1 | MEDIUM | error-handling | `src/auth/auth.service.ts:21` | Registering an existing username throws SqliteError SQLITE_CONSTRAINT_UNIQUE, which the error middleware returns as 500 | Catch that code and throw `new HttpError(409, 'USERNAME_TAKEN', 'Username is already taken')`; add a 409 test |
| R-2 | MEDIUM | security | `src/auth/auth.service.ts:34` | Unknown usernames return code USER_NOT_FOUND without running bcrypt; wrong passwords return INVALID_PASSWORD after a compare. Error code and timing both reveal which usernames exist | Return one 401 INVALID_CREDENTIALS body for both, and compare against a dummy hash precomputed at the configured cost when the user is missing |
| R-3 | LOW | performance | `src/db.ts:24` | todos has no index on user_id, so every list query scans the table | Non-blocking: `CREATE INDEX IF NOT EXISTS idx_todos_user_id ON todos(user_id)` |

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
- JWT_SECRET is validated at startup; there is no fallback secret.
- Every todo query is now scoped by user_id, and cross-user tests prove it.
- Validation errors return field-level details in one consistent error body.
```

### AgexReport (final)

```markdown
<!-- agex:artifact type=AgexReport version=1 -->
## AgexReport: Todo REST API with JWT auth, validation, and tests
**Producer:** orchestrator · **Status:** DONE · **Confidence:** HIGH

### Task
Build a REST API for a todo app with JWT authentication, input validation, and tests. COMPLEX:
new data model and API, authentication, more than five files.

### Outcome
POST /auth/register, POST /auth/login, and owner-scoped GET/POST /todos and GET/PATCH/DELETE
/todos/:id run on SQLite with zod validation, covered by 44 passing integration tests.

### Agents Deployed
| # | Agent | Artifact | Status | Cycle |
|---|---|---|---|---|
| 1 | planner | TaskPlan | READY | n/a |
| 2 | researcher | ResearchBrief | COMPLETE | n/a |
| 3 | architect | TechnicalRFC | PROPOSED | n/a |
| 4 | coder (WU-1) | CodeDiff | IMPLEMENTED | n/a |
| 5 | coder (WU-2) | CodeDiff | IMPLEMENTED | n/a |
| 6 | coder (WU-3) | CodeDiff | IMPLEMENTED | n/a |
| 7 | coder (WU-4) | CodeDiff | IMPLEMENTED | n/a |
| 8 | tester | TestReport | FAIL | n/a |
| 9 | coder (WU-3) | CodeDiff | IMPLEMENTED | coder-tester 1/3 for WU-3 |
| 10 | tester | TestReport | PASS | coder-tester 1/3 for WU-3 |
| 11 | reviewer | ReviewVerdict | CHANGES_REQUESTED | n/a |
| 12 | coder (WU-2) | CodeDiff | IMPLEMENTED | coder-reviewer 1/3 for WU-2 |
| 13 | tester | TestReport | PASS | coder-reviewer 1/3 for WU-2 |
| 14 | reviewer | ReviewVerdict | APPROVED | coder-reviewer 1/3 for WU-2 |
| 15 | documenter | DocUpdate | COMPLETE | n/a |

### Changes
- Added: src/config.ts, src/db.ts, src/errors.ts, src/middleware/validate.ts, src/middleware/requireAuth.ts,
  src/auth/{tokens,auth.schemas,user.repository,auth.service,auth.routes}.ts,
  src/todos/{todo.schemas,todo.repository,todo.service,todo.routes}.ts, tests/{helpers,auth.test,todos.test,validation.test}.ts, docs/API.md
- Modified: src/app.ts, src/server.ts, package.json, package-lock.json, README.md

### Verification Evidence
- `npm run typecheck` → exit 0
- `npm run lint` → exit 0, no problems
- `npm test` → Test Files 4 passed (4); Tests 44 passed (44)
- ReviewVerdict (coder-reviewer cycle 1): APPROVED

### Open Issues & Escalations
- R-3 (LOW, non-blocking): add an index on todos.user_id.
- No escalations.

### Next Steps
1. Set JWT_SECRET (at least 32 characters) in every environment; the server refuses to start without it.
2. Review the diff with `git diff` and commit; AGEX never commits.
3. Before exposing the API publicly, run `/agex-secure` for a dedicated security audit.
```

### Session log (excerpt)

```text
[2026-09-27T09:14:02Z] SESSION_START source=startup
[2026-09-27T09:15:40Z] DISPATCH agent=planner
[2026-09-27T09:16:31Z] ARTIFACT type=TaskPlan status=READY
[2026-09-27T09:24:05Z] DISPATCH agent=coder unit=WU-2
[2026-09-27T09:24:05Z] DISPATCH agent=coder unit=WU-3
[2026-09-27T09:25:47Z] FILE_MODIFIED tool=Write path=src/auth/auth.service.ts
[2026-09-27T09:25:52Z] FILE_MODIFIED tool=Write path=src/todos/todo.repository.ts
[2026-09-27T09:36:18Z] ARTIFACT type=TestReport status=FAIL
[2026-09-27T09:36:20Z] CYCLE loop=coder-tester n=1/3
[2026-09-27T09:36:20Z] DISPATCH agent=coder unit=WU-3
[2026-09-27T10:01:12Z] RUN_COMPLETE status=DONE
```

## Expected Outcome

When the run finishes, your working tree contains uncommitted changes and nothing has been pushed:

- **New source:** configuration, database setup, error handling, validation middleware, token helpers, `requireAuth`, and the `auth` and `todos` modules under `src/`.
- **Modified:** `src/app.ts` (routers and error middleware), `src/server.ts` (loads the validated config), `package.json` and the lockfile (`better-sqlite3`, `bcryptjs`, `jsonwebtoken`, `zod`, and their type packages).
- **Tests:** four new files under `tests/`, 44 tests in total including the cross-user isolation and regression tests.
- **Docs:** `docs/API.md` with every endpoint, request and response shape, and error code; new Configuration and Running Locally sections in `README.md`.

Verify it yourself:

```bash
npm run typecheck && npm run lint && npm test
JWT_SECRET="$(openssl rand -hex 32)" npm run dev
```

Then, in a second terminal, exercise the API:

```bash
curl -s -X POST http://localhost:3000/auth/register -H 'Content-Type: application/json' -d '{"username":"ada","password":"correct-horse-battery"}'
TOKEN=$(curl -s -X POST http://localhost:3000/auth/login -H 'Content-Type: application/json' -d '{"username":"ada","password":"correct-horse-battery"}' | jq -r .accessToken)
curl -s -X POST http://localhost:3000/todos -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"title":"Write the release notes"}'
curl -s http://localhost:3000/todos -H "Authorization: Bearer $TOKEN"
```

A request without the `Authorization` header should return 401, and a todo title longer than 200 characters should return 400 with a `details` array naming the `title` field.

## Variations and Tips

- **Preview first.** Run `/agex-plan Build a REST API for a todo app with JWT authentication, input validation, and tests` to see the TaskPlan and the expected number of dispatches before anything runs. The plan stays in the conversation, and a following `/agex` with the same task uses it as input.
- **State your decisions up front.** If you already know the stack, say so: `/agex Build a REST API for a todo app with JWT authentication, input validation, and tests, using PostgreSQL via pg and argon2 for password hashing`. The planner then records these as constraints instead of assumptions, and the researcher checks the versions your manifests pin.
- **Narrow the scope to stay MEDIUM.** A smaller request such as `/agex Add owner-scoped PATCH /todos/:id with zod validation and tests` touches a handful of files in one component, skips the planner, researcher, and architect, and costs far fewer dispatches.
- **Split very large features.** If the plan would exceed the 15-dispatch soft budget, run it in slices (auth first, then todos). Each run ends with its own quality gate, so every slice is verified before the next one starts.
- **Add a security pass for anything internet-facing.** The reviewer checks OWASP Top 10 issues in the diff, but `/agex-secure` audits the whole project, including dependencies and configuration. See the [security audit example](../security-audit/task.md).
- **Keep your working tree clean before starting.** Then `git diff` afterwards shows exactly what AGEX changed.

For the artifact formats used above, see the [Handoff Protocol](../../docs/HANDOFF-PROTOCOL.md); for the other walkthroughs, see the [Examples index](../../docs/EXAMPLES.md).
