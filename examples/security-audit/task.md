# Example: Audit a Flask Shop and Fix Its Critical Findings

This walkthrough has two parts. First, `/agex-secure` runs the read-only security agent over a whole Flask application and returns a SecurityAuditReport with CRITICAL findings, including a live payment key in a tracked `.env` file that is never shown beyond its first four characters. Second, after you rotate the leaked credentials, `/agex` fixes the CRITICAL and HIGH findings along AGEX's security route: coders fix, the tester proves the fixes, and the reviewer and a security re-check confirm that nothing CRITICAL or HIGH remains. It also shows what no tool can fix for you: a secret that was ever committed stays in git history.

## Scenario

`storefront` is a small online shop: Python 3.11, Flask 2.2, SQLite through the standard `sqlite3` module, server-rendered Jinja2 templates, gunicorn in a Docker image, and pytest with Flask's test client.

| Path | Contents |
|---|---|
| `app/__init__.py` | `create_app()`: reads settings from the environment (python-dotenv loads `.env` in development) and registers the blueprints |
| `app/db.py` | `get_db()` opens the SQLite database per request, following the Flask tutorial pattern |
| `app/products.py` | Public pages: product list, product detail, and `GET /products/search?q=` |
| `app/auth.py` | Session-cookie login and logout, plus a password-reset flow that emails a link to the account's address |
| `app/account.py` | Signed-in routes: `POST /account/email` and `POST /account/password` |
| `app/cart.py` | `POST /cart/checkout`, which charges the customer through Stripe |
| `app/templates/_macros.html` | `form_start()`, the macro that renders the opening `<form method="post">` tag of every form in the app |
| `requirements.txt` | `Flask==2.2.2` and `Werkzeug==2.2.2`, plus pinned python-dotenv, stripe, and gunicorn |
| `requirements-dev.txt` | pytest and pip-audit, installed in the project's virtual environment |
| `tests/` | 18 tests: `test_products.py` (8), `test_auth.py` (4), `test_account.py` (4), `test_cart.py` (2); the `logged_in_client` fixture in `conftest.py` signs in through `POST /login` |
| `Dockerfile` | `FROM python:3.11-slim`, installs the requirements, and starts `gunicorn -b 0.0.0.0:8000 "app:create_app()"`; there is no `USER` instruction |
| `.env` | `SECRET_KEY`, `STRIPE_SECRET_KEY`, and `DATABASE_PATH`. It was committed in the very first commit; a `.env` line was added to `.gitignore` a week later |
| `.env.example` | The same keys with empty values |

The shop has never had a security review, and the public launch is next week.

## The Command

```text
/agex-secure
```

No argument is needed: without a scope, the whole project is audited. After you have rotated the leaked credentials (see below), fix the worst findings in the same conversation:

```text
/agex Fix the CRITICAL and HIGH findings from the security audit
```

With a plugin install the same commands are `/agex:agex-secure` and `/agex:agex`.

## What AGEX Does

### Part 1: The audit

`/agex-secure` is a focused specialist command, not an orchestration run: there is no complexity classification, and the whole command is read-only.

1. **Context injection and dispatch.** Before the model reads the prompt, the command injects the list of source files, the dependency manifests that exist (`requirements.txt`; every other manifest it checks for is absent), and the names of environment files: `.env` and `.env.example` in the project root, and the same two tracked by git. It prints file names only, never the contents of an environment file. With no scope given, the main conversation states "whole project" and dispatches `security` (`agex:security` in a plugin install) with a self-contained packet.
2. **security → SecurityAuditReport, CRITICAL_FINDINGS.** The security agent works strictly read-only:
   - **Secrets.** It greps for known credential formats in files-with-matches mode, so matching values never enter its context. `.env` matches the pattern for live Stripe secret keys, which is all the evidence needs: `sk_l****`. It lists the file's keys by name only. `git log` shows that `.env` was added in the first commit; `.gitignore` lists it, but ignore rules do not apply to files git already tracks, so the file is in every commit since. **SEC-1, CRITICAL.**
   - **Injection.** `app/products.py:41` builds the search query by concatenating the `q` parameter into the SQL string. The route is public, so anyone can read any table, including customer emails and password hashes, with a `UNION` payload. **SEC-2, CRITICAL.**
   - **CSRF.** No CSRF protection exists anywhere (`grep -rniE 'csrf' app requirements.txt` finds nothing), state-changing POST routes rely only on the session cookie, and `SESSION_COOKIE_SAMESITE` is not set. A page on another site can change a signed-in customer's email address, and the password-reset flow then hands the account to the attacker. **SEC-3, HIGH.**
   - **Dependencies.** `command -v pip-audit` finds pip-audit in the virtual environment, so the agent runs `pip-audit -r requirements.txt`: Flask 2.2.2 and Werkzeug 2.2.2 have published advisories. The agent never installs a scanner; had pip-audit been missing, the report would say the audit was not run. **SEC-4, HIGH.**
   - **Configuration.** Without a `USER` instruction, gunicorn runs as root inside the container (**SEC-5, MEDIUM**), and the session cookie lacks the `Secure` attribute (**SEC-6, LOW**).
