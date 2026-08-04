# Live demonstration runbook — Assignment 1 (Group 5)

Oral demo script and cold operator checklist. Every step has a command and a pass/fail expected result.

| Field | Value |
|---|---|
| Region | `eu-west-1` only |
| Tool | Terraform (≥1.6) + AWS provider |
| Workload prefix | `devops-g5-iac-` |
| Do not touch | console lab `devops-g5-*` (no `-iac`) |
| Namespace | `group5-iac.internal` |
| State bucket | `devops-g5-iac-tfstate-827478161993` |
| Lock table | `devops-g5-iac-tflock` |
| State key | `lab/terraform.tfstate` |
| Account | `827478161993` |
| Lab dir | `infra/environments/lab` |

```text
Owner types. Team observes. Operator narrates. Coach asks questions. Evidence decides.
```

No one takes over another engineer’s terminal.

---

## How to run this demo

1. Export the constants block once at the start of every session.
2. Execute steps **in order** within each demo.
3. Read the **Expected** block **before** running the command; then show the live match.
4. Say pass/fail out loud. If fail — stop, diagnose, do not improvise console creates.
5. Demo 2 greet requires the sticky-callback image (see Demo 4). If greet is 504 with A=2, that is the scar — finish Demo 4, then release the fixed SHA before claiming architecture allow.

---

## Constants (export once)

```bash
export AWS_DEFAULT_REGION=eu-west-1
export AWS_REGION=eu-west-1
export ACCOUNT=827478161993
export CLUSTER=devops-g5-iac-cluster
export SVC_A=devops-g5-iac-svc-service-a
export SVC_B=devops-g5-iac-svc-service-b
export SVC_C=devops-g5-iac-svc-service-c
export ALB_NAME=devops-g5-iac-alb
export TG_NAME=devops-g5-iac-tg-service-a
export STATE_BUCKET=devops-g5-iac-tfstate-827478161993
export LOCK_TABLE=devops-g5-iac-tflock
export LAB_DIR="$(git rev-parse --show-toplevel)/infra/environments/lab"
cd "$LAB_DIR"
```

After apply (or when stack is up):

```bash
export ALB="$(terraform output -raw alb_dns_name)"
echo "ALB=$ALB"
```

---

## Preflight (before Demo 1)

| Check | Command | Expected |
|---|---|---|
| Tools | `terraform version && aws --version && curl --version \| head -1` | Terraform ≥1.6; aws/curl present |
| Identity | `aws sts get-caller-identity --output table` | `Account` = `827478161993` |
| Region | `aws configure get region; echo $AWS_DEFAULT_REGION` | Both `eu-west-1` |
| tfvars | `test -f terraform.tfvars && grep -E 'image_tag_[abc]' terraform.tfvars` | File exists; three SHA tags (not `latest`) |
| Session Manager (Demos 2.x Exec) | `session-manager-plugin --version` | Plugin installed (required for `execute-command`) |

If `terraform.tfvars` is missing:

```bash
cp terraform.tfvars.example terraform.tfvars
# edit image_tag_a/b/c to SHAs that exist in ECR (or use console bootstrap once)
```

If the remote state backend does not exist yet (true zero):

```bash
cd "$(git rev-parse --show-toplevel)/infra/bootstrap"
terraform init
terraform apply
terraform output
cd "$LAB_DIR"
```

| Expected (bootstrap) |
|---|
| Creates state bucket + DynamoDB lock only |
| Outputs include `state_bucket` and `lock_table` |
| Does **not** create VPC/ALB/ECS |

---

## Demo 1 — Spin up from zero

**Narrate:** highest risk is create of NAT + ALB + ECS; no console creates; state backend survives later destroy.

### 1.1 Prove workload is absent

```bash
aws ecs describe-clusters --clusters "$CLUSTER" \
  --query '{status:clusters[0].status,failure:failures[0].reason}' --output table

aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?LoadBalancerName=='$ALB_NAME'].LoadBalancerName" --output text
```

