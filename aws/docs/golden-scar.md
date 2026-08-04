# Golden scar — Service A desired=2 broke C→A callbacks

## Symptom

```text
curl http://<iac-alb>/health?shallow=1   → 200
curl http://<iac-alb>/greet-service-b    → 504  "upstream request timeout"
```

Shallow health and ALB target health stayed green. Console lab greet (Service A desired=1) still succeeded.

## Initial belief

Service Connect mesh was incomplete after first apply (missing peer names in `/etc/hosts`), or the C→A callback security-group rule was missing.

## Evidence collected

1. **Tasks RUNNING** in both AZs; ALB targets `10.5.10.x` / `10.5.11.x` healthy.
2. **CloudWatch logs** for one greet request:
   - A: `request_received` `/greet-service-b`
   - B: `request_received` `/greet` → `200`
   - C: `callback_sent` → `service-a` `200`
   - A: `callback_received` on **one** task, then originating task logged `request_failed` / `downstream_timeout`
3. **Console comparison:** `devops-g5-svc-service-a` desired count **1** → greet succeeds.
4. **IaC stack:** Service A desired count **2** (Assignment 1 requirement).

## Belief disproved

Not a missing SG rule (callback returned HTTP 200). Not a broken A→B→C forward path (B and C completed). Service Connect names resolved.

## Actual cause

`pendingCallbacks` is **in-memory per task**. Service C called `http://service-a:3001/greeting-rcvd` via Service Connect, which **load-balances** across both A tasks. The callback often landed on the sibling task that was not waiting for that `request_id`, so the originating task timed out with `downstream_timeout` / ALB 504.

## Repair

Propagate a sticky callback URL:

1. Service A resolves its **task private IP** from `ECS_CONTAINER_METADATA_URI_V4` (or `CALLBACK_BASE_URL`).
2. A sends `X-Callback-URL: http://<task-ip>:3001` to B.
3. B forwards the header to C.
4. C posts to that URL when allowed (private IP / lab hosts); otherwise falls back to `SERVICE_A_CALLBACK_URL`.

A→B and B→C still use Service Connect **service names**. Only the callback targets the originating task ENI (already permitted by `service-c-sg` → `service-a-sg` :3001).

## Prevention encoded

| Layer | Prevention |
|---|---|
| App | `shared/callback.js` + header contract in A/B/C |
| Tests | service-a chain test forwards `X-Callback-URL` |
| Docs | This golden scar + operate/demo runbooks |
| Ops | Runtime proof requires greet success with A desired=2 across two AZs |

## Demo narration (one minute)

> Symptom: greet 504 while health was green. We believed Service Connect or SGs. Logs proved the callback hit the wrong A replica. Cause: in-memory wait + Service Connect LB with desired=2. Fix: sticky task-IP callback URL. Prevention: code + tests + this scar.
