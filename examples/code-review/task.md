# Example: Review a Payment Webhook Handler Before Committing

This walkthrough follows `/agex-review` on staged changes that touch signature verification. Because the change involves cryptography and untrusted input, AGEX runs the reviewer and the security agent in parallel, merges their findings, and returns CHANGES_REQUESTED for a HIGH issue: the webhook signature is compared with a comparison that is not constant-time. It ends with an optional follow-up run that fixes the findings.

## Scenario

`billing-service` is a Node.js 20 service written in TypeScript with Express 4, PostgreSQL (`pg`), and Jest with supertest. Your payment provider now sends webhooks, and you have written a handler for them. The provider:

- signs each delivery with HMAC-SHA256, using the endpoint's webhook secret (`PAYMENTS_WEBHOOK_SECRET`) as the key, over the string formed by the timestamp, a period, and the raw request body;
- sends a `Payment-Signature` header with a `t` field (Unix timestamp in seconds) and a `v1` field (the hex-encoded HMAC);
- retries a delivery until it receives a 2xx response, so the same event can arrive more than once.

You have staged four files with `git add`:

| File | Change |
|---|---|
| `src/webhooks/payments.ts` | New handler for `POST /webhooks/payments` |
| `src/app.ts` | Mounts the route with `express.raw({ type: 'application/json' })`, before the global `express.json()` |
| `src/orders/order.service.ts` | New `markPaid(orderId, paymentId)`: updates the order and emails a receipt |
| `tests/webhooks/payments.test.ts` | Two tests: a valid signature returns 200, an invalid one returns 400 |

The core of the staged handler (`src/webhooks/payments.ts`, lines 12-35):

```ts
export async function paymentsWebhook(req: Request, res: Response): Promise<void> {
  const header = req.header('Payment-Signature') ?? '';
  const parts = Object.fromEntries(header.split(',').map((kv) => kv.split('=')));
  const timestamp = parts.t;
  const signature = parts.v1;

  const expected = crypto
    .createHmac('sha256', config.paymentsWebhookSecret)
    .update(`${timestamp}.${req.body.toString('utf8')}`)
    .digest('hex');

  if (signature !== expected) {
    res.status(400).json({ error: 'invalid_signature' });
    return;
  }

  const event = JSON.parse(req.body.toString('utf8'));
  logger.info({ event }, 'payment webhook received');

  if (event.type === 'payment.succeeded') {
    await orderService.markPaid(event.data.orderId, event.data.paymentId);
  }
  res.status(200).json({ received: true });
}
```

Both tests pass. Before committing, you want an adversarial second pair of eyes.

## The Command

```text
/agex-review
```

With a plugin install the same command is `/agex:agex-review`. No argument is needed: without a focus argument, `/agex-review` reviews staged changes first.

## What AGEX Does

`/agex-review` is a focused specialist command, not a full orchestration run: there is no complexity classification, planner, or coder, and the command is strictly read-only. Before the model reads the prompt, it injects `git status`, the staged and unstaged diff summaries and diffs (truncated for orientation), the recent commits, and the last commit.

1. **Target selection.** No focus argument was given, so the first match in the command's order applies: the staged changes, four files. The main conversation states this target in one line.
2. **Security-sensitivity check, then a parallel dispatch.** The diff computes and compares an HMAC (cryptography), parses an untrusted header and request body (input handling), and reads a secret from configuration. That meets the rule for adding the security agent, so the main conversation sends two Agent calls in one message: `reviewer` and `security` (`agex:reviewer` and `agex:security` in a plugin install). Both receive the same target, the list of changed files, and instructions to read the full files and their callers rather than trusting the truncated diff.
3. **reviewer → ReviewVerdict, CHANGES_REQUESTED.** Four issues:
   - **R-1, HIGH, security:** the signature is compared with `!==`, which stops at the first differing character. Response timing leaks how much of a forged signature is correct. The fix is `crypto.timingSafeEqual` on equal-length buffers, and the length check must come first because `timingSafeEqual` throws a `RangeError` on inputs of different length, which would turn a malformed header into a 500.
   - **R-2, MEDIUM, security:** the timestamp is parsed but never checked, so a captured delivery can be replayed at any time later.
   - **R-3, MEDIUM, logic:** `markPaid` is not idempotent. Every retried delivery sends another receipt email, and a late retry can overwrite a later status such as `refunded` back to `paid`.
   - **R-4, LOW, tests:** no tests for a missing or malformed header, a wrong-length or non-hex signature, a stale timestamp, or a duplicate delivery.

   By the decision rule, no CRITICAL plus at least one HIGH gives CHANGES_REQUESTED.