| Expected | Pass if |
|---|---|
| Cluster `failure` = `MISSING`, **or** `status` = `INACTIVE` | No ACTIVE IaC cluster |
| ALB name print is empty | No `devops-g5-iac-alb` |

Narrate: console `devops-g5-alb` / `devops-g5-cluster` may still exist — leave them alone.

### 1.2 Init + validate

```bash
cd "$LAB_DIR"
terraform init
terraform fmt -check
terraform validate
```

| Expected |
|---|
| `Terraform has been successfully initialized!` (S3 backend + DynamoDB lock) |
| `fmt -check` exit 0 |
| `Success! The configuration is valid.` |

### 1.3 Plan (speak the full change brief)

```bash
terraform plan -out=lab.tfplan
```

| Expected (first create) |
|---|
| Plan will create VPC `10.5.0.0/16`, NAT, ALB, cluster, SGs, ECR×3, ECS A=2 B=1 C=1, CodeBuild×3, CodePipeline×3 (build/push), artifact bucket, IAM |
| **No** unexpected replacements |
| Operator speaks: additions / replacements / user impact / security / cost / recovery / reason |

```text
Expected additions: VPC, NAT, ALB, ECS, SGs, ECR iac, pipelines, logs
Expected replacements: none
User impact: new IaC ALB DNS; console lab unchanged
Security impact: private tasks, SG refs, no public IPs
Cost impact: NAT + ALB + Fargate — destroy after demos
Recovery: terraform destroy then re-apply; state survives
Reason: Assignment 1 greenfield create
```

### 1.4 Apply + prove clean follow-up plan

```bash
terraform apply lab.tfplan
terraform plan
terraform output
```

| Expected |
|---|
| Apply finishes with no console repair |
| Follow-up plan: `No changes. Your infrastructure matches the configuration.` |
| Outputs include at least: |

```text
alb_dns_name          = "devops-g5-iac-alb-….eu-west-1.elb.amazonaws.com"
cluster_name          = "devops-g5-iac-cluster"
namespace             = "group5-iac.internal"
name_prefix           = "devops-g5-iac"
deployed_image_tags   = { a = "<sha>", b = "<sha>", c = "<sha>" }
pipelines             = {
  a = "devops-g5-iac-pipeline-service-a"
  b = "devops-g5-iac-pipeline-service-b"
  c = "devops-g5-iac-pipeline-service-c"
}
release_path          = "build/push SHA via CodePipeline → set image_tag_{a,b,c} …"
```

```bash
export ALB="$(terraform output -raw alb_dns_name)"
```

### 1.5 Wait until Service A targets are healthy

```bash
TG=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# Poll until 2 healthy (usually 2–5 minutes after apply)
aws elbv2 describe-target-health --target-group-arn "$TG" --output table
```

| Expected |
|---|
| Two targets, `Target.Id` = private IPs (`10.5.10.x` / `10.5.11.x`) |
| `TargetHealth.State` = `healthy` for both |
| Target type implied: **ip** (awsvpc) |

### 1.6 Services, AZs, no public IP, logs, discovery

```bash
aws ecs describe-services --cluster "$CLUSTER" \
  --services "$SVC_A" "$SVC_B" "$SVC_C" \
  --query 'services[*].{name:serviceName,desired:desiredCount,running:runningCount,status:status}' \
  --output table
```

| Expected table |
|---|
| `devops-g5-iac-svc-service-a` desired **2** running **2** status `ACTIVE` |
| `…-service-b` desired **1** running **1** |
| `…-service-c` desired **1** running **1** |

```bash
TASKS=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SVC_A" \
  --desired-status RUNNING --query 'taskArns' --output text)

aws ecs describe-tasks --cluster "$CLUSTER" --tasks $TASKS \
  --query 'tasks[*].{az:availabilityZone,last:lastStatus,ip:attachments[0].details[?name==`privateIPv4Address`].value|[0]}' \
  --output table

# Prove no public IP assignment on the service network config
aws ecs describe-services --cluster "$CLUSTER" --services "$SVC_A" \
  --query 'services[0].networkConfiguration.awsvpcConfiguration.assignPublicIp' --output text
```

