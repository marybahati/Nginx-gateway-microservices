# Validation Commands and Expected Outputs

All commands run from your engineer machine unless noted.
Replace `<task-id-a>`, `<task-id-b>`, `<task-id-c>` with the short task IDs shown below.

```
service-a task: ee9ba1708dba492e9e35c24531a77f74
service-b task: ddbacb6c6a1a49f69c34224881e53569
service-c task: 295aa32c6a6e4138a996fcf0fa7d73cb
ALB DNS:        devops-g5-alb-751035582.eu-west-1.elb.amazonaws.com
```

---

## Phase 2 — Per-service checkpoint

### 2a. Task state: RUNNING and container health: HEALTHY

```bash
aws ecs describe-tasks \
  --cluster devops-g5-cluster \
  --tasks ee9ba1708dba492e9e35c24531a77f74 \
        ddbacb6c6a1a49f69c34224881e53569 \
        295aa32c6a6e4138a996fcf0fa7d73cb \
  --region eu-west-1 \
  --query 'tasks[*].{task:taskArn,lastStatus:lastStatus,health:healthStatus,image:containers[0].image}' \
  --output table
```

Expected output:
```
----------------------------------------------------------------------
|                         DescribeTasks                              |
+----------+----------+------------------------------------------+--+
| health   |lastStatus| image                                    |  |
+----------+----------+------------------------------------------+--+
| HEALTHY  | RUNNING  | 827478161993.dkr.ecr.eu-west-1...service-a:85a3a32 |
| HEALTHY  | RUNNING  | 827478161993.dkr.ecr.eu-west-1...service-b:85a3a32 |
| HEALTHY  | RUNNING  | 827478161993.dkr.ecr.eu-west-1...service-c:85a3a32 |
+----------+----------+------------------------------------------+--+
```

### 2b. Version: current Git SHA visible through ALB

```bash
curl -s http://devops-g5-alb-751035582.eu-west-1.elb.amazonaws.com/version | python3 -m json.tool
```

Expected output:
```json
{
    "service": "service-a",
    "version": "85a3a32",
    "status": "ok"
}
```

### 2c. CloudWatch: application log visible

```bash
aws logs tail /ecs/devops-g5-service-a --since 10m --region eu-west-1 | head -5
aws logs tail /ecs/devops-g5-service-b --since 10m --region eu-west-1 | head -5
aws logs tail /ecs/devops-g5-service-c --since 10m --region eu-west-1 | head -5
```

Expected output (one line per service, JSON structured):
```
2026-07-21T... service-a {"timestamp":"...","service":"service-a","event":"request_received",...}
2026-07-21T... service-b {"timestamp":"...","service":"service-b","event":"request_received",...}
2026-07-21T... service-c {"timestamp":"...","service":"service-c","event":"request_received",...}
```

### 2d. ECS Exec: shell access succeeds

```bash
aws ecs execute-command \
  --cluster devops-g5-cluster \
  --task ee9ba1708dba492e9e35c24531a77f74 \
  --container service-a \
  --interactive \
  --command "/bin/sh" \
  --region eu-west-1
```

Expected output:
```
The Session Manager plugin was installed successfully. Use the AWS CLI to start a session.
Starting session with SessionId: ecs-execute-command-...
#
```

---

## Phase 3 — Gate 2: Runtime and Security Proof

### 3a. Positive test — Internet → ALB (engineer machine)

```bash
curl -i http://devops-g5-alb-751035582.eu-west-1.elb.amazonaws.com/health
```

Expected output:
```
HTTP/1.1 200 OK
...
{"service":"service-a","status":"ok","dependencies":{"service-b":"ok","service-c":"ok"}}
```

### 3b. Positive test — ALB → A → B → C (full chain)

```bash
curl -s http://devops-g5-alb-751035582.eu-west-1.elb.amazonaws.com/greet-service-b \
  -H "X-Request-ID: gate2-test-001" | python3 -m json.tool
```

Expected output:
```json
{
    "request_id": "gate2-test-001",
    "status": "success",
    "message": "Request completed successfully"
}
```

### 3c. Positive test — A → B (inside service-a task via ECS Exec)

```bash
aws ecs execute-command \
  --cluster devops-g5-cluster \
  --task ee9ba1708dba492e9e35c24531a77f74 \
  --container service-a \
  --interactive \
  --command "curl -i --max-time 5 http://service-b:3002/health" \
  --region eu-west-1
```

Expected output:
```
HTTP/1.1 200 OK
{"service":"service-b","status":"ok","dependencies":{"service-c":"ok"}}
```

