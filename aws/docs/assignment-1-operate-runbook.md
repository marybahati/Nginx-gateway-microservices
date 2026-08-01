# Assignment 1 Operate Runbook — Terraform stack `devops-g5-iac`

**Does not touch** console lab `devops-g5-*` (without `-iac`).

| | Console lab | This Terraform exercise |
|---|---|---|
| Prefix | `devops-g5-` | `devops-g5-iac-` |
| Namespace | `group5.internal` | `group5-iac.internal` |
| VPC | default `172.31.0.0/16` | `10.5.0.0/16` |
| Release | CodePipeline → console ECS | **GitHub → CodePipeline `devops-g5-iac-pipeline-service-*` → ECR `devops-g5-iac-service-*` → ECS `devops-g5-iac-svc-*`** |

**No manual `docker push` or hand-editing SHA for day-to-day releases.** Merge to `main` triggers the three IaC pipelines (same CodeConnections app as before).

```text
Predict → Plan → Review → Apply → Prove → Release → Destroy → Rebuild
```

---

## End-to-end release (GitHub connected)

```text
PR → merge main
  → CodeConnections webhook
  → devops-g5-iac-pipeline-service-{a,b,c}
  → CodeBuild (buildspecs/iac/service-generic.yml)
       IMAGE_TAG = git SHA (7 chars)
       push → devops-g5-iac-service-{a,b,c}:SHA
       imagedefinitions.json
  → ECS Deploy → devops-g5-iac-svc-service-{a,b,c}
```

Terraform creates the pipelines and ECS services once.  
`lifecycle.ignore_changes` on `task_definition` lets the pipeline own new SHA revisions.

First boot only: tasks start from an existing console-lab image SHA (`bootstrap_image_tag`, default `4289726`) so apply does not need a laptop docker build. The **next merge to main** (or “Release change” on the pipeline) switches them onto `devops-g5-iac-service-*` SHA tags.

Terraform creates B → C → A, then force-redeploys all three once (`terraform_data.service_connect_mesh_refresh`) so Service Connect injects the full peer set into each task’s `/etc/hosts`. Without that bounce, early A tasks only resolve `service-a` and greet fails with `fetch failed`.

---

## 1. Spin up (platform)

### Prerequisites

```bash
export PATH="/opt/homebrew/bin:$PATH"
terraform version   # >= 1.6
aws sts get-caller-identity
aws configure get region   # eu-west-1
```

### Full change brief — first create

```text
Expected additions: VPC 10.5.0.0/16, NAT, ALB, cluster, SGs, ECR iac×3,
  ECS A=2 B=1 C=1, CodeBuild×3, CodePipeline×3, artifact bucket, IAM
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
terraform init
terraform apply -auto-approve
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

Save `greet_url` / `alb_dns_name` and `pipelines`.

### Kick first GitHub-built images

`buildspecs/iac/service-generic.yml` and `infra/` must be on `main` (pipelines pull from GitHub, not your laptop).

```bash
# After push/merge to main — or to force a run without an app change:
aws codepipeline start-pipeline-execution --name devops-g5-iac-pipeline-service-a --region eu-west-1
aws codepipeline start-pipeline-execution --name devops-g5-iac-pipeline-service-b --region eu-west-1
aws codepipeline start-pipeline-execution --name devops-g5-iac-pipeline-service-c --region eu-west-1
```

Day-to-day: merge to `main` → WebhookV2 → all three IaC pipelines (SHA from `CODEBUILD_RESOLVED_SOURCE_VERSION`, no manual docker/tag).

---

## 2. Prove contracts

```bash
ALB=$(terraform -chdir=infra/environments/lab output -raw alb_dns_name)
curl -sS "http://$ALB/health?shallow=1"
curl -sS "http://$ALB/greet-service-b"
```

| Test | Expected |
|---|---|
| Internet → ALB | 200 |
| greet A→B→C→callback | 200 success |
| Exec A → `service-b:3002/health` | 200 |
| Exec B → `service-c:3003/health` | 200 |
| Exec A → `service-c:3003/health` | deny/timeout |
| Task public IP | none |
| Service A tasks | 2 AZs |
| Pipelines | `devops-g5-iac-pipeline-service-{a,b,c}` succeed on merge |

---

## 3. Release a new version (no manual SHA)

1. Change app (e.g. version string) on a branch → PR → merge `main`.  
2. Watch CodePipeline `devops-g5-iac-pipeline-service-*` (Source = WebhookV2).  
3. Confirm new 7-char SHA in ECR `devops-g5-iac-service-*`.  
4. Confirm ALB `/health` or `/version` shows that SHA.  
5. `terraform plan` in lab → **no unexpected task-def churn** (ignored).

Safe infra change example (desired count / tag): edit Terraform → plan → apply → clean follow-up plan.

---

## 4. Tear down

```text
Expected deletions: all devops-g5-iac-* workload (VPC, NAT, ALB, ECS, pipelines, iac ECR, …)
Survive: devops-g5-iac-tfstate-*, devops-g5-iac-tflock, console devops-g5-*, default VPC
```

```bash
cd infra/environments/lab
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan
# Cost sweep: no NAT/ALB/Fargate for -iac
# Backend remains until mentors approve:
# cd ../bootstrap && terraform destroy
```

---

## 5. Rebuild from clean checkout

```bash
git clone <repo> && cd <repo>
cd infra/bootstrap && terraform init && terraform apply -auto-approve
cd ../environments/lab && terraform init && terraform apply -auto-approve
# prove + merge to main for pipeline SHA refresh
```

Cycle 2: another engineer operates; coach asks questions only.

---

## 6. Safety

- Never commit state/credentials/plans  
- Never delete console `devops-g5-*` (no `-iac`) via this stack  
- Region `eu-west-1` only  
- Console = inspect only for Terraform-managed resources  
