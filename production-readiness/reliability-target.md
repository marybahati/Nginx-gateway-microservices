# 01 — Reliability target

**Group:** 5  
**Region:** `eu-west-1`  
**Stack:** `devops-g5-iac-*`  
**Measurement window:** 30 rolling days (calendar month for error-budget review)

## Critical user journey

**Journey:** A client calls `GET /greet-service-b` on the public ALB and receives a successful greeting after the full async chain completes.

```text
Client → ALB:80 → Service A → Service B → Service C → callback POST → Service A → 200 JSON
```

This journey exercises every production hop: edge load balancing, orchestration, downstream relays, async callback, and multi-AZ Service A (desired=2 with sticky `X-Callback-URL`).

## SLIs, SLOs, and error budgets

| SLI | Definition (signal) | SLO (30d) | Error budget (30d) | CloudWatch source |
|-----|---------------------|-----------|--------------------|-------------------|
| **Availability** | Ratio of successful greet responses: `1 − (HTTPCode_Target_5XX_Count / RequestCount)` on Service A target group | ≥ **99.5%** successful | **0.5%** failed requests (~3.6 h equivalent at 1k req/min) | `AWS/ApplicationELB` → `HTTPCode_Target_5XX_Count`, `RequestCount` (dimensions: `TargetGroup`, `LoadBalancer`) |
| **Latency** | p95 end-to-end time at ALB for Service A targets | p95 **< 2 s** for 99% of 5-min windows | 1% of windows may exceed 2 s (~7.2 h) | `AWS/ApplicationELB` → `TargetResponseTime` stat **p95** |
| **Correctness** | Greet failures logged by Service A (`event=request_failed`, `path=/greet-service-b`) | **< 10** failures per 30d | 10 failed greets | Custom metric `devops-g5-iac/Application` → `GreetRequestFailures` (log metric filter) |

### Where measurements come from

1. **CloudWatch dashboard:** `devops-g5-iac-reliability` (Terraform `infra/modules/observability`)
2. **ALB metrics:** Load Balancers → `devops-g5-iac-alb` → Monitoring
3. **Log-derived correctness:** Log groups `/ecs/devops-g5-iac-service-a` → Metric filters → `GreetRequestFailures`
4. **GitHub Actions smoke:** workflow `aws-reliability-smoke.yml` (synthetic probe on each main push)

### Screenshots to attach

Capture and store under `production-readiness/screenshots/`:

- [ ] Dashboard `devops-g5-iac-reliability` — requests, 5xx, p95 latency panels
- [ ] ALB target group metric graph for `HTTPCode_Target_5XX_Count`
- [ ] Log metric `GreetRequestFailures` graph (or Logs Insights query below)

**Logs Insights query (correctness SLI audit):**

```sql
fields @timestamp, event, path, status, error, request_id
| filter service = "service-a" and path = "/greet-service-b"
| stats count(*) as total,
        sum(case when event = "request_failed" then 1 else 0 end) as failures
```

## Engineering behaviour by budget state

| Budget state | Behaviour |
|--------------|-----------|
| **Healthy** (>50% budget remaining) | Normal feature work; optional performance experiments in lab |
| **Consuming quickly** (25–50% remaining mid-window) | Freeze risky deploys; daily dashboard review; prioritize callback/latency fixes |
| **At risk** (<25% remaining) | Change freeze except mitigations; incident commander on greet failures; scale review Service A CPU |
| **Exhausted** | Stop non-fix releases; root-cause within 24h; post-incident action items before new features |

## SLO ↔ alert mapping

| SLI | Alert (Terraform) | Fires when |
|-----|-------------------|------------|
| Availability | `devops-g5-iac-alb-target-5xx` | >5 target 5xx in 2×1min periods |
| Availability | `devops-g5-iac-alb-unhealthy-hosts` | ≥1 unhealthy target |
| Latency | `devops-g5-iac-alb-latency-p95` | p95 >2s for 3×1min |
| Saturation (leading indicator) | `devops-g5-iac-service-a-cpu-high` | CPU >80% for 2×5min |
| Correctness | `devops-g5-iac-greet-failures` | >3 log failures in 5min |