### 3d. Positive test — B → C (inside service-b task via ECS Exec)

```bash
aws ecs execute-command \
  --cluster devops-g5-cluster \
  --task ddbacb6c6a1a49f69c34224881e53569 \
  --container service-b \
  --interactive \
  --command "curl -i --max-time 5 http://service-c:3003/health" \
  --region eu-west-1
```

Expected output:
```
HTTP/1.1 200 OK
{"service":"service-c","status":"ok","dependencies":{}}
```

### 3e. Negative test — Internet → A direct (engineer machine, must be DENIED)

```bash
# Get service-a task public IP first
TASK_IP=$(aws ecs describe-tasks \
  --cluster devops-g5-cluster \
  --tasks ee9ba1708dba492e9e35c24531a77f74 \
  --region eu-west-1 \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text | xargs -I{} aws ec2 describe-network-interfaces \
  --network-interface-ids {} --region eu-west-1 \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

curl --connect-timeout 5 http://$TASK_IP:3001/health && echo "FAIL: exposed" || echo "OK: blocked"
```

Expected output:
```
curl: (28) Connection timed out after 5000 milliseconds
OK: blocked
```

### 3f. Negative test — Internet → B direct (must be DENIED)

```bash
TASK_IP_B=$(aws ecs describe-tasks \
  --cluster devops-g5-cluster \
  --tasks ddbacb6c6a1a49f69c34224881e53569 \
  --region eu-west-1 \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text | xargs -I{} aws ec2 describe-network-interfaces \
  --network-interface-ids {} --region eu-west-1 \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

curl --connect-timeout 5 http://$TASK_IP_B:3002/health && echo "FAIL: exposed" || echo "OK: blocked"
```

Expected output:
```
curl: (28) Connection timed out after 5000 milliseconds
OK: blocked
```

### 3g. Negative test — Internet → C direct (must be DENIED)

```bash
TASK_IP_C=$(aws ecs describe-tasks \
  --cluster devops-g5-cluster \
  --tasks 295aa32c6a6e4138a996fcf0fa7d73cb \
  --region eu-west-1 \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text | xargs -I{} aws ec2 describe-network-interfaces \
  --network-interface-ids {} --region eu-west-1 \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

curl --connect-timeout 5 http://$TASK_IP_C:3003/health && echo "FAIL: exposed" || echo "OK: blocked"
```

Expected output:
```
curl: (28) Connection timed out after 5000 milliseconds
OK: blocked
```

### 3h. Negative test — A → C (inside service-a task, must be DENIED)

```bash
aws ecs execute-command \
  --cluster devops-g5-cluster \
  --task ee9ba1708dba492e9e35c24531a77f74 \
  --container service-a \
  --interactive \
  --command "curl -i --max-time 5 http://service-c:3003/health" \
  --region eu-west-1
```

Expected output:
```
curl: (28) Connection timed out after 5 seconds
```

### 3i. Security group rules proof

```bash
# ALB SG — inbound :80 from internet
aws ec2 describe-security-groups --group-ids sg-0e0a3697d6f2bdd6a \
  --region eu-west-1 \
  --query 'SecurityGroups[0].IpPermissions' --output table

# Service-A SG — inbound :3001 from ALB SG only
aws ec2 describe-security-groups --group-ids sg-004dfad088190b075 \
  --region eu-west-1 \
  --query 'SecurityGroups[0].IpPermissions' --output table

# Service-B SG — inbound :3002 from service-a SG only
aws ec2 describe-security-groups --group-ids sg-08c4cf59960d46bde \
  --region eu-west-1 \
  --query 'SecurityGroups[0].IpPermissions' --output table

# Service-C SG — inbound :3003 from service-b SG only
aws ec2 describe-security-groups --group-ids sg-0a48cc8721a9f782a \
  --region eu-west-1 \
  --query 'SecurityGroups[0].IpPermissions' --output table
```

Expected — service-a SG shows only ALB SG as source, service-b SG shows only service-a SG, service-c SG shows only service-b SG. No `0.0.0.0/0` on application ports.

### 3j. ALB target health

```bash
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:eu-west-1:827478161993:targetgroup/devops-g5-tg-service-a/c625d63378c6c1d8 \
  --region eu-west-1 \
  --query 'TargetHealthDescriptions[*].{ip:Target.Id,port:Target.Port,state:TargetHealth.State}' \
  --output table
```