| Expected |
|---|
| Two AZs present (e.g. `eu-west-1a` and `eu-west-1b`) |
| Private IPs only |
| `assignPublicIp` = `DISABLED` |

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /ecs/devops-g5-iac-service \
  --query 'logGroups[*].logGroupName' --output table

terraform output -raw namespace
```

| Expected |
|---|
| `/ecs/devops-g5-iac-service-a` |
| `/ecs/devops-g5-iac-service-b` |
| `/ecs/devops-g5-iac-service-c` |
| Namespace print: `group5-iac.internal` |
| Discovery names (narrate): `service-a`, `service-b`, `service-c` |

**Demo 1 exit criteria:** clean plan + A=2/B=1/C=1 running + 2 healthy TG targets + private only + namespace shown.

---

## Demo 2 — Walk the architecture (allow + deny)

**Path to narrate:**

```text
Client → ALB:80 → Service A:3001 → Service B:3002 → Service C:3003 → callback A:3001
```

For **each** hop: destination:port · route · SG · discovery name · log evidence · symptom if broken.

### 2.1 Allow — Internet → ALB → A

```bash
cd "$LAB_DIR"
export ALB="$(terraform output -raw alb_dns_name)"
SHA="$(terraform output -json deployed_image_tags | python3 -c 'import sys,json; print(json.load(sys.stdin)["a"])')"

echo "ALB=$ALB SHA=$SHA"

curl -sS -m 10 -w "\nHTTP %{http_code}\n" "http://$ALB/health?shallow=1"
curl -sS -m 10 -w "\nHTTP %{http_code}\n" "http://$ALB/version"
curl -sS -m 25 -w "\nHTTP %{http_code}\n" "http://$ALB/greet-service-b"
```

| Command | Exact expected shape | HTTP |
|---|---|---|
| `/health?shallow=1` | `{"service":"service-a","status":"ok","dependencies":{},"version":"<SHA>"}` | **200** |
| `/version` | `{"service":"service-a","version":"<SHA>","status":"ok"}` | **200** |
| `/greet-service-b` | `{"request_id":"<uuid>","status":"success","message":"Request completed successfully"}` | **200** |

| Pass if |
|---|
| `version` equals declared `image_tag_a` (`$SHA`) |
| Greet `status` is `success` with A desired=2 |

| If greet is `504` / `upstream request timeout` |
|---|
| Shallow health still 200 → classic A=2 callback scar (Demo 4). Do not invent SG fixes. Release sticky-callback SHA (Demo 3), then re-run this step. |

### 2.2 Allow — A → B by Service Connect name

```bash
TASK_A=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SVC_A" \
  --desired-status RUNNING --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster "$CLUSTER" --task "$TASK_A" \
  --container service-a --interactive \
  --command "curl -sS -m 5 -w '\nHTTP %{http_code}\n' http://service-b:3002/health?shallow=1"
```

| Expected |
|---|
| Session opens via SSM |
| Body includes `"service":"service-b","status":"ok"` |
| Trailing `HTTP 200` |
| Narrate SG: `service-a-sg` → `service-b-sg` :3002 |
| Narrate discovery: `service-b` in `group5-iac.internal` |

### 2.3 Allow — B → C by Service Connect name

```bash
TASK_B=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SVC_B" \
  --desired-status RUNNING --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster "$CLUSTER" --task "$TASK_B" \
  --container service-b --interactive \
  --command "curl -sS -m 5 -w '\nHTTP %{http_code}\n' http://service-c:3003/health?shallow=1"
```

| Expected |
|---|
| `"service":"service-c","status":"ok"` + `HTTP 200` |
| Narrate SG: `service-b-sg` → `service-c-sg` :3003 |

### 2.4 Deny — A → C direct

```bash
aws ecs execute-command --cluster "$CLUSTER" --task "$TASK_A" \
  --container service-a --interactive \
  --command "curl -sS -m 5 -w '\nHTTP %{http_code}\n' http://service-c:3003/health?shallow=1; echo EXIT:\$?"
