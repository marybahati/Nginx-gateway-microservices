# Production readiness — GO / NO-GO

**Date:** 2026-08-29 (live drill completed)  
**Region:** `eu-west-1`  
**Stack:** `devops-g5-iac-*`  
**Account:** `240462142849`  
**Decision:** **GO WITH CONDITIONS**

---

## Decision

| Verdict | Rationale |
|---------|-----------|
| **GO WITH CONDITIONS** | Greet journey is multi-AZ, health-checked, SHA-deployed, with live CloudWatch SLIs/alarms and a **completed** failure drill (TTD ~5 min to alert, TTR ~8.5 min to journey restore). Not unconditional GO: single NAT, HTTP-only ALB, lab fault routes still exposed. |

### Conditions before unconditional GO

1. Confirm SNS email subscription for `alert_email` (inbox link).
2. Remove or disable lab fault routes (`/lab/slow`, `/lab/fail`) in production-bound images.
3. Add NAT redundancy or NAT failure monitoring (see failure-map gap).
4. Attach CloudWatch dashboard/alarm screenshots under `production-readiness/screenshots/`.

---

## Three strongest pieces of evidence

### 1. Defined reliability target tied to live metrics

`production-readiness/reliability-target.md` maps the greet journey to three SLIs with SLOs and error budgets. Dashboard `devops-g5-iac-reliability` and alarms are provisioned in account `240462142849`.

### 2. Actionable alerts that fired in a live drill

`devops-g5-iac-alb-latency-p95` moved **OK → ALARM** at **2026-08-29 07:14:52 UTC** during controlled `/lab/slow` injection (see `incident-timeline.md`). Alarm descriptions include what / why / where.

### 3. Tested recovery proving the user journey

After mitigation at 07:18:04, **5/5** `GET /greet-service-b` returned **200** by 07:18:18 (TTR ~8.5 min). Runbook covers the greener-health/callback failure mode separately (`runbook.md` + golden-scar).

---

## Evidence index

| # | Artifact | Path |
|---|----------|------|
| 01 | Reliability target | `production-readiness/reliability-target.md` |
| 02 | Failure map | `production-readiness/failure-map.md` |
| 03 | Alerts | `production-readiness/alert-definitions.md` + `infra/modules/observability` |
| 04 | Runbook | `production-readiness/runbook.md` |
| 05 | Incident timeline | `production-readiness/incident-timeline.md` |
| — | Screenshots | `production-readiness/screenshots/` |

---

## Would you put this system in production today?

**Answer for reviewers:** Yes **with conditions** — we measure the critical journey, alert on customer-impacting latency, and restored greet after a controlled failure with measured TTD/TTR. Do not ship until lab routes are gated, alert routing is confirmed, and NAT risk is accepted or mitigated.
