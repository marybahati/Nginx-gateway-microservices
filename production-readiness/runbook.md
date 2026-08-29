# 04 — Recovery runbook: Greet 504 with green health

**Scenario:** `GET /greet-service-b` returns **504** while `GET /health?shallow=1` returns **200** and ALB targets show healthy.  
**Based on:** [golden-scar.md](../aws/docs/golden-scar.md) — callback landed on wrong Service A replica.

**Audience:** On-call engineer without prior context.

---

## Trigger

- Alert `devops-g5-iac-greet-failures` or `devops-g5-iac-alb-latency-p95` fires
- Synthetic smoke (`aws-reliability-smoke.yml`) fails on greet step
- User report: greeting endpoint times out

---

## 1. Verify impact

```bash
export AWS_REGION=eu-west-1
ALB=$(aws elbv2 describe-load-balancers --names devops-g5-iac-alb \
  --query 'LoadBalancers[0].DNSName' --output text)

curl -sS -o /dev/null -w "shallow:%{http_code}\n" "http://$ALB/health?shallow=1"
curl -sS -o /dev/null -w "greet:%{http_code}\n" "http://$ALB/greet-service-b"
```

| Result | Meaning |
|--------|---------|
| shallow 200, greet 504 | **This runbook applies** — async/callback path broken |
| both fail | Escalate to ALB / total outage runbook |
| greet 200 | False alarm or recovered — see Validate |

**Customer impact:** Greet journey broken; other shallow-health probes may still pass.

---

## 2. Diagnose

### 2a. Target and task health

```bash
aws ecs describe-services --cluster devops-g5-iac-cluster \
  --services devops-g5-iac-svc-service-a devops-g5-iac-svc-service-b devops-g5-iac-svc-service-c \
  --query 'services[].{name:serviceName,running:runningCount,desired:desiredCount}' --output table
```

Expect Service A `desired=2`, B/C `desired=1`, all `running` equals `desired`.

### 2b. Trace one failed request in logs

```bash
aws logs filter-log-events \
  --log-group-name /ecs/devops-g5-iac-service-a \
  --filter-pattern '{ $.event = "request_failed" && $.path = "/greet-service-b" }' \
  --limit 5 --region eu-west-1
```

Note `request_id` and `error` field (`downstream_timeout` implicates callback path).

### 2c. Confirm callback routing hypothesis

For the same `request_id`, search all three log groups:

```bash
RID="<request_id_from_above>"
for lg in service-a service-b service-c; do
  echo "=== $lg ==="
  aws logs filter-log-events --log-group-name "/ecs/devops-g5-iac-$lg" \
    --filter-pattern "\"$RID\"" --limit 20 --region eu-west-1 \
    --query 'events[].message' --output text
done
```

**Smoking gun:** C logs `callback_sent` with 200, but A shows `callback_received` on a *different* task than the one with `request_failed`.

### 2d. Check deployed image includes callback fix

```bash
curl -sS "http://$ALB/version" | jq .
# Compare SHA to terraform.tfvars image_tag_* — must include shared/callback.js fix
```

---

## 3. Mitigate

| Cause | Mitigation |
|-------|------------|
| Old image without `X-Callback-URL` | Update `image_tag_*` to fixed SHA → `terraform apply` |
| Service Connect stale peers | Force redeploy all three services (see Recover) |
| Single A task crash loop | ECS → service-a → stop failing task; verify circuit breaker not rolling back |

**Temporary traffic reduction (if overload):** scale Service A desired count only after confirming callback fix is deployed (scaling without fix can worsen callback LB issue).

---

## 4. Recover

```bash
CLUSTER=devops-g5-iac-cluster
for svc in devops-g5-iac-svc-service-a devops-g5-iac-svc-service-b devops-g5-iac-svc-service-c; do
  aws ecs update-service --cluster "$CLUSTER" --service "$svc" --force-new-deployment --region eu-west-1
done
```

Wait for deployments stable:

```bash
aws ecs wait services-stable --cluster devops-g5-iac-cluster \
  --services devops-g5-iac-svc-service-a devops-g5-iac-svc-service-b devops-g5-iac-svc-service-c \
  --region eu-west-1
```

---

## 5. Validate (prove user journey — not just container running)

```bash
# Must pass 5 consecutive greets
for i in 1 2 3 4 5; do
  curl -sf "http://$ALB/greet-service-b" >/dev/null && echo "greet $i OK" || echo "greet $i FAIL"
done

# Deep health includes downstream checks
curl -sS "http://$ALB/health" | jq '.dependencies'
```

**Success criteria:**

- 5/5 greet requests return HTTP 200
- No new `request_failed` on `/greet-service-b` in last 10 minutes
- Firing alarms return to OK

---

## 6. Escalate

| Condition | Escalate to |
|-----------|-------------|
| Mitigation fails after 30 min | Platform owner + Service A owner |
| Suspected security group regression | Network owner — verify `c_to_a_callback` rule |
| Repeated recurrence post-fix | Schedule golden-scar review; enable X-Ray segment SLIs |

**Post-incident:** Update `incident-timeline.md` with TTD/TTR; file gap fixes in failure-map.

---

## Test evidence

This runbook was validated against the documented golden-scar failure mode. Re-test after each deploy:

```bash
./scripts/load-test.sh "$ALB"   # if available
# or manual loop above
```

Record output in `production-readiness/screenshots/runbook-validation.txt`.