4. **security → SecurityAuditReport, FINDINGS.** SEC-1 (HIGH, CWE-208, observable timing discrepancy) and SEC-2 (MEDIUM, CWE-294, capture-replay) confirm R-1 and R-2 independently. SEC-3 (LOW, CWE-532) adds that the handler logs the full event, including customer billing details. The secrets scan is clean (the secret comes from configuration, and `.env.example` holds an empty value), `npm audit --omit=dev` reports no vulnerabilities, and the configuration review confirms that the raw body parser is mounted correctly, so the HMAC covers the exact bytes received.
5. **Validation and bottom line.** The main conversation checks both envelopes and section orders, confirms that each Status matches its own table, and presents both artifacts in full. The bottom line takes the stricter of the two: **CHANGES_REQUESTED**, with 1 HIGH, 2 MEDIUM, and 2 LOW after merging the two duplicated findings. Nothing was edited, staged, or committed, and no secret value appears anywhere in the output.
6. **Optional follow-up: fix with `/agex`.** `/agex-review` never fixes anything itself; it suggests `/agex` with the verdict as input. Because the ReviewVerdict and SecurityAuditReport are already in the conversation, you can run:

   ```text
   /agex Fix R-1, R-2, R-3, and SEC-3 from the webhook review, and add tests for the cases listed in R-4
   ```

   The orchestrator classifies this as MEDIUM (three source files and one test file in one component, with the remediation already specified) and runs a short chain:
   - **coder → CodeDiff, IMPLEMENTED.** Parses the header strictly, rejects timestamps more than 300 seconds from the server clock, computes the HMAC over the raw bytes, and compares 32-byte buffers with `crypto.timingSafeEqual` after a length check. `markPaid` becomes a conditional update (`WHERE id = $1 AND status = 'pending' RETURNING id`) that sends the receipt only when a row actually changed. Logging is reduced to the event id and type.
   - **tester → TestReport, PASS.** Adds six tests: missing header, header without `v1`, wrong-length signature (400, not 500), non-hex signature, a timestamp 301 seconds old, and a duplicate delivery that sends exactly one receipt.
   - **reviewer and security in parallel → ReviewVerdict APPROVED and SecurityAuditReport PASS.** The security agent re-checks the same scope and finds nothing open.
   - **AgexReport, DONE,** after four dispatches.

## Illustrative Artifact Excerpts

The excerpts below are illustrative. They show the envelope, section order, and level of detail you should expect, abridged for length. They are not captured output from a recorded run.

### ReviewVerdict

```markdown
<!-- agex:artifact type=ReviewVerdict version=1 -->
## ReviewVerdict: Payment webhook handler, staged changes
**Producer:** reviewer · **Status:** CHANGES_REQUESTED · **Confidence:** HIGH

### Summary
Reviewed the four staged files plus src/config.ts and the orders repository they call. The raw-body
setup is correct, but signature verification is not constant-time (HIGH), the timestamp is never
checked, and payment handling is not idempotent under the provider's retries.

### Issues
| ID | Severity | Category | Location | Problem | Remediation |
|---|---|---|---|---|---|
| R-1 | HIGH | security | `src/webhooks/payments.ts:23` | `signature !== expected` returns at the first differing character, so response timing leaks how much of a forged signature is correct | Decode both to Buffers; if lengths differ, reject with 400; otherwise compare with `crypto.timingSafeEqual`. Check length first: timingSafeEqual throws RangeError on unequal lengths |
| R-2 | MEDIUM | security | `src/webhooks/payments.ts:15` | `t` is signed but never compared with the current time, so captured deliveries can be replayed | Reject when `t` is not an integer or differs from the server clock by more than 300 seconds |
| R-3 | MEDIUM | logic | `src/orders/order.service.ts:52` | Retried deliveries re-send the receipt, and a late retry sets a refunded order back to paid | `UPDATE orders SET status = 'paid', payment_id = $2 WHERE id = $1 AND status = 'pending' RETURNING id`; email only when a row is returned |
| R-4 | LOW | tests | `tests/webhooks/payments.test.ts:1` | Only the happy path and one bad signature are tested | Add missing header, missing v1, wrong-length and non-hex v1, stale timestamp, and duplicate delivery cases |

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
- express.raw is scoped to the webhook route and registered before express.json, so the HMAC covers the exact bytes received.
- The webhook secret comes from validated configuration, not from code.
- Unknown event types are acknowledged with 200, so the provider does not retry them forever.
```

### SecurityAuditReport

