# End-to-End Test Runbook

**Group:** group-5  
**Cluster:** `devops-g5-cluster`  
**Region:** `eu-west-1`  
**Flow:** Internet → ALB → service-a → service-b → service-c → callback → service-a → response

Run every section in order. Each section tells you what to expect and what the result means.

---

## 0. Set shared variables

Run this block once at the start of every session. Every command below depends on these variables.

```bash
export AWS_DEFAULT_REGION=eu-west-1
export CLUSTER=devops-g5-cluster

export ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names devops-g5-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

export TG_ARN=$(aws elbv2 describe-target-groups \
  --names devops-g5-tg-service-a \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

export TASK_A=$(aws ecs list-tasks \
  --cluster $CLUSTER \
  --service-name devops-g5-svc-service-a \
  --query 'taskArns[0]' --output text)

export TASK_B=$(aws ecs list-tasks \
  --cluster $CLUSTER \
  --service-name devops-g5-svc-service-b \
  --query 'taskArns[0]' --output text)

export TASK_C=$(aws ecs list-tasks \
  --cluster $CLUSTER \
  --service-name devops-g5-svc-service-c \
  --query 'taskArns[0]' --output text)

echo "ALB:    $ALB_DNS"
echo "TG:     $TG_ARN"
echo "TASK_A: $TASK_A"
echo "TASK_B: $TASK_B"
echo "TASK_C: $TASK_C"
```

**Expected:** all five variables print non-empty values.  
If `ALB_DNS` is empty the ALB does not exist. If any `TASK_*` is empty that service has no running task.

---

## 1. Infrastructure state

### 1.1 ECS cluster is active

```bash
aws ecs describe-clusters \
  --clusters $CLUSTER \
  --query 'clusters[0].{name:clusterName,status:status,activeTasks:activeServicesCount}'
```

Expected: `status: ACTIVE`

### 1.2 All three services are running

```bash
aws ecs describe-services \
  --cluster $CLUSTER \
  --services devops-g5-svc-service-a devops-g5-svc-service-b devops-g5-svc-service-c \
  --query 'services[*].{name:serviceName,desired:desiredCount,running:runningCount,status:status}'
```

Expected: `running` equals `desired` for all three rows.

### 1.3 All three tasks are RUNNING and HEALTHY

```bash
aws ecs describe-tasks \
  --cluster $CLUSTER \
  --tasks $TASK_A $TASK_B $TASK_C \
  --query 'tasks[*].{group:group,lastStatus:lastStatus,health:healthStatus}'
```

Expected: `lastStatus: RUNNING`, `health: HEALTHY` for all three.

### 1.4 ALB is active

```bash
aws elbv2 describe-load-balancers \
  --names devops-g5-alb \
  --query 'LoadBalancers[0].{dns:DNSName,state:State.Code,scheme:Scheme,az:AvailabilityZones[*].ZoneName}'
```

Expected: `state: active`, `scheme: internet-facing`, two availability zones listed.

### 1.5 Target group has healthy targets

```bash
aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].{ip:Target.Id,port:Target.Port,state:TargetHealth.State,reason:TargetHealth.Reason}'
```

Expected: at least one target with `state: healthy`.

| state | meaning |
|---|---|
| `healthy` | ALB is routing traffic to this task |
| `unhealthy` | health check path is wrong or service-a is not responding on `/health` |
| `initial` | task just started, waiting for threshold |
| `draining` | task is being replaced |

---

## 2. ALB reachability

### 2.1 ALB responds on port 80

```bash
curl -i --max-time 10 http://$ALB_DNS/health
```

Expected:
```
HTTP/1.1 200 OK
{"service":"service-a","status":"ok","dependencies":{"service-b":"ok"},"version":"<sha>"}
```

| response | cause |
|---|---|
| `200` | ALB and service-a are working |
| `502` | service-a task is not running or not healthy |
| `503` | target group has no healthy targets |
| connection refused | ALB security group missing port 80 ingress from `0.0.0.0/0` |
| connection timeout | ALB does not exist or DNS has not propagated |

### 2.2 Confirm deployed SHA

```bash
curl -s http://$ALB_DNS/version
```

Expected:
```json
{"service":"service-a","version":"<7-char-git-sha>","status":"ok"}
```

The `version` value must match the first 7 characters of the commit that was built and pushed to ECR. If it shows `dev` the `SERVICE_VERSION` build arg was not passed during the Docker build.

---

## 3. Full end-to-end chain

This is the primary test. It exercises every hop:  
`ALB → service-a → service-b → service-c → callback → service-a → 200`

```bash
curl -i --max-time 35 http://$ALB_DNS/greet-service-b \
  -H "X-Request-ID: e2e-test-001"
```

Expected:
```
HTTP/1.1 200 OK
{"request_id":"e2e-test-001","status":"success","message":"Request completed successfully"}
```

| response | meaning |
|---|---|
| `200 success` | full chain completed including service-c callback |
| `500` | service-a reached service-b but something failed downstream |
| `504 downstream_timeout` | service-c callback never reached service-a within 30 s — callback path is broken |
| `502` | service-a is not running |