3. **Validation and bottom line.** The main conversation checks the envelope and section order, confirms that CRITICAL_FINDINGS matches a matrix with CRITICAL rows, confirms that the tracked `.env` is rated at least HIGH, and scans every Evidence cell for anything that looks like an unredacted secret before presenting the report in full. The bottom line: overall risk CRITICAL, with 2 CRITICAL, 2 HIGH, 1 MEDIUM, and 1 LOW findings. Top priorities: rotate both credentials and stop tracking `.env`; parameterize the search query; add CSRF protection.
4. **Next steps suggested, not taken.** `/agex-secure` never fixes anything and never touches files. It suggests `/agex` for the fixes and tells you to rotate every leaked credential first, because deleting `.env` from the latest commit does not remove it from git history.

### Between the runs: rotate the leaked credentials

Only you can do this, and it comes first. Once a secret has been committed, treat it as compromised, whether or not the repository was ever pushed:

- Roll the Stripe secret key in the Stripe Dashboard and let the old key expire immediately.
- Generate a new `SECRET_KEY`, for example with `python -c "import secrets; print(secrets.token_hex(32))"`. Flask signs session cookies with this key, so anyone holding the old one could forge a session for any customer. Changing it signs everyone out once.
- Put both new values in your local `.env` only. The fix run stops git from tracking the file.

### Part 2: The fix run

Run `/agex` in the same conversation, so the SecurityAuditReport is already available as input.

1. **Complexity classification: MEDIUM, task type security fixes.** Five files in one application, and every remediation is already specified in the SecurityAuditReport, so no design decision is left: no planner, researcher, or architect. The security route applies: coder → tester → reviewer → security re-check. The orchestrator scopes the run to SEC-1 through SEC-4, as you asked. Before dispatching anything, it asks you one question, because part of SEC-1 is something no agent can do: have both credentials been rotated? You confirm.
2. **Work units with disjoint files.** A MEDIUM task needs no RFC, so the orchestrator defines the units itself:
   - **WU-1 (SEC-2):** `app/products.py`.
   - **WU-2 (SEC-1, SEC-3, SEC-4):** `requirements.txt`, `app/__init__.py`, `app/templates/_macros.html`, and removing `.env` from the git index with `git rm --cached .env`, which keeps your local file. The packet permits exactly that one git command; committing stays with you. The dependency upgrade and the new CSRF library both change `requirements.txt`, so they belong to one unit.

   WU-2's acceptance criteria anticipate a side effect: once CSRF protection is on, existing tests that post forms without a token receive 400 until the test configuration is updated. Test files belong to the tester, so the coder is told to report those failures rather than edit tests.
3. **coder (WU-1) and coder (WU-2) in parallel → two CodeDiffs, both IMPLEMENTED.** The orchestrator sends both Agent calls in one message.
   - WU-1 replaces the concatenated SQL with a parameterized query: `db.execute("SELECT id, name, price FROM products WHERE name LIKE ?", (f"%{q}%",))`.
   - WU-2 upgrades Flask and Werkzeug together to current 3.x releases (Flask 2.2 cannot import Werkzeug 3, so the two cannot be upgraded separately), adds Flask-WTF, registers `CSRFProtect(app)`, sets `SESSION_COOKIE_SAMESITE="Lax"`, adds the hidden `csrf_token` field to `form_start()`, and untracks `.env`. `pip-audit -r requirements.txt` now finds no known vulnerabilities. As anticipated, 9 of the 18 existing tests fail with 400: every test that posts a form, including all tests that sign in through `logged_in_client`.
