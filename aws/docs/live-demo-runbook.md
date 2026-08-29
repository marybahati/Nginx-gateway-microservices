# Live demonstration runbook — Assignment 1 (Group 5)

**Region:** `eu-west-1` only  
**Tool:** Terraform (pinned) + AWS provider `~> 5.80`  
**Workload prefix:** `devops-g5-iac-` (does **not** touch console `devops-g5-*`)  
**Namespace:** `group5-iac.internal`  
**State backend:** `devops-g5-iac-tfstate-*` + `devops-g5-iac-tflock` (survive destroy)

**New account?** See [new-account-migration.md](./new-account-migration.md) and `scripts/new-account-bootstrap.sh`.

```text
Owner types. Team observes. Operator narrates. Coach asks questions. Evidence decides.
```

No one takes over another engineer’s terminal.

---

## Demo 1 — Spin up from zero

1. Show account/Region:
   ```bash
   aws sts get-caller-identity
   aws configure get region   # must be eu-west-1
   ```
2. Prove workload gone (after a prior destroy, or before first apply):
   ```bash
   aws ecs describe-clusters --clusters devops-g5-iac-cluster --region eu-west-1 \
     --query 'clusters[0].status' --output text
   # expected: MISSING or INACTIVE
   ```
3. Present plan (highest risk: VPC/NAT/ALB/ECS create; no console creates):
   ```bash
   cd infra/environments/lab
   terraform init
   terraform plan -out=lab.tfplan
   ```
4. Apply via IaC only: `terraform apply lab.tfplan`
5. Show outputs, tasks, ALB health, logs, Service Connect names:
   ```bash
   terraform output
   aws ecs list-services --cluster devops-g5-iac-cluster --region eu-west-1
   aws elbv2 describe-target-health --target-group-arn "$(aws elbv2 describe-target-groups --names devops-g5-iac-tg-service-a --query 'TargetGroups[0].TargetGroupArn' --output text)"
   ```
6. Follow-up plan must be clean: `terraform plan`

---

## Demo 2 — Walk the architecture

Trace one live request:

```text
Client → ALB:80 → Service A:3001 → Service B:3002 → Service C:3003 → callback A:3001
```

For each hop cover: destination/port, route, SG rule, discovery name, log evidence, symptom if broken.

Prove allow/deny:

| Path | Expected |
|---|---|
| Internet → ALB `/health?shallow=1` | Allow 200 |
| ALB → A (target health) | Allow healthy |
| A → B by name (Exec curl) | Allow |
| B → C by name (Exec curl) | Allow |
| Internet → task private IP | Deny |
| A → C direct (Exec curl) | Deny / timeout |

```bash
ALB=$(terraform output -raw alb_dns_name)
curl -sS "http://$ALB/health?shallow=1"
curl -sS "http://$ALB/greet-service-b"
```

---

## Demo 3 — Release (IaC selects SHA)

```text
App change → tests → build SHA image → push ECR → update image_tag_* in tfvars
→ terraform plan → review → apply → rolling deploy → SHA visible on ALB → clean plan
```

1. Change a visible string (e.g. version) on a branch; merge or build locally with Git SHA tag.
2. Pipeline `devops-g5-iac-pipeline-service-*` **builds/pushes** only (Deploy stage off by default).
3. Set `image_tag_a/b/c` to the new SHA in `terraform.tfvars`.
4. Explain plan (expect new task-definition revisions; no unexplained replacements).
5. Apply; show revision + rolling deployment events.
6. `curl http://$ALB/version` shows new SHA.
7. Safe infra change (example: log retention or desired count) → apply → clean follow-up plan.

---

## Demo 4 — Golden scar

Present [golden-scar.md](./golden-scar.md): A=2 + Service Connect LB broke in-memory callbacks; sticky `X-Callback-URL` prevention.

---

## Demo 5 — Tear down

```text
Expected deletions: devops-g5-iac-* VPC/NAT/ALB/ECS/ECR iac/pipelines/logs (as owned)
Survive: state bucket + lock; console devops-g5-*; default VPC
```

1. `terraform plan -destroy -out=destroy.tfplan` — review.
2. Confirm account, Region, state key `lab/terraform.tfstate`.
3. `terraform apply destroy.tfplan`
4. Prove VPC/ALB/tasks/NAT gone; backend remains.
5. Cost sweep: no leftover NAT/ALB/Fargate for `-iac`.

---

## Full change brief (first create / destroy / networking)

```text
Expected additions, changes and deletions:
Expected replacements:
User impact:
Security impact:
Cost impact:
Recovery approach:
Reason to proceed:
```

## Routine plan note

```text
Expected delta:
Unexpected plan action:
Decision:
```