---

## 4. Correlation ID in all three log groups

Run immediately after section 3. The same `X-Request-ID` must appear in all three services.

```bash
for svc in service-a service-b service-c; do
  echo ""
  echo "=== $svc ==="
  aws logs filter-log-events \
    --log-group-name /ecs/devops-g5-$svc \
    --filter-pattern '"e2e-test-001"' \
    --query 'events[*].message' \
    --output text
done
```

Expected log events per service:

| service | expected events |
|---|---|
| service-a | `request_received`, `request_forwarded`, `callback_received` |
| service-b | `request_received` |
| service-c | `request_received`, `callback_sent` |

If a service shows no output that hop never received the request — that is your broken edge.

---

## 5. Internal connectivity (ECS Exec)

These tests prove Service Connect wiring and security group rules from inside the tasks.

### 5.1 service-a → service-b (must succeed)

```bash
aws ecs execute-command \
  --cluster $CLUSTER \
  --task $TASK_A \
  --container service-a \
  --interactive \
  --command "curl -s --max-time 5 http://service-b:3002/health"
```

Expected: `{"service":"service-b","status":"ok",...}`

### 5.2 service-b → service-c (must succeed)

```bash
aws ecs execute-command \
  --cluster $CLUSTER \
  --task $TASK_B \
  --container service-b \
  --interactive \
  --command "curl -s --max-time 5 http://service-c:3003/health"
```

Expected: `{"service":"service-c","status":"ok",...}`

### 5.3 service-c → service-a callback path (must succeed)

```bash
aws ecs execute-command \
  --cluster $CLUSTER \
  --task $TASK_C \
  --container service-c \
  --interactive \
  --command "curl -s --max-time 5 http://service-a:3001/health"
```

Expected: `{"service":"service-a","status":"ok",...}`

This is the path that unblocks the 30-second wait in section 3. If this times out, section 3 will return 504.

### 5.4 service-a → service-c (must be denied — security contract)

```bash
aws ecs execute-command \
  --cluster $CLUSTER \
  --task $TASK_A \
  --container service-a \
  --interactive \
  --command "curl -s --max-time 5 http://service-c:3003/health"
```

Expected: connection timed out after 5 seconds — **not** a 200.  
If this returns 200 the security group for service-c has an incorrect ingress rule allowing service-a.

---

## 6. Security boundary — internet cannot reach services directly

Run from your laptop. All three must fail or time out.

```bash
# Get the public IPs of the running tasks
aws ecs describe-tasks \
  --cluster $CLUSTER \
  --tasks $TASK_A $TASK_B $TASK_C \
  --query 'tasks[*].{group:group,eni:attachments[0].details[?name==`networkInterfaceId`].value|[0]}'
```

Use the ENI IDs to find the public IPs:

```bash
# Replace <eni-id-a>, <eni-id-b>, <eni-id-c> with values from above
aws ec2 describe-network-interfaces \
  --network-interface-ids <eni-id-a> <eni-id-b> <eni-id-c> \
  --query 'NetworkInterfaces[*].{group:Description,publicIp:Association.PublicIp}'
```

Then test each one:

```bash
curl -v --connect-timeout 5 http://<service-a-public-ip>:3001/health
curl -v --connect-timeout 5 http://<service-b-public-ip>:3002/health
curl -v --connect-timeout 5 http://<service-c-public-ip>:3003/health
```

Expected: all three time out.  
If any returns 200 that service's security group has an incorrect ingress rule from `0.0.0.0/0`.

---

## 7. Security group rules audit

Verify the rules match the traffic contracts without running live traffic.

```bash
# ALB SG — must allow 0.0.0.0/0 on port 80 inbound
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=devops-g5-alb-sg" \
  --query 'SecurityGroups[0].IpPermissions'

# service-a SG — must allow alb-sg:3001 and service-c-sg:3001 inbound only
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=devops-g5-service-a-sg" \
  --query 'SecurityGroups[0].IpPermissions'

# service-b SG — must allow service-a-sg:3002 inbound only
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=devops-g5-service-b-sg" \
  --query 'SecurityGroups[0].IpPermissions'

# service-c SG — must allow service-b-sg:3003 inbound only
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=devops-g5-service-c-sg" \
  --query 'SecurityGroups[0].IpPermissions'
```

Expected rule summary:

| security group | inbound source | port |
|---|---|---|
| `devops-g5-alb-sg` | `0.0.0.0/0` | 80 |
| `devops-g5-service-a-sg` | `devops-g5-alb-sg` | 3001 |
| `devops-g5-service-a-sg` | `devops-g5-service-c-sg` | 3001 |
| `devops-g5-service-b-sg` | `devops-g5-service-a-sg` | 3002 |
| `devops-g5-service-c-sg` | `devops-g5-service-b-sg` | 3003 |

---

## 8. CloudWatch logs — confirm each service is logging

```bash
aws logs tail /ecs/devops-g5-service-a --since 10m
aws logs tail /ecs/devops-g5-service-b --since 10m
aws logs tail /ecs/devops-g5-service-c --since 10m
```