```

| Expected |
|---|
| curl fails within ~5s (timeout / connection error) |
| **Not** HTTP 200 with `service-c` body |
| Narrate: no SG rule A→C; forward path is A→B→C only |

### 2.5 Deny — Internet → task private IP

```bash
TG=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
PRIV=$(aws elbv2 describe-target-health --target-group-arn "$TG" \
  --query 'TargetHealthDescriptions[0].Target.Id' --output text)
echo "PRIV=$PRIV"

curl -sS -m 5 -w "\nHTTP %{http_code}\n" "http://$PRIV:3001/health?shallow=1" || echo "DENIED_AS_EXPECTED exit=$?"
```

| Expected |
|---|
| Failure (timeout / no route / HTTP 000) |
| Pass: laptop cannot reach task `:3001` on private IP |

### 2.6 Log evidence (one greet)

Re-run greet once, then:

```bash
curl -sS -m 25 -H "X-Request-ID: demo-$(date +%s)" "http://$ALB/greet-service-b"; echo

aws logs tail /ecs/devops-g5-iac-service-a --since 5m --format short | tail -30
aws logs tail /ecs/devops-g5-iac-service-b --since 5m --format short | tail -20
aws logs tail /ecs/devops-g5-iac-service-c --since 5m --format short | tail -20
```

| Expected events |
|---|
| A: `request_received` path `/greet-service-b` |
| A: `request_forwarded` target `service-b` |
| B: `request_received` path `/greet` |
| C: `request_received` path `/greet-c` / callback |
| A: `callback_received` / greet completes |
| Same `request_id` visible across services |

### Hop cheat sheet (speak this)

| Hop | Dest:port | Route | SG | Discovery | Broken symptom |
|---|---|---|---|---|---|
| Client→ALB | `:80` | IGW → ALB | ALB SG `0.0.0.0/0:80` | ALB DNS | connection fail |
| ALB→A | `:3001` | VPC local | ALB→A SG | TG ip targets | 502 / unhealthy |
| A→B | `:3002` | VPC local | A→B | `service-b` | greet fail; shallow OK |
| B→C | `:3003` | VPC local | B→C | `service-c` | B/greet error |
| C→A callback | `:3001` | VPC local | C→A | sticky task IP / `service-a` | 504 timeout |

**Demo 2 exit criteria:** allow health+version+greet; Exec A→B and B→C 200; Exec A→C fail; internet→task IP fail; logs show the chain.

---

## Demo 3 — Release (IaC selects the SHA)

```text
App change → tests → pipeline Build pushes :SHA → set image_tag_* → plan → apply → prove /version → clean plan
```

Pipelines: `devops-g5-iac-pipeline-service-{a,b,c}`. Default: **Build/push only** (`enable_ecs_deploy = false`). ECS deploy is Terraform.

### 3.1 Confirm SHA image exists in IaC ECR

```bash
NEW_SHA=<paste-7+-char-git-sha>

for r in devops-g5-iac-service-a devops-g5-iac-service-b devops-g5-iac-service-c; do
  echo "== $r =="
  aws ecr describe-images --repository-name "$r" --image-ids imageTag="$NEW_SHA" \
    --query 'imageDetails[0].imageTags' --output text
done
```

| Expected |
|---|
| Each repo returns a tag list containing `$NEW_SHA` |
| Narrate: immutable tags; pipeline pushed; **IaC** will select deploy |

Optional pipeline stage proof:

```bash
aws codepipeline list-pipeline-executions \
  --pipeline-name devops-g5-iac-pipeline-service-a \
  --max-results 1 \
  --query 'pipelineExecutionSummaries[0].{status:status,id:pipelineExecutionId}' --output table