Expected output:
```
-------------------------------
|   DescribeTargetHealth      |
+-------------+-------+-------+
|     ip      | port  | state |
+-------------+-------+-------+
|  10.x.x.x   | 3001  | healthy |
|  10.x.x.x   | 3001  | healthy |
+-------------+-------+-------+
```

---

## Phase 4 — Trace one request end-to-end

### 4a. Send a traced request and follow logs across all three services

```bash
REQUEST_ID="trace-$(date +%s)"
curl -s http://devops-g5-alb-751035582.eu-west-1.elb.amazonaws.com/greet-service-b \
  -H "X-Request-ID: $REQUEST_ID"
echo "Tracing: $REQUEST_ID"

sleep 3

echo "=== service-a logs ==="
aws logs filter-log-events \
  --log-group-name /ecs/devops-g5-service-a \
  --filter-pattern "$REQUEST_ID" \
  --region eu-west-1 \
  --query 'events[*].message' --output text

echo "=== service-b logs ==="
aws logs filter-log-events \
  --log-group-name /ecs/devops-g5-service-b \
  --filter-pattern "$REQUEST_ID" \
  --region eu-west-1 \
  --query 'events[*].message' --output text

echo "=== service-c logs ==="
aws logs filter-log-events \
  --log-group-name /ecs/devops-g5-service-c \
  --filter-pattern "$REQUEST_ID" \
  --region eu-west-1 \
  --query 'events[*].message' --output text
```

Expected — same `request_id` appears in all three log groups showing the full chain: `request_received` in A → `request_forwarded` in B → `callback_sent` in C → `callback_received` in A → `request_completed` in A.

---

## Phase 4.3 — Kill a task (availability test)

### 4.3a. Start continuous traffic in one terminal

```bash
while true; do
  date
  curl -s -o /dev/null \
    -w "status=%{http_code} time=%{time_total}\n" \
    http://devops-g5-alb-751035582.eu-west-1.elb.amazonaws.com/health
  sleep 1
done
```

Expected output (steady state):
```
Mon Jul 21 14:00:00 UTC 2026
status=200 time=0.045
Mon Jul 21 14:00:01 UTC 2026
status=200 time=0.043
```

### 4.3b. Stop one service-a task (second terminal)

```bash
aws ecs stop-task \
  --cluster devops-g5-cluster \
  --task ee9ba1708dba492e9e35c24531a77f74 \
  --reason "availability-test" \
  --region eu-west-1 \
  --query 'task.{lastStatus:lastStatus,stoppedReason:stoppedReason}' \
  --output json
```

Expected output:
```json
{
    "lastStatus": "STOPPING",
    "stoppedReason": "availability-test"
}
```

### 4.3c. Watch ECS replace the task

```bash
watch -n 5 'aws ecs describe-services \
  --cluster devops-g5-cluster \
  --services devops-g5-svc-service-a \
  --region eu-west-1 \
  --query "services[0].{running:runningCount,pending:pendingCount,desired:desiredCount,events:events[0].message}" \
  --output json'
```

Expected output (during replacement):
```json
{
    "running": 1,
    "pending": 1,
    "desired": 2,
    "events": "service devops-g5-svc-service-a has started 1 tasks: task abc123."
}
```

Expected output (after recovery):
```json
{
    "running": 2,
    "pending": 0,
    "desired": 2,
    "events": "service devops-g5-svc-service-a has reached a steady state."
}
```

### 4.3d. Check target health transitions

```bash
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:eu-west-1:827478161993:targetgroup/devops-g5-tg-service-a/c625d63378c6c1d8 \
  --region eu-west-1 \
  --query 'TargetHealthDescriptions[*].{ip:Target.Id,state:TargetHealth.State,reason:TargetHealth.Reason}' \
  --output table
```

Expected output (during replacement):
```
+-------------+---------+---------------------------+
|     ip      |  state  |          reason           |
+-------------+---------+---------------------------+
|  10.x.x.x   | healthy |                           |
|  10.x.x.x   | initial | Elb.RegistrationInProgress|
+-------------+---------+---------------------------+
```

---

## Phase 5 — Hands-off delivery (Gate 3A)

### 5a. Verify pipeline auto-triggered after merge

```bash
aws codepipeline list-pipeline-executions \
  --pipeline-name devops-g5-pipeline-service-a \
  --region eu-west-1 \
  --max-results 1 \
  --query 'pipelineExecutionSummaries[0].{id:pipelineExecutionId,status:status,trigger:trigger.triggerType,commit:sourceRevisions[0].revisionId}' \
  --output json
```

