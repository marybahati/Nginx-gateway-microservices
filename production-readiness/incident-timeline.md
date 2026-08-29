# 05 — Incident timeline (controlled failure)

**Exercise:** Inject latency on Service B via Service A `GET /lab/slow` while mixed greet traffic runs; observe detection and recovery.  
**Helper:** `AWS_PROFILE=devops-g5 ./scripts/reliability-incident-drill.sh`  
**Region:** `eu-west-1`  
**Account:** `240462142849`  
**Date:** 2026-08-29

## Injection procedure

```bash
export AWS_PROFILE=devops-g5 AWS_REGION=eu-west-1
./scripts/reliability-incident-drill.sh
```

## Timeline

| Phase | Timestamp (UTC) | Event | Evidence |
|-------|-----------------|-------|----------|
| **T0 — Failure introduced** | `2026-08-29 07:09:55` | Started drill: sustained `/lab/slow` + greet traffic (420s, concurrency 8) | Script: `T0 failure introduced` |
| **First signal** | `2026-08-29 07:09` (+~1 min) | ALB p95 `TargetResponseTime` ≈ **2.48 s** (SLO threshold 2 s) | CloudWatch metric datapoint 07:09 |
| **Alert** | `2026-08-29 07:14:52` (+~5 min) | `devops-g5-iac-alb-latency-p95` → ALARM | Script `*** First ALARM`; CW history OK→ALARM 07:14:30 |
| **Diagnosis** | `2026-08-29 07:15` | Lab slow path (`SLOW_DELAY_MS=2000`); greet still ~0.5 s when not on slow route | `/lab/slow` ≈2.4 s; B logs `lab_slow_endpoint_triggered` |
| **Mitigation** | `2026-08-29 07:18:04` (+~8 min) | Load generator stopped (drill duration ended) | Script: `Mitigation (load stopped)` |
| **Recovery** | `2026-08-29 07:18:04` | No ECS redeploy required; fault was traffic to lab route | — |
| **SLI restored** | `2026-08-29 07:18:18` (+~8.5 min) | **5/5** `GET /greet-service-b` → **200** | Script validation block |

## Metrics

| Metric | Value |
|--------|-------|
| **Time to Detect (TTD)** | Metric signal ≈ **1 min**; alert ≈ **5 min** (07:14:52 − 07:09:55) |
| **Time to Mitigate** | **~8 min** (07:18:04 − 07:09:55) |
| **Time to Recover (TTR)** | **~8.5 min** (07:18:18 − 07:09:55) — user journey proven |

Note: CloudWatch alarm can remain ALARM for a few more evaluation periods after traffic stops (needs 3 consecutive OK datapoints). Customer journey was restored at 07:18:18 regardless.

## Gaps identified

### Detection gap

**Gap:** Alert lagged ~5 minutes because the alarm requires **3×60s** periods with p95 > 2s, and `/lab/slow` only adds ~2s so p95 barely crosses the line.  
**Fix before production:** Lower WARNING threshold (e.g. p95 > 1.5s, 2 periods) and/or schedule `aws-reliability-smoke.yml` every 1–5 minutes.

### Recovery gap

**Gap:** Mitigation was “stop the load generator”; lab routes (`/lab/slow`, `/lab/fail`) remain publicly reachable via the ALB.  
**Fix before production:** Gate lab routes behind `ENABLE_LAB_ROUTES=false` in production task env.

## Raw evidence checklist

- [x] Drill transcript (terminal) with T0 / ALARM / mitigate / 5× greet 200
- [x] Alarm history: OK → ALARM at 2026-08-29 07:14:30 UTC  
  `aws cloudwatch describe-alarm-history --alarm-name devops-g5-iac-alb-latency-p95 --region eu-west-1`
- [ ] Dashboard PNG exports in `production-readiness/screenshots/` (attach from console)
- [x] Five successful greet curls after mitigation (ok=5/5)

## Reference: golden-scar incident (historical)

Callback-LB miss with Service A `desired=2`:

- **TTD:** Long — shallow health stayed green
- **TTR:** Hours until root cause; fix in `shared/callback.js`

This motivated the log-metric greet-failure alarm and sticky `X-Callback-URL` prevention (see `runbook.md`).
