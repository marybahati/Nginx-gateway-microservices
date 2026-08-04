# Live demonstration runbook — Assignment 1 (Group 5)

**Region:** `eu-west-1` only  
**Tool:** Terraform (pinned) + AWS provider `~> 5.80`  
**Workload prefix:** `devops-g5-iac-` (does **not** touch console `devops-g5-*`)  
**Namespace:** `group5-iac.internal`  
**State:** `devops-g5-iac-tfstate-*` + `devops-g5-iac-tflock` (survive destroy)  
**Working directory for lab commands:** `infra/environments/lab`

```text
Owner types. Team observes. Operator narrates. Coach asks questions. Evidence decides.
```

No one takes over another engineer’s terminal.

---

## Demo 1 — Spin up from zero

### 1.1 Account and Region

```bash
aws sts get-caller-identity
aws configure get region
```

| Expected |
|---|
| Account `827478161993` (or your group account) |
| Region output: `eu-west-1` |

### 1.2 Prove workload does not exist (start of demo / after prior destroy)

```bash
aws ecs describe-clusters --clusters devops-g5-iac-cluster --region eu-west-1 \
  --query 'clusters[0].{status:status,registered:registeredContainerInstancesCount}' --output table

aws elbv2 describe-load-balancers --region eu-west-1 \
  --query "LoadBalancers[?LoadBalancerName=='devops-g5-iac-alb'].LoadBalancerName" --output text
```

| Expected |
|---|
| Cluster status `INACTIVE` / empty / or error “cluster not found” style absence |
| ALB query returns **empty** (no `devops-g5-iac-alb`) |
| Narrate: console `devops-g5-*` may still exist — **do not touch it** |

### 1.3 Init, plan, narrate highest risk

```bash
cd infra/environments/lab
terraform init
terraform fmt -check
terraform validate
terraform plan -out=lab.tfplan
```

| Expected |
|---|
| `Terraform has been successfully initialized` (S3 backend + lock) |
| `Success! The configuration is valid.` |
| Plan shows **adds** for VPC/NAT/ALB/ECS/SGs/ECR/pipelines (first create) |
| **No** unexplained replacements; narrate NAT cost + ECS create risk |
| Operator reads full change brief before apply |

### 1.4 Apply (IaC only — no console create)

```bash
terraform apply lab.tfplan
terraform plan
terraform output
```

| Expected |
|---|
| Apply completes without console repairs |
| Follow-up `terraform plan`: **No changes** (or only known no-ops) |
| Outputs include `alb_dns_name`, `cluster_name`, `namespace` = `group5-iac.internal`, `pipelines` |

### 1.5 Tasks, ALB health, Service Connect, logs

```bash
aws ecs describe-services --region eu-west-1 --cluster devops-g5-iac-cluster \
  --services devops-g5-iac-svc-service-a devops-g5-iac-svc-service-b devops-g5-iac-svc-service-c \
  --query 'services[*].{name:serviceName,desired:desiredCount,running:runningCount,status:status}' \
  --output table

TG=$(aws elbv2 describe-target-groups --region eu-west-1 --names devops-g5-iac-tg-service-a \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
aws elbv2 describe-target-health --region eu-west-1 --target-group-arn "$TG" --output table

aws ecs list-tasks --region eu-west-1 --cluster devops-g5-iac-cluster \
  --service-name devops-g5-iac-svc-service-a --desired-status RUNNING --output text
# then describe those tasks for AZs / no public IP:
aws ecs describe-tasks --region eu-west-1 --cluster devops-g5-iac-cluster --tasks <task-id> \
  --query 'tasks[0].{az:availabilityZone,attachments:attachments}' --output json
```

| Expected |
|---|
| A desired/running **2**; B **1**; C **1**; status `ACTIVE` |
| Target group: **2 healthy** targets (private IPs, type ip) |
| Service A tasks in **eu-west-1a and eu-west-1b** |
| Task ENIs: **no public IP** |
| Namespace discussed: `group5-iac.internal`; discovery names `service-a/b/c` |
| Log groups exist: `/ecs/devops-g5-iac-service-{a,b,c}` |

```bash
aws logs describe-log-groups --region eu-west-1 \
  --log-group-name-prefix /ecs/devops-g5-iac-service --query 'logGroups[*].logGroupName' --output table
```

| Expected |
|---|
| Three log groups listed for a, b, c |

---

## Demo 2 — Walk the architecture (allow + deny)

Trace:

```text
Client → ALB:80 → A:3001 → B:3002 → C:3003 → callback A:3001
```

