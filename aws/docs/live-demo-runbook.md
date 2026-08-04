# Live demonstration runbook — Assignment 1 (Group 5)

| Field | Value |
|---|---|
| Region | `eu-west-1` |
| Tool | Terraform (≥1.6) + AWS provider |
| Workload prefix | `devops-g5-iac-` |
| Do not touch | console lab `devops-g5-*` (no `-iac`) |
| Namespace | `group5-iac.internal` |
| State bucket | `devops-g5-iac-tfstate-827478161993` |
| Lock table | `devops-g5-iac-tflock` |
| State key | `lab/terraform.tfstate` |
| Account | `827478161993` |
| Lab dir | `infra/environments/lab` |

Every block below is self-contained. Commands use literal resource names (no `$TG_NAME` / `$CLUSTER` env vars required).

```bash
export AWS_DEFAULT_REGION=eu-west-1
export AWS_REGION=eu-west-1
```

---

## Preflight

### Tools

```bash
terraform version
aws --version
curl --version | head -1
session-manager-plugin --version
```

| Expected |
|---|
| Terraform ≥1.6 |
| aws CLI present |
| curl present |
| Session Manager plugin present (needed for ECS Exec) |

### Identity and Region

```bash
aws sts get-caller-identity --output table
aws configure get region
echo "$AWS_DEFAULT_REGION"
```

| Expected |
|---|
| `Account` = `827478161993` |
| Region = `eu-west-1` |

### tfvars

```bash
cd ~/Nginx-gateway-microservices/infra/environments/lab
# or: cd "$(git rev-parse --show-toplevel)/infra/environments/lab"
test -f terraform.tfvars && grep -E 'image_tag_[abc]' terraform.tfvars
```

| Expected |
|---|
| File exists |
| Three SHA tags (not `latest`) |

If missing:

```bash
cp terraform.tfvars.example terraform.tfvars
# set image_tag_a/b/c to SHAs that exist in ECR
```

### Bootstrap (only if state backend does not exist)

```bash
cd ~/Nginx-gateway-microservices/infra/bootstrap
terraform init
terraform apply
terraform output
```

| Expected |
|---|
| State bucket + DynamoDB lock created |
| Outputs include `state_bucket` and `lock_table` |
| No VPC / ALB / ECS created |

---

## Demo 1 — Spin up from zero

### 1.1 Prove workload is absent

```bash
aws ecs describe-clusters --clusters devops-g5-iac-cluster \
  --query '{status:clusters[0].status,failure:failures[0].reason}' --output table

aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?LoadBalancerName=='devops-g5-iac-alb'].LoadBalancerName" --output text
```

| Expected |
|---|
| Cluster `failure` = `MISSING`, or `status` = `INACTIVE` |
| ALB query returns empty |

### 1.2 Init and validate

```bash
cd ~/Nginx-gateway-microservices/infra/environments/lab
terraform init
terraform fmt -check
terraform validate
```

| Expected |
|---|
| `Terraform has been successfully initialized!` |
| `fmt -check` exit 0 |
| `Success! The configuration is valid.` |

### 1.3 Plan

```bash
terraform plan -out=lab.tfplan
```

| Expected (first create) |
|---|
| Create: VPC `10.5.0.0/16`, NAT, ALB, cluster, SGs, ECR×3, ECS A=2 B=1 C=1, CodeBuild×3, CodePipeline×3, artifact bucket, IAM |
| Replacements: none |

### 1.4 Apply and follow-up plan

```bash
terraform apply lab.tfplan
terraform plan
terraform output
```