```markdown
<!-- agex:artifact type=SecurityAuditReport version=1 -->
## SecurityAuditReport: Payment webhook handler, staged changes
**Producer:** security · **Status:** FINDINGS · **Confidence:** HIGH

### Scope
- Staged changes: src/webhooks/payments.ts, src/app.ts, src/orders/order.service.ts, tests/webhooks/payments.test.ts
- Callers and configuration read for context: src/config.ts, src/orders/order.repository.ts
- Out of scope: the rest of the project (run /agex-secure for a full audit)

### Risk Matrix
| ID | Severity | Category | Location | Finding | Evidence (redacted) | Remediation |
|---|---|---|---|---|---|---|
| SEC-1 | HIGH | CWE-208 | `src/webhooks/payments.ts:23` | Non-constant-time HMAC comparison lets an attacker who can time responses forge a signature incrementally | `if (signature !== expected) {` | Compare equal-length Buffers with crypto.timingSafeEqual |
| SEC-2 | MEDIUM | CWE-294 | `src/webhooks/payments.ts:15` | Signed timestamp never validated; any captured delivery replays successfully | `const timestamp = parts.t;` | Enforce a 300-second tolerance |
| SEC-3 | LOW | CWE-532 | `src/webhooks/payments.ts:29` | Full event payload, including customer billing details, logged at info level | `logger.info({ event }, 'payment webhook received');` | Log event.id and event.type only |

### Secrets Scan
- Patterns searched: private key blocks, API key and webhook-secret prefixes, AWS access key ids, bearer tokens, password and secret assignments
- Tracked env files: .env.example (template; PAYMENTS_WEBHOOK_SECRET is empty)
- Result: no secrets found; the handler reads the secret from src/config.ts:14, which requires it at startup

### Dependency Audit
- `npm audit --omit=dev` — found 0 vulnerabilities; the diff adds no dependencies (it uses node:crypto)

### Configuration Review
- Body parsing — express.raw on the webhook route (src/app.ts:18) precedes the global express.json (src/app.ts:21) — no issue
- Route authentication — the route is outside session auth and authenticated by signature, as intended — see SEC-1 and SEC-2

### Summary
- CRITICAL: 0 · HIGH: 1 · MEDIUM: 1 · LOW: 1
- Overall risk: HIGH
```

### AgexReport from the follow-up `/agex` run (abridged)

```markdown
<!-- agex:artifact type=AgexReport version=1 -->
## AgexReport: Harden payment webhook verification and idempotency
**Producer:** orchestrator · **Status:** DONE · **Confidence:** HIGH

### Task
Fix R-1, R-2, R-3, and SEC-3 from the webhook review and add the tests listed in R-4. MEDIUM.

### Outcome
Signatures are verified in constant time with a 300-second replay window, duplicate deliveries are
harmless, and logs no longer contain billing details.

### Agents Deployed
| # | Agent | Artifact | Status | Cycle |
|---|---|---|---|---|
| 1 | coder | CodeDiff | IMPLEMENTED | coder-reviewer 1/3 |
| 2 | tester | TestReport | PASS | coder-reviewer 1/3 |
| 3 | reviewer | ReviewVerdict | APPROVED | coder-reviewer 1/3 |
| 4 | security | SecurityAuditReport | PASS | n/a |

### Changes
- Modified: src/webhooks/payments.ts, src/orders/order.service.ts, tests/webhooks/payments.test.ts

### Verification Evidence
- `npx tsc --noEmit` → exit 0
- `npm test -- webhooks` → 8 passed, 0 failed
- ReviewVerdict: APPROVED; SecurityAuditReport: PASS (0 findings)

### Open Issues & Escalations
- None

### Next Steps
1. Re-stage the updated files (`git add -u`) and run `/agex-review` once more if you want a final look at the staged result.
2. Commit.
```

In the follow-up report, the earlier `/agex-review` verdict, passed to the orchestrator as input, plays the part of the first review, so the fix, its re-test, and the re-review form coder-reviewer cycle 1 of 3.

## Expected Outcome

After `/agex-review` alone:

- **No files change.** The command is read-only: nothing is edited, staged, or committed.
- **You receive** the ReviewVerdict and SecurityAuditReport in full, plus a bottom line of CHANGES_REQUESTED with issue counts per severity. Each issue has an exact location and a concrete remediation.

After the optional follow-up `/agex` run:

- `src/webhooks/payments.ts` verifies signatures in constant time, rejects stale timestamps, and logs only the event id and type; `src/orders/order.service.ts` updates orders conditionally and sends receipts once; `tests/webhooks/payments.test.ts` grows from two to eight tests.
- The fixes are unstaged working-tree changes on top of your staged files. Run `git diff` to see exactly what AGEX changed, then stage and commit.

## Variations and Tips

- **Review something other than the staged set.** Pass a focus argument: a path (`/agex-review src/webhooks`) or a git ref. `/agex-review main` reviews everything on your branch since it diverged from `main`. With nothing staged and no argument, the command falls back to unstaged and untracked changes, then to the last commit.
- **Stage deliberately.** `git add -p` lets you stage exactly the hunks you want reviewed. Smaller review targets get sharper reviews; the injected diff is truncated at 400 lines for orientation, although the agents read full files regardless.
- **You do not have to ask for the security agent.** Any change touching authentication, input handling, cryptography, or secrets triggers it automatically. For changes without those, only the reviewer runs, which is cheaper.
- **Blocking issues stop everything.** Had the handler skipped signature verification entirely, that would have been a CRITICAL finding and a BLOCKED verdict: fix it before anything else.
- **Audit beyond the diff.** `/agex-review` scopes the security agent to the change. For the whole codebase, including dependencies and configuration, use `/agex-secure`; see the [security audit example](../security-audit/task.md).

For the artifact formats used above, see the [Handoff Protocol](../../docs/HANDOFF-PROTOCOL.md); for the other walkthroughs, see the [Examples index](../../docs/EXAMPLES.md).