Expected: structured JSON lines with `service`, `event`, `request_id`, `timestamp` fields.  
If a log group is empty the task definition `logConfiguration` is wrong or the execution role is missing CloudWatch permissions.

---

## 9. Pipeline and delivery state

### 9.1 CodeConnections is authorized

```bash
aws codeconnections list-connections \
  --query 'Connections[?ConnectionName==`devops-g5-github-connection`].{name:ConnectionName,status:ConnectionStatus}'
```

Expected: `status: AVAILABLE`

### 9.2 Latest pipeline execution succeeded

```bash
for svc in service-a service-b service-c; do
  echo ""
  echo "=== devops-g5-pipeline-$svc ==="
  aws codepipeline list-pipeline-executions \
    --pipeline-name devops-g5-pipeline-$svc \
    --query 'pipelineExecutionSummaries[0].{status:status,trigger:trigger.triggerType,started:startTime}' \
    --output table
done
```

Expected: `status: Succeeded` for all three pipelines.

### 9.3 ECR images are SHA-tagged

```bash
for svc in service-a service-b service-c; do
  echo ""
  echo "=== devops-g5-$svc ==="
  aws ecr list-images \
    --repository-name devops-g5-$svc \
    --query 'imageIds[*].imageTag' \
    --output table
done
```

Expected: tags are 7-character git SHAs. No `latest` tag should appear.

---

## 10. Availability test — kill a task and observe recovery

Open two terminals.

**Terminal 1 — continuous traffic:**

```bash
while true; do
  curl -s -o /dev/null \
    -w "$(date +%H:%M:%S) status=%{http_code} time=%{time_total}s\n" \
    http://$ALB_DNS/greet-service-b
  sleep 1
done
```

**Terminal 2 — stop one service-a task:**

```bash
# Record the task being stopped
echo "Stopping task: $TASK_A"
aws ecs stop-task --cluster $CLUSTER --task $TASK_A

# Watch ECS replace it
watch -n 3 "aws ecs describe-services \
  --cluster $CLUSTER \
  --services devops-g5-svc-service-a \
  --query 'services[0].{running:runningCount,pending:pendingCount,desired:desiredCount,events:events[0].message}'"
```

**Terminal 2 — watch target health recover:**

```bash
watch -n 5 "aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].{ip:Target.Id,state:TargetHealth.State}'"
```

Expected sequence in terminal 1:
1. One or two non-200 responses while the old task stops and the new task registers
2. Traffic returns to `status=200` once the replacement task passes health checks

Expected sequence in terminal 2:
1. Old task IP transitions to `draining` then disappears
2. New task IP appears as `initial` then `healthy`

---

## 11. Quick sanity — run anytime

Paste this as a single block to get a full status snapshot in under 30 seconds.

```bash
echo "=== ECS services ===" && \
aws ecs describe-services \
  --cluster $CLUSTER \
  --services devops-g5-svc-service-a devops-g5-svc-service-b devops-g5-svc-service-c \
  --query 'services[*].{name:serviceName,running:runningCount,desired:desiredCount}' \
  --output table && \
echo "" && \
echo "=== ALB target health ===" && \
aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].{ip:Target.Id,state:TargetHealth.State}' \
  --output table && \
echo "" && \
echo "=== Health endpoint ===" && \
curl -s http://$ALB_DNS/health | python3 -m json.tool && \
echo "" && \
echo "=== Full chain ===" && \
curl -s http://$ALB_DNS/greet-service-b \
  -H "X-Request-ID: sanity-$(date +%s)" | python3 -m json.tool && \
echo "" && \
echo "=== Version ===" && \
curl -s http://$ALB_DNS/version | python3 -m json.tool
```

Expected final output:
```json
{"service":"service-a","version":"<sha>","status":"ok"}
```

---

## Result reference

| section | pass condition | fail → check |
|---|---|---|
| 1 — infrastructure state | all services running, tasks HEALTHY, target healthy | ECS service events, stopped-task reason |
| 2 — ALB reachability | `GET /health` returns 200 | ALB SG port 80, target group health check path |
| 3 — full chain | `GET /greet-service-b` returns 200 | section 5 internal connectivity |
| 4 — correlation ID | same ID in all three log groups | missing service = broken hop |
| 5.1 — A→B | 200 from service-b | service-a-sg → service-b-sg rule, Service Connect name |
| 5.2 — B→C | 200 from service-c | service-b-sg → service-c-sg rule, Service Connect name |
| 5.3 — C→A | 200 from service-a | service-c-sg → service-a-sg rule on port 3001 |
| 5.4 — A→C | timeout | if 200: remove service-a-sg ingress rule from service-c-sg |
| 6 — internet denied | all three task IPs time out | if 200: remove 0.0.0.0/0 ingress from that service SG |
| 9 — pipeline | Succeeded, SHA tag in ECR | CodeBuild logs, IAM role permissions |
| 10 — availability | traffic recovers after task stop | desired count, health check thresholds |
