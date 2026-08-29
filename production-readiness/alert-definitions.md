# 03 — Actionable alerts

Implemented in Terraform: `infra/modules/observability/main.tf`  
SNS topic: `devops-g5-iac-reliability-alerts`  
Optional email: set `alert_email` in `terraform.tfvars` and confirm SNS subscription.

## Alert catalogue (≥3 signals)

### 1. Availability — ALB target 5xx

| Field | Value |
|-------|-------|
| **Name** | `devops-g5-iac-alb-target-5xx` |
| **Signal** | `AWS/ApplicationELB` `HTTPCode_Target_5XX_Count` (Sum, 60s) |
| **Threshold** | > 5 errors for 2 consecutive periods |
| **What is wrong?** | Service A targets are returning 5xx to the ALB |
| **Why does it matter?** | Customers calling `/greet-service-b` receive failed responses |
| **Where to investigate first?** | ECS → `devops-g5-iac-svc-service-a` → Events; logs `/ecs/devops-g5-iac-service-a`; then B/C chain |

### 2. Latency — p95 target response time

| Field | Value |
|-------|-------|
| **Name** | `devops-g5-iac-alb-latency-p95` |
| **Signal** | `AWS/ApplicationELB` `TargetResponseTime` (p95, 60s) |
| **Threshold** | > 2 seconds for 3 consecutive periods |
| **What is wrong?** | Greet journey is slow end-to-end at the edge |
| **Why does it matter?** | Users approach callback timeout (30s); SLO breach risk |
| **Where to investigate first?** | Logs for `downstream_timeout`; Service B/C duration_ms; CPU alarm on A |

### 3. Saturation — Service A CPU

| Field | Value |
|-------|-------|
| **Name** | `devops-g5-iac-service-a-cpu-high` |
| **Signal** | `AWS/ECS` `CPUUtilization` (Average, 300s) |
| **Threshold** | > 80% for 2 consecutive periods |
| **What is wrong?** | Service A is CPU-saturated |
| **Why does it matter?** | Leading indicator before latency and timeout failures |
| **Where to investigate first?** | ECS service metrics; consider desired count increase; check load test traffic |

### 4. Availability — unhealthy targets

| Field | Value |
|-------|-------|
| **Name** | `devops-g5-iac-alb-unhealthy-hosts` |
| **Signal** | `AWS/ApplicationELB` `UnHealthyHostCount` (Max, 60s) |
| **Threshold** | ≥ 1 for 2 periods |
| **What is wrong?** | At least one Service A task fails ALB health checks |
| **Why does it matter?** | Reduced capacity; greet may fail if remaining task overloaded |
| **Where to investigate first?** | Target group health reasons; container health check `curl .../health?shallow=1` |

### 5. Correctness — greet log failures

| Field | Value |
|-------|-------|
| **Name** | `devops-g5-iac-greet-failures` |
| **Signal** | Custom `devops-g5-iac/Application` `GreetRequestFailures` |
| **Threshold** | > 3 in 5 minutes |
| **What is wrong?** | Service A logged `request_failed` on `/greet-service-b` |
| **Why does it matter?** | User journey failed while shallow health may still pass |
| **Where to investigate first?** | [golden-scar runbook](./runbook.md); filter logs by `request_id` |

## Alerts we intentionally avoid

| Condition | Reason |
|-----------|--------|
| Single 4xx spike | No operator action; client error |
| ECS deployment IN_PROGRESS | Self-healing rolling update |
| Low request volume overnight | Not customer-impacting |

## Verification commands

```bash
# List alarms and state
aws cloudwatch describe-alarms --alarm-name-prefix devops-g5-iac- \
  --region eu-west-1 \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}' --output table

# Open dashboard
echo "https://eu-west-1.console.aws.amazon.com/cloudwatch/home?region=eu-west-1#dashboards/dashboard/devops-g5-iac-reliability"
```

## Screenshots to attach

- [ ] CloudWatch Alarms list showing OK state after deploy
- [ ] One alarm detail page (description shows what/why/where)
- [ ] Dashboard with live metrics during load test (`scripts/load-test.sh`)