| Expected |
|---|
| Apply completes |
| Follow-up plan: `No changes. Your infrastructure matches the configuration.` |
| Outputs match: |

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
```

### 1.5 Target health

```bash
TG=$(aws elbv2 describe-target-groups --names devops-g5-iac-tg-service-a \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
echo "TG=$TG"

aws elbv2 describe-target-health --target-group-arn "$TG" --output table
```

| Expected |
|---|
| `TG=` starts with `arn:aws:elasticloadbalancing:eu-west-1:…:targetgroup/devops-g5-iac-tg-service-a/…` |
| Two targets with private IPs (`10.5.10.x` / `10.5.11.x`) |
| Both `TargetHealth.State` = `healthy` |

### 1.6 Services, AZs, public IP, logs, namespace

```bash
aws ecs describe-services --cluster devops-g5-iac-cluster \
  --services devops-g5-iac-svc-service-a devops-g5-iac-svc-service-b devops-g5-iac-svc-service-c \
  --query 'services[*].{name:serviceName,desired:desiredCount,running:runningCount,status:status}' \
  --output table
```

| Expected |
|---|
| `devops-g5-iac-svc-service-a` desired 2 / running 2 / `ACTIVE` |
| `devops-g5-iac-svc-service-b` desired 1 / running 1 / `ACTIVE` |
| `devops-g5-iac-svc-service-c` desired 1 / running 1 / `ACTIVE` |

```bash
TASKS=$(aws ecs list-tasks --cluster devops-g5-iac-cluster \
  --service-name devops-g5-iac-svc-service-a \
  --desired-status RUNNING --query 'taskArns' --output text)

aws ecs describe-tasks --cluster devops-g5-iac-cluster --tasks $TASKS \
  --query 'tasks[*].{az:availabilityZone,last:lastStatus,ip:attachments[0].details[?name==`privateIPv4Address`].value|[0]}' \
  --output table

aws ecs describe-services --cluster devops-g5-iac-cluster \
  --services devops-g5-iac-svc-service-a \
  --query 'services[0].networkConfiguration.awsvpcConfiguration.assignPublicIp' --output text
```

| Expected |
|---|
| Tasks in two AZs (e.g. `eu-west-1a` and `eu-west-1b`) |
| Private IPs only |
| `assignPublicIp` = `DISABLED` |

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /ecs/devops-g5-iac-service \
  --query 'logGroups[*].logGroupName' --output table

cd ~/Nginx-gateway-microservices/infra/environments/lab
terraform output -raw namespace
```

| Expected |
|---|
| `/ecs/devops-g5-iac-service-a` |
| `/ecs/devops-g5-iac-service-b` |
| `/ecs/devops-g5-iac-service-c` |
| `group5-iac.internal` |

---

## Demo 2 — Walk the architecture (allow + deny)

```text
Client → ALB:80 → Service A:3001 → Service B:3002 → Service C:3003 → callback A:3001
```

### 2.1 Allow — Internet → ALB → A

```bash
cd ~/Nginx-gateway-microservices/infra/environments/lab
ALB=$(terraform output -raw alb_dns_name)
SHA=$(terraform output -json deployed_image_tags | python3 -c 'import sys,json; print(json.load(sys.stdin)["a"])')
echo "ALB=$ALB SHA=$SHA"

curl -sS -m 10 -w "\nHTTP %{http_code}\n" "http://$ALB/health?shallow=1"
curl -sS -m 10 -w "\nHTTP %{http_code}\n" "http://$ALB/version"
curl -sS -m 25 -w "\nHTTP %{http_code}\n" "http://$ALB/greet-service-b"
```

| Command | Expected body | HTTP |
|---|---|---|
| `/health?shallow=1` | `{"service":"service-a","status":"ok","dependencies":{},"version":"<SHA>"}` | 200 |
| `/version` | `{"service":"service-a","version":"<SHA>","status":"ok"}` | 200 |
| `/greet-service-b` | `{"request_id":"<uuid>","status":"success","message":"Request completed successfully"}` | 200 |

| Also expected |
|---|
| `version` equals `image_tag_a` (`$SHA`) |
| Greet succeeds with Service A desired count = 2 |

If greet returns 504 / `upstream request timeout`, see Demo 4, then Demo 3 (deploy sticky-callback SHA), then re-run this step.

### 2.2 Allow — A → B

```bash
TASK_A=$(aws ecs list-tasks --cluster devops-g5-iac-cluster \
  --service-name devops-g5-iac-svc-service-a \
  --desired-status RUNNING --query 'taskArns[0]' --output text)
echo "TASK_A=$TASK_A"

aws ecs execute-command --cluster devops-g5-iac-cluster --task "$TASK_A" \
  --container service-a --interactive \
  --command "curl -sS -m 5 -w '\nHTTP %{http_code}\n' http://service-b:3002/health?shallow=1"
```

| Expected |
|---|
| `TASK_A=` is a task ARN |
| Body includes `"service":"service-b","status":"ok"` |
| `HTTP 200` |

### 2.3 Allow — B → C

```bash
TASK_B=$(aws ecs list-tasks --cluster devops-g5-iac-cluster \
  --service-name devops-g5-iac-svc-service-b \
  --desired-status RUNNING --query 'taskArns[0]' --output text)
echo "TASK_B=$TASK_B"

aws ecs execute-command --cluster devops-g5-iac-cluster --task "$TASK_B" \
  --container service-b --interactive \
  --command "curl -sS -m 5 -w '\nHTTP %{http_code}\n' http://service-c:3003/health?shallow=1"
```

| Expected |
|---|
| `TASK_B=` is a task ARN |
| Body includes `"service":"service-c","status":"ok"` |
| `HTTP 200` |

### 2.4 Deny — A → C direct

```bash
TASK_A=$(aws ecs list-tasks --cluster devops-g5-iac-cluster \
  --service-name devops-g5-iac-svc-service-a \
  --desired-status RUNNING --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster devops-g5-iac-cluster --task "$TASK_A" \
  --container service-a --interactive \
  --command "curl -sS -m 5 -w '\nHTTP %{http_code}\n' http://service-c:3003/health?shallow=1; echo EXIT:\$?"
```

| Expected |
|---|
| Timeout or connection error within ~5s |
| Not HTTP 200 with a `service-c` body |

### 2.5 Deny — Internet → task private IP

```bash
TG=$(aws elbv2 describe-target-groups --names devops-g5-iac-tg-service-a \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
PRIV=$(aws elbv2 describe-target-health --target-group-arn "$TG" \
  --query 'TargetHealthDescriptions[0].Target.Id' --output text)
echo "TG=$TG"
echo "PRIV=$PRIV"

# Stop if lookup failed (empty name / empty IP is NOT a pass)
test -n "$TG" && test "$TG" != "None" || { echo "FAIL: target group ARN empty"; exit 1; }
test -n "$PRIV" && [[ "$PRIV" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "FAIL: PRIV is not an IP ($PRIV)"; exit 1; }

curl -sS -m 5 -w "\nHTTP %{http_code}\n" "http://$PRIV:3001/health?shallow=1" || echo "DENIED_AS_EXPECTED exit=$?"
```

| Expected |
|---|
| `PRIV=` is a real private IP (e.g. `10.5.10.x`) |
| Then: timeout / no route / HTTP 000 |
| Pass only after `PRIV` is a valid IP — empty `PRIV` is a setup failure |

### 2.6 Log evidence

```bash
cd ~/Nginx-gateway-microservices/infra/environments/lab
ALB=$(terraform output -raw alb_dns_name)

curl -sS -m 25 -H "X-Request-ID: demo-$(date +%s)" "http://$ALB/greet-service-b"; echo

aws logs tail /ecs/devops-g5-iac-service-a --since 5m --format short | tail -30
aws logs tail /ecs/devops-g5-iac-service-b --since 5m --format short | tail -20
aws logs tail /ecs/devops-g5-iac-service-c --since 5m --format short | tail -20
```

| Expected |
|---|
| A: `request_received` path `/greet-service-b` |
| A: `request_forwarded` target `service-b` |
| B: `request_received` path `/greet` |
| C: `request_received` path `/greet-c` / callback |
| A: callback received / greet completes |
| Same `request_id` across services |

### Hop reference

| Hop | Dest:port | Route | SG | Discovery | If broken |
|---|---|---|---|---|---|
| Client→ALB | `:80` | IGW → ALB | ALB SG `0.0.0.0/0:80` | ALB DNS | connection fail |
| ALB→A | `:3001` | VPC local | ALB→A SG | TG ip targets | 502 / unhealthy |
| A→B | `:3002` | VPC local | A→B | `service-b` | greet fail; shallow OK |
| B→C | `:3003` | VPC local | B→C | `service-c` | B/greet error |
| C→A callback | `:3001` | VPC local | C→A | sticky task IP / `service-a` | 504 timeout |

---

## Demo 3 — Release (IaC selects the SHA)

```text
App change → tests → pipeline Build pushes :SHA → set image_tag_* → plan → apply → prove /version → clean plan
```

Pipelines: `devops-g5-iac-pipeline-service-{a,b,c}` (Build/push only; ECS deploy via Terraform).

### 3.1 Confirm SHA in IaC ECR

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

```bash
aws codepipeline list-pipeline-executions \
  --pipeline-name devops-g5-iac-pipeline-service-a \
  --max-results 1 \
  --query 'pipelineExecutionSummaries[0].{status:status,id:pipelineExecutionId}' --output table
```

| Expected |
|---|
| Latest execution `Succeeded` |

### 3.2 Update tfvars and apply

Edit `infra/environments/lab/terraform.tfvars`:

```hcl
image_tag_a = "<NEW_SHA>"
image_tag_b = "<NEW_SHA>"
image_tag_c = "<NEW_SHA>"
```

```bash
cd ~/Nginx-gateway-microservices/infra/environments/lab
terraform plan -out=release.tfplan
```

| Expected |
|---|
| New task definition revisions for A/B/C (image `:NEW_SHA`) |
| ECS services update to new task defs |
| No VPC / subnet / ALB replace |

```bash
terraform apply release.tfplan
terraform plan
```

| Expected |
|---|
| Services stabilize (A 2/2, B 1/1, C 1/1) |
| Follow-up plan: `No changes` |

### 3.3 Prove new SHA through ALB

```bash
cd ~/Nginx-gateway-microservices/infra/environments/lab
ALB=$(terraform output -raw alb_dns_name)

curl -sS -m 10 -w "\nHTTP %{http_code}\n" "http://$ALB/version"
curl -sS -m 10 -w "\nHTTP %{http_code}\n" "http://$ALB/health?shallow=1"
curl -sS -m 25 -w "\nHTTP %{http_code}\n" "http://$ALB/greet-service-b"
terraform output deployed_image_tags
```

| Expected |
|---|
| `/version` → `"version":"<NEW_SHA>"` HTTP 200 |
| Shallow health `version` = `<NEW_SHA>` |
| Greet HTTP 200 `"status":"success"` |
| `deployed_image_tags` a/b/c all = `<NEW_SHA>` |

### 3.4 Safe infra change

```bash
# Edit: aws_security_group.service_b tags add DemoNote = "assignment1-demo"
cd ~/Nginx-gateway-microservices/infra/environments/lab
terraform plan -out=safe.tfplan
```

| Expected |
|---|
| In-place update of the intended SG only |
| No unexpected destroys |

```bash
terraform apply safe.tfplan
terraform plan
```

| Expected |
|---|
| Apply completes |
| Follow-up plan: `No changes` |

---

## Demo 4 — Golden scar

See [golden-scar.md](./golden-scar.md).

### Symptom (pre-fix image only)

```bash
cd ~/Nginx-gateway-microservices/infra/environments/lab
ALB=$(terraform output -raw alb_dns_name)

curl -sS -m 10 -w "\nHTTP %{http_code}\n" "http://$ALB/health?shallow=1"
curl -sS -m 25 -w "\nHTTP %{http_code}\n" "http://$ALB/greet-service-b"
```

| Expected (scar) |
|---|
| Health HTTP 200 `"status":"ok"` |
| Greet HTTP 504 / `upstream request timeout` |
| Service A desired count = 2 |

### Evidence

```bash
aws logs tail /ecs/devops-g5-iac-service-a --since 10m --format short | tail -40
aws logs tail /ecs/devops-g5-iac-service-c --since 10m --format short | tail -40
```

| Expected (scar) |
|---|
| C callback returns 200 on one A task |
| Originating A task logs `downstream_timeout` / `request_failed` |

### After fixed SHA deployed (Demo 3)

```bash
cd ~/Nginx-gateway-microservices/infra/environments/lab
ALB=$(terraform output -raw alb_dns_name)
curl -sS -m 25 -w "\nHTTP %{http_code}\n" "http://$ALB/greet-service-b"
```

| Expected (fixed) |
|---|
| HTTP 200 `{"request_id":"…","status":"success","message":"Request completed successfully"}` |

| Cause | Fix |
|---|---|
| In-memory `pendingCallbacks` + Service Connect LB across A replicas | Sticky `X-Callback-URL: http://<task-ip>:3001` via A→B→C (`shared/callback.js`) |

---

## Demo 5 — Tear down + cost sweep

### 5.1 Destroy plan

```bash
cd ~/Nginx-gateway-microservices/infra/environments/lab
terraform plan -destroy -out=destroy.tfplan
```

| Expected |
|---|
| Destroy: VPC, NAT, ALB, ECS, SGs, namespace, IaC ECR (if empty), pipelines/CodeBuild, IaC log groups, artifact bucket |
| Survive: `devops-g5-iac-tfstate-827478161993`, `devops-g5-iac-tflock`, console `devops-g5-*`, default VPC |

### 5.2 Destroy

```bash
terraform apply destroy.tfplan
```

| Expected |
|---|
| Destroy completes |
| Console `devops-g5-*` untouched |
| State bucket and lock table not deleted |

### 5.3 Prove gone; backend remains

```bash
aws ecs describe-clusters --clusters devops-g5-iac-cluster \
  --query '{status:clusters[0].status,failure:failures[0].reason}' --output table

aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName,'devops-g5-iac')].LoadBalancerName" --output text

aws ec2 describe-nat-gateways \
  --filter Name=tag:Name,Values=devops-g5-iac-nat \
  --query 'NatGateways[?State!=`deleted`].{id:NatGatewayId,state:State}' --output table

aws s3api head-bucket --bucket devops-g5-iac-tfstate-827478161993
aws dynamodb describe-table --table-name devops-g5-iac-tflock \
  --query 'Table.TableStatus' --output text
```

| Expected |
|---|
| Cluster `MISSING` or `INACTIVE` |
| No IaC ALB names |
| No active IaC NAT (`pending` / `available`) |
| `head-bucket` succeeds |
| Lock table `ACTIVE` |

### 5.4 Cost sweep

```bash
aws ecs list-tasks --cluster devops-g5-iac-cluster --output text 2>/dev/null || echo "cluster absent OK"

aws ec2 describe-nat-gateways \
  --filter Name=tag:Name,Values=devops-g5-iac-nat \
  --query 'length(NatGateways[?State==`available`])' --output text

aws elbv2 describe-load-balancers \
  --query "length(LoadBalancers[?contains(LoadBalancerName,'devops-g5-iac')])" --output text
```

| Expected |
|---|
| No running IaC tasks / cluster absent |
| NAT available count `0` |
| IaC ALB count `0` |

---

## Failure cheat sheet

| Symptom | Check | Likely cause |
|---|---|---|
| `Target group names cannot be empty` | Command used `$TG_NAME` unset | Use literal `devops-g5-iac-tg-service-a` |
| `PRIV=` empty then curl exit 3 | TG lookup failed | Fix TG name first; empty PRIV is not deny pass |
| Plan replaces ALB/VPC | Re-read plan; stop | Accidental force-new change |
| TG unhealthy | `describe-target-health` + A logs | Bad image/tag, SG, or slow boot |
| Health 200, greet 504 | A desired=2 + callback logs | Golden scar (Demo 4) |
| Exec `TargetNotConnected` | task RUNNING + SSM plugin + task role | Wait / fix plugin |
| Pipeline green, ECS old SHA | `terraform output deployed_image_tags` | tfvars + apply not done |
| Wrong stack | name has `-iac`? | Console lab is `devops-g5-*` |