4. **tester → TestReport, PASS.** The tester sets `WTF_CSRF_ENABLED=False` in the default test configuration in `tests/conftest.py`, the setup Flask-WTF documents for testing, and adds a `csrf_client` fixture that keeps protection on. That does not weaken the suite: every existing test passes unchanged, and nine new tests prove the fixes. Three search tests: a product name containing an apostrophe is found instead of causing a 500, `' OR '1'='1` matches nothing, and a `UNION` payload returns no user data. Six CSRF and cookie tests: posts without a token return 400 for login, email change, and checkout; a token taken from the rendered form is accepted; a token from another session is rejected; and the session cookie carries `SameSite=Lax`. 27 of 27 pass.
5. **reviewer and security in parallel → ReviewVerdict APPROVED and SecurityAuditReport FINDINGS.** Both are read-only and depend only on the fixed code, so they run in the same turn.
   - The reviewer finds two LOW items, both non-blocking: `%` and `_` in a search term still act as `LIKE` wildcards (harmless, but a search for `%` lists every product), and no CSRF test covers `POST /account/password`.
   - The security re-check confirms that SEC-1 to SEC-4 are resolved and reports SEC-5 (MEDIUM) and SEC-6 (LOW) as still open, because you asked for CRITICAL and HIGH only. Its status is FINDINGS rather than PASS, and that is expected: the quality gate blocks only on open CRITICAL or HIGH findings.
6. **Quality gate and AgexReport, DONE.** TestReport PASS, ReviewVerdict APPROVED, no open CRITICAL or HIGH findings, and every acceptance criterion checked, after five dispatches. The report lists SEC-5, SEC-6, and the two LOW review items under Open Issues, and repeats the warning about git history under Next Steps.

## Illustrative Artifact Excerpts

The excerpts below are illustrative. They show the envelope, section order, and level of detail you should expect, abridged for length. They are not captured output from a recorded run. Secret values appear only as their first four characters followed by `****`, or as `****` alone.

### SecurityAuditReport (the audit)