Expected output:
```json
{
    "id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "status": "Succeeded",
    "trigger": "WebHook",
    "commit": "85a3a32eaef81f40e0b98e81fa995bfd0efdbb2f"
}
```

### 5b. Verify all three pipeline stages passed

```bash
for svc in service-a service-b service-c; do
  echo "=== devops-g5-pipeline-$svc ==="
  aws codepipeline get-pipeline-state \
    --name devops-g5-pipeline-$svc \
    --region eu-west-1 \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table
done
```

Expected output:
```
=== devops-g5-pipeline-service-a ===
-------------------------
|   GetPipelineState    |
+---------+-------------+
|  Stage  |   Status    |
+---------+-------------+
|  Source |  Succeeded  |
|  Build  |  Succeeded  |
|  Deploy |  Succeeded  |
+---------+-------------+
(same for service-b and service-c)
```

### 5c. Verify SHA-tagged image in ECR matches deployed commit

```bash
COMMIT=$(git rev-parse --short HEAD)
for svc in service-a service-b service-c; do
  echo "=== devops-g5-$svc ==="
  aws ecr describe-images \
    --repository-name devops-g5-$svc \
    --image-ids imageTag=$COMMIT \
    --region eu-west-1 \
    --query 'imageDetails[0].{tag:imageTags[0],pushedAt:imagePushedAt,size:imageSizeInBytes}' \
    --output json
done
```

Expected output:
```json
{
    "tag": "85a3a32",
    "pushedAt": "2026-07-21T...",
    "size": 79575522
}
```

### 5d. Verify new SHA visible through ALB after deploy

```bash
curl -s http://devops-g5-alb-751035582.eu-west-1.elb.amazonaws.com/version | python3 -m json.tool
```

Expected output:
```json
{
    "service": "service-a",
    "version": "85a3a32",
    "status": "ok"
}
```

---

## Gate 3B — Automatic rollback

### Step 1: Confirm current known-good revision

```bash
aws ecs describe-services \
  --cluster devops-g5-cluster \
  --services devops-g5-svc-service-a \
  --region eu-west-1 \
  --query 'services[0].taskDefinition' \
  --output text
```

Note the revision number (e.g. `devops-g5-td-service-a:7`) — this is the good revision to restore to.

### Step 2: Deploy a bad revision (wrong health-check path)

```bash
# Register a broken task definition with wrong health check path
aws ecs register-task-definition \
  --family devops-g5-td-service-a \
  --cli-input-json "$(aws ecs describe-task-definition \
    --task-definition devops-g5-td-service-a \
    --region eu-west-1 \
    --query 'taskDefinition' \
    --output json | \
    python3 -c "
import json,sys
td=json.load(sys.stdin)
td['containerDefinitions'][0]['healthCheck']['command']=['CMD-SHELL','exit 1']
for k in ['taskDefinitionArn','revision','status','requiresAttributes','compatibilities','registeredAt','registeredBy']:
    td.pop(k,None)
print(json.dumps(td))")" \
  --region eu-west-1 \
  --query 'taskDefinition.{family:family,revision:revision}' \
  --output json
```

Expected output:
```json
{
    "family": "devops-g5-td-service-a",
    "revision": 8
}
```

### Step 3: Force deploy the bad revision

```bash
aws ecs update-service \
  --cluster devops-g5-cluster \
  --service devops-g5-svc-service-a \
  --task-definition devops-g5-td-service-a:8 \
  --force-new-deployment \
  --region eu-west-1 \
  --query 'service.{taskDef:taskDefinition,status:status}' \
  --output json
```

### Step 4: Watch circuit breaker activate and rollback

```bash
watch -n 10 'aws ecs describe-services \
  --cluster devops-g5-cluster \
  --services devops-g5-svc-service-a \
  --region eu-west-1 \
  --query "services[0].{taskDef:taskDefinition,running:runningCount,deployments:deployments[*].{id:id,status:status,taskDef:taskDefinition,failed:failedTasks,rollout:rolloutState}}" \
  --output json'
```

Expected output (circuit breaker firing):
```json
{
    "deployments": [
        {
            "status": "IN_PROGRESS",
            "taskDef": "devops-g5-td-service-a:8",
            "failed": 3,
            "rollout": "FAILED"
        },
        {
            "status": "ACTIVE",
            "taskDef": "devops-g5-td-service-a:7",
            "rollout": "COMPLETED"
        }
    ]
}
```