```

| Expected |
|---|
| Latest execution `Succeeded` (or show Build succeeded) |
| No Deploy stage (or Deploy disabled) selecting ECS |

### 3.2 Point Terraform at the new SHA

Edit `$LAB_DIR/terraform.tfvars`:

```hcl
image_tag_a = "<NEW_SHA>"
image_tag_b = "<NEW_SHA>"
image_tag_c = "<NEW_SHA>"
```

```bash
cd "$LAB_DIR"
terraform plan -out=release.tfplan
```

| Expected plan |
|---|
| New task definition revisions for A/B/C (image URI `:NEW_SHA`) |
| ECS services update to new task defs (rolling) |
| **No** VPC / subnet / ALB replace |
| Speak brief: replacements none; rolling deploy + circuit breaker |

```bash
terraform apply release.tfplan
terraform plan
```

| Expected |
|---|
| Services stabilize (A still 2/2) |
| Follow-up plan: **No changes** |

### 3.3 Prove new SHA through ALB

```bash
export ALB="$(terraform output -raw alb_dns_name)"
curl -sS -m 10 -w "\nHTTP %{http_code}\n" "http://$ALB/version"
curl -sS -m 10 -w "\nHTTP %{http_code}\n" "http://$ALB/health?shallow=1"
curl -sS -m 25 -w "\nHTTP %{http_code}\n" "http://$ALB/greet-service-b"
terraform output deployed_image_tags
```

| Expected |
|---|
| `/version` → `"version":"<NEW_SHA>"` HTTP 200 |
| Shallow health version matches |
| Greet HTTP 200 `"status":"success"` |
| `deployed_image_tags` all equal `<NEW_SHA>` |

### 3.4 One safe infra change

Example — tag-only in-place update (predict → plan → apply → prove):

```bash
# Edit: aws_security_group.service_b tags add DemoNote = "assignment1-demo"
terraform plan -out=safe.tfplan
```

| Expected |
|---|
| Exactly the intended SG (or chosen resource) **update in-place** |
| Narrate: in-place vs new task-def revision vs replace |
| No unexpected destroys |

```bash
terraform apply safe.tfplan
terraform plan
```

| Expected |
|---|
| Apply OK; follow-up plan clean |

**Demo 3 exit criteria:** ECR has SHA → tfvars updated → only task-def/service churn → ALB `/version` shows SHA → clean plan.

---

## Demo 4 — Golden scar (≤2 minutes)

Full write-up: [golden-scar.md](./golden-scar.md).

| Beat | Say / show |
|---|---|
| Symptom | `/health?shallow=1` → 200; `/greet-service-b` → **504** with A desired=2 |
| Belief | Service Connect incomplete or missing C→A SG |
| Evidence | Logs: C callback **200** on the **wrong** A task; originating A logs `downstream_timeout` |
| Disprove | SG worked; forward A→B→C worked; names resolved |
| Cause | in-memory `pendingCallbacks` + Service Connect load-balancing across A replicas |
| Fix | sticky `X-Callback-URL: http://<task-ip>:3001` through A→B→C |
| Prevention | `shared/callback.js` + tests + this scar + greet proof with A=2 |

Optional live proof of symptom (only if running **pre-fix** image):

```bash
curl -sS -m 25 -w "\nHTTP %{http_code}\n" "http://$ALB/greet-service-b"
# Expected (scar): HTTP 504 / upstream request timeout
```

After fixed SHA deployed (Demo 3):

```bash
curl -sS -m 25 -w "\nHTTP %{http_code}\n" "http://$ALB/greet-service-b"
# Expected (prevented): HTTP 200 {"status":"success",...}
```

**Demo 4 exit criteria:** coach hears cause ≠ “missing SG”; prevention is encoded in code/tests/docs.

---

## Demo 5 — Tear down + cost sweep

### 5.1 Review destroy plan

```bash
cd "$LAB_DIR"
terraform plan -destroy -out=destroy.tfplan
```