```markdown
<!-- agex:artifact type=SecurityAuditReport version=1 -->
## SecurityAuditReport: storefront, full project
**Producer:** security · **Status:** CRITICAL_FINDINGS · **Confidence:** HIGH

### Scope
- Whole repository and working tree: app/ (6 modules, 11 templates), requirements.txt, requirements-dev.txt,
  Dockerfile, .gitignore, and .env and .env.example (key names only)
- Stack: Python 3.11, Flask 2.2.2, sqlite3, Jinja2, gunicorn in Docker
- Out of scope: deployed infrastructure and the Stripe account configuration

### Risk Matrix
| ID | Severity | Category | Location | Finding | Evidence (redacted) | Remediation |
|---|---|---|---|---|---|---|
| SEC-1 | CRITICAL | CWE-798 | `.env:2` | A live Stripe secret key and the Flask SECRET_KEY are committed. .gitignore:3 lists .env, but the file was tracked before that rule existed and ignore rules do not apply to tracked files, so it is in every commit since the first | `STRIPE_SECRET_KEY=sk_l****`, `SECRET_KEY=****` | Rotate both credentials first; then `git rm --cached .env` and commit. The old values stay in git history, so rotation is what makes them harmless |
| SEC-2 | CRITICAL | A03:2021-Injection | `app/products.py:41` | The public search concatenates q into SQL; a UNION payload reads any table, including users.email and users.password_hash | `sql = "SELECT id, name, price FROM products WHERE name LIKE '%" + q + "%'"` | `db.execute("SELECT id, name, price FROM products WHERE name LIKE ?", (f"%{q}%",))` |
| SEC-3 | HIGH | CWE-352 | `app/account.py:28` | No CSRF protection on any POST route and SESSION_COOKIE_SAMESITE unset: another site can change a signed-in customer's email, then take the account over through password reset (app/auth.py:61) | `@bp.post("/email")` authenticated by the session cookie alone; `grep -rniE 'csrf' app requirements.txt` finds nothing | Add Flask-WTF, call `CSRFProtect(app)` in create_app, emit `{{ csrf_token() }}` in form_start() (app/templates/_macros.html:3), set SESSION_COOKIE_SAMESITE="Lax" |
| SEC-4 | HIGH | A06:2021-Vulnerable and Outdated Components | `requirements.txt:1` | Flask 2.2.2 and Werkzeug 2.2.2 (line 2) have published advisories, among them CVE-2023-25577 (Werkzeug: denial of service through multipart form parsing, fixed in 2.2.3) and CVE-2023-30861 (Flask: a caching proxy can serve one user's session cookie to others, fixed in 2.2.5) | `Flask==2.2.2`, `Werkzeug==2.2.2` | Upgrade Flask and Werkzeug together to current 3.x releases (Flask 2.2 cannot import Werkzeug 3); re-run pip-audit |
| SEC-5 | MEDIUM | A05:2021-Security Misconfiguration | `Dockerfile:9` | No USER instruction: gunicorn runs as root in the container, so any code-execution bug yields root inside it | `CMD ["gunicorn", "-b", "0.0.0.0:8000", "app:create_app()"]` with no USER before it | Add `RUN useradd --create-home --uid 10001 app` and `USER app` before CMD |
| SEC-6 | LOW | CWE-614 | `app/__init__.py:18` | SESSION_COOKIE_SECURE is not set, so the session cookie would also be sent over plain HTTP | No SESSION_COOKIE_SECURE in the config mapping | Set SESSION_COOKIE_SECURE=True outside development |

### Secrets Scan
- Patterns searched (files-with-matches mode, so no value entered the agent's context): AWS access keys,
  GitHub and Slack tokens, Stripe live keys, Google API keys, private key blocks, credentialed connection
  strings, generic secret, token, and password assignments
- Tracked env files: .env (SEC-1); .env.example (template, all values empty)
- .env keys, by name only: SECRET_KEY, STRIPE_SECRET_KEY, DATABASE_PATH
- History: `git log --diff-filter=A --format='%h %ad' --date=short -- .env` → added in the first commit
- Result: SEC-1; no secrets in source files or templates

### Dependency Audit
- `pip-audit -r requirements.txt` — known vulnerabilities in 2 packages, flask 2.2.2 and werkzeug 2.2.2
  (SEC-4); no other pinned package affected

### Configuration Review
- Dockerfile — no USER instruction, runs as root — SEC-5
- Session cookie — HttpOnly on (Flask default); Secure unset — SEC-6; SameSite unset — part of SEC-3
- Debug mode — FLASK_DEBUG not set in the Dockerfile; gunicorn serves production traffic — no issue
- .gitignore — lists .env at line 3, but the file is tracked — SEC-1

### Summary
- CRITICAL: 2 · HIGH: 2 · MEDIUM: 1 · LOW: 1
- Overall risk: CRITICAL
```

### CodeDiff for WU-2 (abridged)

```markdown
<!-- agex:artifact type=CodeDiff version=1 -->
## CodeDiff: CSRF protection, dependency upgrade, and untracked .env
**Producer:** coder · **Status:** IMPLEMENTED · **Confidence:** HIGH

### Summary
Registered Flask-WTF's CSRFProtect in create_app and added the token field to form_start(), so every POST
form carries it, and set SESSION_COOKIE_SAMESITE to Lax. Upgraded Flask and Werkzeug together from 2.2.2
to current 3.x releases, pinned exactly. Removed .env from the git index; the local file is untouched.

### Work Units Implemented
- WU-2: SEC-1 (tracking), SEC-3, SEC-4 — all acceptance criteria met, including the anticipated test failures

### Files Changed
| File | Change (added/modified/deleted) | Notes |
|---|---|---|
| `requirements.txt` | modified | Flask and Werkzeug upgraded together to current 3.x releases; Flask-WTF added; all pinned |
| `app/__init__.py` | modified | `CSRFProtect(app)` in create_app; `SESSION_COOKIE_SAMESITE="Lax"` |
| `app/templates/_macros.html` | modified | form_start() emits `<input type="hidden" name="csrf_token" value="{{ csrf_token() }}">` |
| `.env` | deleted | From the git index only, with `git rm --cached .env` (staged); the working-tree file is kept and ignored |

### Verification
- Typecheck: not available (no mypy or pyright configuration in the project)
- Lint: not available (no linter configured in the project)
- Tests: `python -m pytest -q` → 9 failed, 9 passed; every failure is 400 "The CSRF token is missing." from
  a test that posts a form, including all tests using the logged_in_client fixture, as the packet anticipated
- `pip-audit -r requirements.txt` → No known vulnerabilities found
- `git ls-files .env` → no output

### Deviations from RFC
None

### Notes for Tester & Reviewer
- tests/conftest.py needs WTF_CSRF_ENABLED=False for the existing functional tests, plus dedicated tests with
  protection on. I did not edit any test file.
- The user rotated SECRET_KEY before this run, which signs out every existing session once.
```