Expected output (after rollback completes):
```json
{
    "taskDef": "arn:aws:ecs:eu-west-1:827478161993:task-definition/devops-g5-td-service-a:7",
    "running": 2,
    "deployments": [
        {
            "status": "PRIMARY",
            "taskDef": "devops-g5-td-service-a:7",
            "rollout": "COMPLETED"
        }
    ]
}
```

### Step 5: Confirm ALB target health recovered

```bash
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:eu-west-1:827478161993:targetgroup/devops-g5-tg-service-a/c625d63378c6c1d8 \
  --region eu-west-1 \
  --query 'TargetHealthDescriptions[*].{ip:Target.Id,state:TargetHealth.State}' \
  --output table
```

Expected output:
```
+-------------+---------+
|     ip      |  state  |
+-------------+---------+
|  10.x.x.x   | healthy |
|  10.x.x.x   | healthy |
+-------------+---------+
```

### Step 6: Confirm application responds through ALB

```bash
curl -s http://devops-g5-alb-751035582.eu-west-1.elb.amazonaws.com/health | python3 -m json.tool
```

Expected output:
```json
{
    "service": "service-a",
    "status": "ok",
    "dependencies": {
        "service-b": "ok",
        "service-c": "ok"
    }
}
```

---

## Phase 6 — Cleanup order

Run in this exact order to avoid dependency errors:

```bash
# 1. Stop pipelines (prevent new deploys during cleanup)
for svc in service-a service-b service-c; do
  aws codepipeline stop-pipeline-execution \
    --pipeline-name devops-g5-pipeline-$svc \
    --pipeline-execution-id $(aws codepipeline list-pipeline-executions \
      --pipeline-name devops-g5-pipeline-$svc --region eu-west-1 \
      --max-results 1 --query 'pipelineExecutionSummaries[0].pipelineExecutionId' \
      --output text) \
    --region eu-west-1 2>/dev/null || true
done

# 2. Scale down ECS services to 0
for svc in service-a service-b service-c; do
  aws ecs update-service \
    --cluster devops-g5-cluster \
    --service devops-g5-svc-$svc \
    --desired-count 0 \
    --region eu-west-1 --output json | python3 -c "import json,sys; s=json.load(sys.stdin)['service']; print(s['serviceName'], s['desiredCount'])"
done

# 3. Delete ECS services
for svc in service-a service-b service-c; do
  aws ecs delete-service \
    --cluster devops-g5-cluster \
    --service devops-g5-svc-$svc \
    --force \
    --region eu-west-1 \
    --query 'service.{name:serviceName,status:status}' --output json
done

# 4. Delete ALB and target group
ALB_ARN=$(aws elbv2 describe-load-balancers --region eu-west-1 \
  --query 'LoadBalancers[?LoadBalancerName==`devops-g5-alb`].LoadBalancerArn' --output text)
aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN --region eu-west-1
sleep 10
aws elbv2 delete-target-group \
  --target-group-arn arn:aws:elasticloadbalancing:eu-west-1:827478161993:targetgroup/devops-g5-tg-service-a/c625d63378c6c1d8 \
  --region eu-west-1

# 5. Delete ECS cluster
aws ecs delete-cluster --cluster devops-g5-cluster --region eu-west-1 \
  --query 'cluster.{name:clusterName,status:status}' --output json

# 6. Delete custom security groups
for sg in sg-0e0a3697d6f2bdd6a sg-004dfad088190b075 sg-08c4cf59960d46bde sg-0a48cc8721a9f782a; do
  aws ec2 delete-security-group --group-id $sg --region eu-west-1 && echo "Deleted $sg" || echo "Could not delete $sg (check dependencies)"
done

# 7. Delete CloudWatch log groups
for svc in service-a service-b service-c; do
  aws logs delete-log-group --log-group-name /ecs/devops-g5-$svc --region eu-west-1 && echo "Deleted /ecs/devops-g5-$svc"
done
```

### Confirm no billable resources remain

```bash
echo "=== ECS clusters ==="
aws ecs list-clusters --region eu-west-1 --query 'clusterArns' --output text

echo "=== ALBs ==="
aws elbv2 describe-load-balancers --region eu-west-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName,`devops-g5`)].LoadBalancerName' --output text

echo "=== Fargate tasks ==="
aws ecs list-tasks --cluster devops-g5-cluster --region eu-west-1 2>/dev/null || echo "Cluster gone"
```

Expected output after cleanup:
```
=== ECS clusters ===
(empty)
=== ALBs ===
(empty)
=== Fargate tasks ===
Cluster gone
```

> Never delete: Default VPC, default subnets, default route table, default Internet Gateway.
