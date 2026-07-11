# Refuse-surface / attack catalog (adversarial-ticket)

Use as a checklist when red-teaming a ticket. Not every item applies to every change — pick by domain.

## AuthZ / multi-tenant
- [ ] Cross-tenant read (IDOR) via sibling resource IDs
- [ ] Cross-tenant write / delete
- [ ] Missing auth on new route while others are gated
- [ ] Role elevation (user → admin) via body/query/header
- [ ] Fail-open on auth errors (catch → allow)

## Input / path
- [ ] Path traversal (`../`, encoded variants) on file or key params
- [ ] Open redirect
- [ ] SSRF from user-controlled URLs
- [ ] Prototype pollution / mass assignment of privileged fields

## Label / provenance smuggling
- [ ] Client-supplied tenant/user id trusted over session
- [ ] Forged internal headers (`X-User-Id`, `X-Admin`)
- [ ] Webhook signature bypass

## Concurrency / TOCTOU
- [ ] Check-then-act races on balances, quotas, uniqueness
- [ ] Double-submit create

## Persistence / hollow impl
- [ ] “Success” with no durable write (memory-only store)
- [ ] Migration not applied; code assumes new column
- [ ] Soft-delete still readable via alternate path

## Spend / abuse
- [ ] Unbounded list / export
- [ ] Missing rate limit on expensive endpoint
- [ ] Cost attribution bypass

## Refuse surfaces (negative controls)
For each invariant the ticket claims, add or run a test that:
1. Attempts the bad action
2. Asserts **refusal** (4xx/deny/error)
3. Proves state unchanged

P0 findings: fix in-branch + ratchet (test fails if fix reverted). Audit the **whole class**, not only the one path that failed.