### SecurityAuditReport (re-check)

```markdown
<!-- agex:artifact type=SecurityAuditReport version=1 -->
## SecurityAuditReport: storefront re-check after fixes
**Producer:** security · **Status:** FINDINGS · **Confidence:** HIGH

### Scope
- Re-check of SEC-1 to SEC-6 against the working tree and index, with focus on the changed files:
  app/products.py, app/__init__.py, app/templates/_macros.html, requirements.txt, tests/
- Resolved: SEC-1 (tracking), SEC-2, SEC-3, SEC-4. Still open, excluded from this run by request: SEC-5, SEC-6

### Risk Matrix
| ID | Severity | Category | Location | Finding | Evidence (redacted) | Remediation |
|---|---|---|---|---|---|---|
| SEC-5 | MEDIUM | A05:2021-Security Misconfiguration | `Dockerfile:9` | Unchanged: gunicorn runs as root in the container | No USER instruction before CMD | Add `RUN useradd --create-home --uid 10001 app` and `USER app` before CMD |
| SEC-6 | LOW | CWE-614 | `app/__init__.py:19` | Unchanged: the session cookie lacks the Secure attribute | No SESSION_COOKIE_SECURE in the config mapping | Set SESSION_COOKIE_SECURE=True outside development |

### Secrets Scan
- Patterns searched: as in the previous audit, in files-with-matches mode
- Tracked env files: .env.example only; .env is staged for removal from the index (`git ls-files .env` prints
  nothing) and ignored by .gitignore:3
- History: .env was added in the first commit and never removed, so all 41 commits on this branch
  (`git rev-list --count HEAD`) still contain the old values. The user states both credentials were rotated
  before this run; that cannot be verified from the repository, and credentials are never tested
- Result: no secrets in tracked files

### Dependency Audit
- `pip-audit -r requirements.txt` — No known vulnerabilities found; SEC-4 resolved

### Configuration Review
- CSRF — CSRFProtect registered (app/__init__.py:24), token emitted by form_start()
  (app/templates/_macros.html:4), SameSite=Lax — SEC-3 resolved
- SQL — every execute call in app/ uses ? placeholders (`grep -rn 'execute(' app`) — SEC-2 resolved
- Dockerfile — SEC-5
- Session cookie Secure attribute — SEC-6

### Summary
- CRITICAL: 0 · HIGH: 0 · MEDIUM: 1 · LOW: 1
- Overall risk: MEDIUM
```

### AgexReport from the fix run (abridged)

```markdown
<!-- agex:artifact type=AgexReport version=1 -->
## AgexReport: Fix CRITICAL and HIGH audit findings in storefront
**Producer:** orchestrator · **Status:** DONE · **Confidence:** HIGH

### Task
Fix the CRITICAL and HIGH findings (SEC-1 to SEC-4) from the security audit. MEDIUM: five files in one
application, with every remediation specified by the SecurityAuditReport.

### Outcome
The product search is parameterized, every POST form is protected against CSRF, Flask and Werkzeug are on
releases with no known vulnerabilities, and .env is no longer tracked. The user rotated both leaked
credentials before the run.

### Agents Deployed
| # | Agent | Artifact | Status | Cycle |
|---|---|---|---|---|
| 1 | coder (WU-1) | CodeDiff | IMPLEMENTED | n/a |
| 2 | coder (WU-2) | CodeDiff | IMPLEMENTED | n/a |
| 3 | tester | TestReport | PASS | n/a |
| 4 | reviewer | ReviewVerdict | APPROVED | n/a |
| 5 | security | SecurityAuditReport | FINDINGS | n/a |

### Changes
- Modified: app/products.py, app/__init__.py, app/templates/_macros.html, requirements.txt,
  tests/conftest.py, tests/test_products.py
- Added: tests/test_csrf.py
- Removed from the git index (staged; the local file is kept): .env

### Verification Evidence
- `python -m pytest -q` → 27 passed
- `pip-audit -r requirements.txt` → No known vulnerabilities found
- ReviewVerdict: APPROVED (2 LOW, non-blocking)
- Security re-check: FINDINGS with CRITICAL 0, HIGH 0, MEDIUM 1, LOW 1; SEC-1 to SEC-4 resolved

### Open Issues & Escalations
- SEC-5 (MEDIUM): the container runs as root; excluded from this run by request.
- SEC-6 (LOW): the session cookie lacks the Secure attribute.
- R-1 (LOW): % and _ act as wildcards in search terms. R-2 (LOW): no CSRF test for POST /account/password.
- No escalations.

### Next Steps
1. Review the changes with `git diff` and `git status` (which shows .env as deleted in the index), then commit.
2. The old secret values remain in git history. Rotation made them useless; if you also want them gone and the
   repository was ever pushed or shared, rewrite history with a tool such as git filter-repo and force-push,
   coordinated with everyone who has a clone.
3. Close the remaining findings: `/agex Fix SEC-5 and SEC-6 from the security audit`.
```