For each hop narrate: destination/port, route, SG, Service Connect name, log evidence, symptom if broken.

### 2.1 Internet → ALB → A (allow)

```bash
cd infra/environments/lab
ALB=$(terraform output -raw alb_dns_name)
echo "ALB=$ALB"

curl -sS -w "\nHTTP %{http_code}\n" "http://$ALB/health?shallow=1"
curl -sS -w "\nHTTP %{http_code}\n" "http://$ALB/greet-service-b"
curl -sS -w "\nHTTP %{http_code}\n" "http://$ALB/version"
```

| Command | Expected |
|---|---|
| shallow health | HTTP **200**; JSON `service":"service-a"`, `status":"ok"` |
| greet | HTTP **200**; `"status":"success"` (A→B→C→callback) |
| version | HTTP **200**; `version` = deployed Git SHA |

### 2.2 A → B by service name (allow)

Pick a running Service A task, then ECS Exec:

```bash
TASK_A=$(aws ecs list-tasks --region eu-west-1 --cluster devops-g5-iac-cluster \
  --service-name devops-g5-iac-svc-service-a --desired-status RUNNING \
  --query 'taskArns[0]' --output text)

aws ecs execute-command --region eu-west-1 --cluster devops-g5-iac-cluster \
  --task "$TASK_A" --container service-a --interactive \
  --command "curl -sS -m 5 -w '\nHTTP %{http_code}\n' http://service-b:3002/health?shallow=1"
```

| Expected |
|---|
| HTTP **200** from `service-b` |
| SG evidence: A SG → B SG :3002 |
| Discovery: `service-b` in `group5-iac.internal` |

### 2.3 B → C by service name (allow)

```bash
TASK_B=$(aws ecs list-tasks --region eu-west-1 --cluster devops-g5-iac-cluster \
  --service-name devops-g5-iac-svc-service-b --desired-status RUNNING \
  --query 'taskArns[0]' --output text)

aws ecs execute-command --region eu-west-1 --cluster devops-g5-iac-cluster \
  --task "$TASK_B" --container service-b --interactive \
  --command "curl -sS -m 5 -w '\nHTTP %{http_code}\n' http://service-c:3003/health?shallow=1"
```

| Expected |
|---|
| HTTP **200** from `service-c` |
| SG: B → C :3003 |

### 2.4 A → C direct (deny)

```bash
aws ecs execute-command --region eu-west-1 --cluster devops-g5-iac-cluster \
  --task "$TASK_A" --container service-a --interactive \
  --command "curl -sS -m 5 -w '\nHTTP %{http_code}\n' http://service-c:3003/health?shallow=1 || true"
```

| Expected |
|---|
| **Timeout / fail / non-200** (no SG allow A→C) |
| Narrate: forward path is A→B→C only |

### 2.5 Internet → task IP direct (deny)

```bash
# Get a private task IP from target health, then from your laptop:
curl -sS -m 5 -w "\nHTTP %{http_code}\n" "http://<task-private-ip>:3001/health?shallow=1" || true
```

| Expected |
|---|
| Fail / timeout (private IP, no public route from internet) |

### 2.6 Log evidence (same request id if possible)

```bash
aws logs tail /ecs/devops-g5-iac-service-a --region eu-west-1 --since 10m --format short | tail -20
aws logs tail /ecs/devops-g5-iac-service-b --region eu-west-1 --since 10m --format short | tail -20
aws logs tail /ecs/devops-g5-iac-service-c --region eu-west-1 --since 10m --format short | tail -20
```

| Expected |
|---|
| A: `/greet-service-b` received / forwarded |
| B: `/greet` received |
| C: `/greet-c` + callback |
| Same `request_id` across services when present |

### Hop cheat sheet

| Hop | Dest:port | Route | SG | Discovery | If broken |
|---|---|---|---|---|---|
| Client→ALB | `:80` | Internet→IGW→ALB | ALB SG 0.0.0.0/0:80 | ALB DNS | Connection fail |
| ALB→A | `:3001` | VPC local | ALB→A SG | TG ip targets | 502 / unhealthy |
| A→B | `:3002` | VPC local | A→B | `service-b` | Greet fail; A shallow OK |
| B→C | `:3003` | VPC local | B→C | `service-c` | B 500 |
| C→A callback | `:3001` | VPC local | C→A | sticky URL / `service-a` | 504 timeout |

---

## Demo 3 — Release (IaC selects SHA)

```text
App change → tests → pipeline build/push SHA → set image_tag_* → plan → apply → prove SHA → clean plan
```

### 3.1 Build/push SHA (pipeline)

After merge or branch build that triggers IaC pipelines:

```bash
# Example: confirm image exists for NEW_SHA (7-char)
NEW_SHA=<paste-7-char-sha>
aws ecr describe-images --region eu-west-1 --repository-name devops-g5-iac-service-a \
  --image-ids imageTag=$NEW_SHA --query 'imageDetails[0].imageTags' --output text
# repeat for service-b / service-c as needed
```

| Expected |
|---|
| Tag `$NEW_SHA` listed (immutable) |
| Pipeline stage **Build** succeeded; **no Deploy** (IaC owns deploy) |

### 3.2 Update declared SHA in IaC

Edit `terraform.tfvars` (local, not committed if secrets — SHA tags are fine):

```hcl
image_tag_a = "<NEW_SHA>"
image_tag_b = "<NEW_SHA>"
image_tag_c = "<NEW_SHA>"
```

```bash
terraform plan -out=release.tfplan
```

| Expected |
|---|
| Task definition **revisions** for A/B/C (image SHA change) |
| **No** unexplained VPC/ALB replacements |
| Narrate: rolling deploy + circuit breaker |

```bash
terraform apply release.tfplan
terraform plan
```

| Expected |
|---|
| Services stabilize; follow-up plan **clean** |

### 3.3 Prove new SHA through ALB

```bash
ALB=$(terraform output -raw alb_dns_name)
curl -sS "http://$ALB/version"
curl -sS "http://$ALB/health?shallow=1"
curl -sS "http://$ALB/greet-service-b"
```

| Expected |
|---|
| `version` field equals **NEW_SHA** |
| Greet still **200 success** |

### 3.4 One safe infra change

Example — Service B log retention or desired count (B owner):

```bash
# After editing the relevant module input / resource
terraform plan -out=safe.tfplan
# Narrate: in-place update vs new task-def revision vs replace
terraform apply safe.tfplan
terraform plan
```

| Expected |
|---|
| Only the intended resource changes |
| Follow-up plan clean |

---

## Demo 4 — Golden scar

Present [golden-scar.md](./golden-scar.md) (or your group’s chosen scar).

| Step | What to show |
|---|---|
| Symptom | greet 504 while shallow health 200 / A=2 |
| Belief | Service Connect / SG |
| Evidence | logs: callback on wrong A task |
| Cause | in-memory pendingCallbacks + Service Connect LB |
| Fix | sticky `X-Callback-URL` |
| Prevention | code + tests + this doc |

---

## Demo 5 — Tear down + cost sweep

### 5.1 Review destroy

```bash
cd infra/environments/lab
terraform plan -destroy -out=destroy.tfplan
```

| Expected in narration |
|---|
| **Removed:** VPC, NAT, ALB, ECS services/tasks, IaC ECR (if empty), pipelines, IaC log groups (as owned) |
| **Survive:** `devops-g5-iac-tfstate-*`, `devops-g5-iac-tflock`, console `devops-g5-*`, default VPC |
| Confirm account, `eu-west-1`, state key `lab/terraform.tfstate` |

### 5.2 Destroy

```bash
terraform apply destroy.tfplan
```

| Expected |
|---|
| Destroy completes; no console deletes of shared/console lab resources |

### 5.3 Prove gone + backend safe

```bash
aws ecs describe-clusters --clusters devops-g5-iac-cluster --region eu-west-1 \
  --query 'clusters[0].status' --output text

aws elbv2 describe-load-balancers --region eu-west-1 \
  --query "LoadBalancers[?contains(LoadBalancerName,'devops-g5-iac')].LoadBalancerName" --output text

aws ec2 describe-nat-gateways --region eu-west-1 \
  --filter Name=tag:Name,Values=devops-g5-iac-nat \
  --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text

aws s3api head-bucket --bucket devops-g5-iac-tfstate-827478161993
aws dynamodb describe-table --region eu-west-1 --table-name devops-g5-iac-tflock \
  --query 'Table.TableStatus' --output text
```

| Expected |
|---|
| Cluster gone/INACTIVE; no IaC ALB; no active IaC NAT |
| State bucket still reachable; lock table `ACTIVE` |

### 5.4 Cost sweep (quick)

```bash
# Spot-check: no running IaC Fargate tasks
aws ecs list-tasks --region eu-west-1 --cluster devops-g5-iac-cluster 2>/dev/null || echo "cluster absent OK"
```

| Expected |
|---|
| No leftover NAT/ALB/Fargate for `-iac` |
| Narrate: bootstrap not destroyed unless mentors approve |

---

## Change brief templates

### Full (first create / destroy / net / IAM / replace)

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
