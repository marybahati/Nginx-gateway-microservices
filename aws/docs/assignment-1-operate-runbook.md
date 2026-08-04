# Assignment 1 Operate Runbook — Terraform stack `devops-g5-iac`

**Does not touch** console lab `devops-g5-*` (without `-iac`).

| | Console lab | This IaC exercise |
|---|---|---|
| Prefix | `devops-g5-` | `devops-g5-iac-` |
| Namespace | `group5.internal` | `group5-iac.internal` |
| VPC | default `172.31.0.0/16` | `10.5.0.0/16` |
| Release | CodePipeline → console ECS | **Pipeline builds/pushes SHA → IaC `image_tag_*` → terraform apply** |

```text
Predict → Plan → Review → Apply → Prove → Release → Destroy → Rebuild
```

---

## Release contract (Assignment 1)

```text
Application change
→ tests
→ build SHA-tagged image (CodePipeline Build stage)
→ push to ECR devops-g5-iac-service-*
→ update image_tag_a / image_tag_b / image_tag_c in terraform.tfvars
→ terraform plan → review → apply
→ ECS rolling deployment
→ new SHA visible through ALB /version
→ clean follow-up plan
```

Pipelines **do not** Deploy to ECS by default (`enable_ecs_deploy = false`). IaC selects the deployed SHA.

First boot: set `use_console_bootstrap_ecr = true` only if IaC ECR lacks the declared tag; otherwise pull from `devops-g5-iac-service-*`.

Terraform creates B → C → A, then force-redeploys once (`terraform_data.service_connect_mesh_refresh`) so Service Connect injects the full peer set. See [golden-scar.md](./golden-scar.md) for the A=2 callback fix (`X-Callback-URL`).

---

## 1. Spin up (platform)

### Prerequisites

```bash
terraform version          # >= 1.6
aws sts get-caller-identity
aws configure get region   # eu-west-1
cp infra/environments/lab/terraform.tfvars.example infra/environments/lab/terraform.tfvars
# edit image_tag_* as needed
```

### Full change brief — first create

```text
Expected additions: VPC 10.5.0.0/16, NAT, ALB, cluster, SGs, ECR iac×3,
  ECS A=2 B=1 C=1, CodeBuild×3, CodePipeline×3 (build/push), artifact bucket, IAM
Expected replacements: none
User impact: new ALB DNS (iac); console lab unchanged
Security impact: private tasks, SG refs, no public IPs
Cost impact: NAT + ALB + Fargate — destroy after demos
Must survive destroy: state bucket/lock; console devops-g5-*; default VPC
Reason: Assignment 1 greenfield
```

### Bootstrap state (once)

```bash
cd infra/bootstrap
terraform init && terraform apply
terraform output
```

### Workload apply

```bash
cd ../environments/lab
terraform init
terraform plan -out=lab.tfplan
terraform apply lab.tfplan
terraform plan    # follow-up must be clean
terraform output
```

### Architecture tests

```bash
cd infra/modules/ecs-service && terraform test
cd infra/modules/alb && terraform test
```

---

## 2. Prove contracts

```bash
ALB=$(terraform -chdir=infra/environments/lab output -raw alb_dns_name)
curl -sS "http://$ALB/health?shallow=1"
curl -sS "http://$ALB/greet-service-b"
curl -sS "http://$ALB/version"
```

| Test | Expected |
|---|---|
| Internet → ALB | 200 |
| greet A→B→C→callback with A=2 | 200 success |
| Exec A → `service-b:3002/health` | 200 |
| Exec B → `service-c:3003/health` | 200 |
| Exec A → `service-c:3003/health` | deny/timeout |
| Task public IP | none |
| Service A tasks | 2 AZs |
| Deployed SHA | matches `image_tag_*` |

---

## 3. Release a new version

1. App change + tests → merge/build → pipeline pushes `:SHA` to IaC ECR.  
2. Set `image_tag_a` (and b/c if needed) in `terraform.tfvars`.  
3. `terraform plan` — expect new task-definition revisions.  
4. `terraform apply` — rolling deploy.  
5. Prove SHA via ALB.  
6. One safe infra change (desired count / log retention / tag) → clean plan.

---

## 4. Tear down

```text
Expected deletions: all devops-g5-iac-* workload
Survive: devops-g5-iac-tfstate-*, devops-g5-iac-tflock, console devops-g5-*, default VPC
```

```bash
cd infra/environments/lab
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan
# Cost sweep: no NAT/ALB/Fargate for -iac
# Backend remains until mentors approve bootstrap destroy
```

---

## 5. Rebuild from clean checkout

```bash
git clone <repo> && cd <repo>
cp infra/environments/lab/terraform.tfvars.example infra/environments/lab/terraform.tfvars
cd infra/bootstrap && terraform init && terraform apply
cd ../environments/lab && terraform init && terraform apply
# prove contracts; release via image_tag_* update
```

Cycle 2: another engineer operates; coach asks questions only.

---

## 6. Safety

- Never commit state/credentials/plans/`terraform.tfvars` with secrets  
- Never delete console `devops-g5-*` (no `-iac`) via this stack  
- Region `eu-west-1` only  
- Console = inspect only for IaC-managed resources  

See also: [live-demo-runbook.md](./live-demo-runbook.md), [golden-scar.md](./golden-scar.md), [cycle-records.md](./cycle-records.md), [gate-1-design-before-creation.md](./gate-1-design-before-creation.md).