## Expected Outcome

After `/agex-secure` alone:

- **No files change.** The command is read-only: nothing is edited, staged, or committed, and no audit tool is installed.
- **You receive** the SecurityAuditReport in full, plus a bottom line with the overall risk, the count per severity, and the top three priorities. No secret value appears anywhere: at most its first four characters.

After rotating the credentials and running the fix:

- `app/products.py` uses a parameterized query; `app/__init__.py` registers CSRF protection and sets `SameSite=Lax`; `app/templates/_macros.html` adds the token to every form; `requirements.txt` pins current Flask and Werkzeug releases plus Flask-WTF.
- `tests/` holds 27 passing tests, up from 18, including regression tests for SQL injection and CSRF.
- `git status` shows `.env` as deleted in the index, and your local `.env` with the new credentials stays on disk, ignored. Nothing is committed until you commit it.
- SEC-5 (container runs as root) and SEC-6 (cookie without `Secure`) remain open, as requested, and are listed in the report.

Verify it yourself:

```bash
python -m pip install -r requirements.txt -r requirements-dev.txt
python -m pytest -q
pip-audit -r requirements.txt
git status --short
```

Then start the development server with `flask --app app run --port 8000` and, in a second terminal, try the attacks that used to work:

```bash
curl -s "http://localhost:8000/products/search?q=%27%20OR%20%271%27%3D%271"
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost:8000/login -d 'username=a&password=b'
```

The search for `' OR '1'='1` now lists no products instead of the whole catalog, and a login form posted without a CSRF token returns `400`.

## Variations and Tips

- **Narrow the audit.** Pass a path or a concern: `/agex-secure app/auth.py` or `/agex-secure dependencies`. The environment-file checks always run, whatever the scope.
- **Choose exactly what gets fixed.** Name finding IDs, such as `/agex Fix SEC-2 from the security audit`. For the remaining findings, `/agex Fix SEC-5 and SEC-6 from the security audit` routes the Dockerfile change to the devops agent, which builds and checks the image locally and stops for your explicit confirmation before anything is pushed, and the cookie flag to the coder.
- **Keep the report in the conversation.** Artifacts live in the conversation, not in files. In a new session, run `/agex-secure` again or paste the report into your `/agex` task, so the orchestrator knows what SEC-1 to SEC-6 refer to.
- **Rotate first, always.** Removing a committed secret from the latest commit does not remove it from git history, and rewriting history does not reach clones, forks, or CI caches that already have it. Rotation is the only step that makes a leaked credential harmless.
- **Stop the next leak earlier.** `/agex Set up GitHub Actions CI that runs pytest and pip-audit on every pull request` adds a dependency check to every change; devops stops for your confirmation before pushing the workflow.
- **Keep secret files out of reach.** Claude Code permission rules can deny reads of `.env` files for the whole session; see the recommendations in [SECURITY.md](../../SECURITY.md).
- **Audit changes as they happen.** `/agex-review` adds the security agent automatically whenever a change touches authentication, input handling, cryptography, or secrets; see the [code review example](../code-review/task.md).

For the artifact formats used above, see the [Handoff Protocol](../../docs/HANDOFF-PROTOCOL.md); for the other walkthroughs, see the [Examples index](../../docs/EXAMPLES.md).