| Expected narration |
|---|
| **Removed:** VPC, NAT, ALB, ECS services/tasks/task defs, IaC SGs, Service Connect namespace, IaC ECR (if empty), pipelines/CodeBuild, IaC log groups, artifact bucket (as owned) |
| **Survive:** `devops-g5-iac-tfstate-827478161993`, `devops-g5-iac-tflock`, console `devops-g5-*`, default VPC |
| Confirm aloud: account `827478161993`, region `eu-west-1`, state key `lab/terraform.tfstate` |

### 5.2 Destroy

```bash
terraform apply destroy.tfplan
```

| Expected |
|---|
| Destroy completes |
| No deletes of console `devops-g5-*` (without `-iac`) |
| No delete of state bucket/lock from this apply |

### 5.3 Prove workload gone; backend remains

```bash
aws ecs describe-clusters --clusters "$CLUSTER" \
  --query '{status:clusters[0].status,failure:failures[0].reason}' --output table

aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName,'devops-g5-iac')].LoadBalancerName" --output text

aws ec2 describe-nat-gateways \
  --filter Name=tag:Name,Values=devops-g5-iac-nat \
  --query 'NatGateways[?State!=`deleted`].{id:NatGatewayId,state:State}' --output table

aws s3api head-bucket --bucket "$STATE_BUCKET"
aws dynamodb describe-table --table-name "$LOCK_TABLE" \
  --query 'Table.TableStatus' --output text
```

| Expected |
|---|
| Cluster `MISSING` or `INACTIVE` |
| No IaC ALB names printed |
| No active (`pending`/`available`) IaC NAT |
| `head-bucket` succeeds (HTTP 200) |
| Lock table status `ACTIVE` |

### 5.4 Cost sweep

```bash
aws ecs list-tasks --cluster "$CLUSTER" --output text 2>/dev/null || echo "cluster absent OK"

aws ec2 describe-nat-gateways \
  --filter Name=tag:Name,Values=devops-g5-iac-nat \
  --query 'length(NatGateways[?State==`available`])' --output text

aws elbv2 describe-load-balancers \
  --query "length(LoadBalancers[?contains(LoadBalancerName,'devops-g5-iac')])" --output text
```

| Expected |
|---|
| No running IaC tasks |
| NAT available count `0` |
| IaC ALB count `0` |
| Narrate: bootstrap destroy only with mentor approval |

**Demo 5 exit criteria:** workload gone; backend intact; cost drivers (NAT/ALB/Fargate) zero for `-iac`.

---

## Failure cheat sheet (during demo)

| Symptom | First check | Likely cause |
|---|---|---|
| Plan wants replace ALB/VPC | Stop; re-read plan | Accidental name/force-new change |
| TG unhealthy | `describe-target-health` + A logs | Bad image/tag, SG, or slow boot |
| Shallow 200, greet 504 | A desired count + callback logs | Golden scar (Demo 4) |
| Exec “TargetNotConnected” | task has Exec enabled + SSM plugin + task role | Wait for RUNNING; check plugin |
| Pipeline green, ECS old SHA | `terraform output deployed_image_tags` | Forgot tfvars + apply (by design) |
| Wrong stack touched | resource name has `-iac`? | Console lab uses `devops-g5-*` |

---

## Change brief templates

### Full (first create / destroy / networking / IAM / replace)

```text
Expected additions, changes and deletions:
Expected replacements:
User impact:
Security impact:
Cost impact:
Recovery approach:
Reason to proceed:
```

### Routine

```text
Expected delta:
Unexpected plan action:
Decision:
```

---

## Quick pass card (post each demo)

| Demo | Pass when |
|---|---|
| 1 Spin up | Clean plan; A2/B1/C1; 2 healthy targets; private only |
| 2 Architecture | Allow health/version/greet; Exec allow/deny; logs |
| 3 Release | SHA in ECR → tfvars → apply → `/version` matches → clean plan |
| 4 Scar | Cause articulated; prevention pointed at code/tests/docs |
| 5 Destroy | Workload gone; state+lock live; NAT/ALB/Fargate clear |
