# New AWS account migration — Group 5

**Region:** `eu-west-1` only  
**Stack prefix:** `devops-g5-iac-`  
**Does not touch** the old console lab account resources.

## Checklist

| Step | Action | Evidence |
|------|--------|----------|
| 1 | Configure new credentials (`aws configure` or env vars) | `aws sts get-caller-identity` shows **new** account |
| 2 | Run bootstrap script | `scripts/new-account-bootstrap.sh` |
| 3 | Build/push first SHA images (or scale after GHA push) | ECR tags exist under `devops-g5-iac-service-*` |
| 4 | `terraform plan` → `apply` (observability + OIDC included) | Services A/B/C RUNNING; alarms created |
| 5 | Prove greet journey | `curl http://$ALB/greet-service-b` → 200 |
| 6 | Set GitHub Actions variable `AWS_GHA_DEPLOY_ROLE_ARN` | `terraform output -raw github_actions_role_arn` |
| 7 | Confirm SNS email (if `alert_email` set) | Inbox confirmation link |
| 8 | Run controlled failure drill | `scripts/reliability-incident-drill.sh` → fill `incident-timeline.md` |

## 1. Authenticate to the NEW account

Credentials were sent via DM. Pick one:

```bash
# Option A — access keys
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...   # if temporary
export AWS_REGION=eu-west-1

# Option B — aws configure
aws configure   # region MUST be eu-west-1

aws sts get-caller-identity
# Account must NOT be the old lab account (240462142849)
```

## 2. Bootstrap (automated)

```bash
export AWS_REGION=eu-west-1
./scripts/new-account-bootstrap.sh
```

Creates S3 state bucket, DynamoDB lock table, writes `infra/environments/lab/backend.hcl`, inits Terraform, and copies `terraform.tfvars` from the example if missing.

## 3. Terraform state lock reset

If `terraform apply` fails with **Error acquiring the state lock**:

```bash
cd infra/environments/lab
# Preferred — use the lock ID from the error message
terraform force-unlock <LOCK_ID>

# Last resort — only when no apply is running
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
aws dynamodb delete-item \
  --table-name devops-g5-iac-tflock \
  --key "{\"LockID\":{\"S\":\"devops-g5-iac-tfstate-${ACCOUNT}/lab/terraform.tfstate\"}}"
```

## 4. First image bootstrapping

Until GitHub Actions has pushed SHAs to the new account ECR:

```bash
# Option A — local push then apply with those SHAs
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=eu-west-1
PREFIX=devops-g5-iac
SHA=$(git rev-parse --short=7 HEAD)
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com

# Apply once with enable_ecs_tasks=false to create ECR + OIDC only, OR create repos via apply
# then for each service:
for svc in service-a service-b service-c; do
  docker build --platform linux/amd64 -f "services/${svc}/Dockerfile" \
    --build-arg SERVICE_VERSION="$SHA" \
    -t "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${PREFIX}-${svc}:${SHA}" .
  docker push "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${PREFIX}-${svc}:${SHA}"
done
```

Edit `terraform.tfvars`:

```hcl
image_tag_a     = "<sha>"
image_tag_b     = "<sha>"
image_tag_c     = "<sha>"
enable_ecs_tasks = true
alert_email     = "you@example.com"   # optional
```

```bash
cd infra/environments/lab
terraform plan -out=lab.tfplan
terraform apply lab.tfplan
```

## 5. Verify Services A, B, C

```bash
cd infra/environments/lab
ALB=$(terraform output -raw alb_dns_name)

curl -sS "http://$ALB/health?shallow=1"
curl -sS "http://$ALB/greet-service-b"
curl -sS "http://$ALB/version"

aws ecs describe-services --cluster devops-g5-iac-cluster \
  --services devops-g5-iac-svc-service-a devops-g5-iac-svc-service-b devops-g5-iac-svc-service-c \
  --region eu-west-1 \
  --query 'services[].{name:serviceName,running:runningCount,desired:desiredCount,status:status}'
```

## 6. GitHub Actions authentication

| Workflow | Purpose | AWS auth |
|----------|---------|----------|
| `container-ci-cd.yml` | Unit tests + Compose smoke + **OIDC build/push/deploy** | `vars.AWS_GHA_DEPLOY_ROLE_ARN` |
| `aws-reliability-smoke.yml` | Post-deploy greet journey probe | same role |

After first apply, set in GitHub **Settings → Secrets and variables → Actions → Variables**:

- `AWS_GHA_DEPLOY_ROLE_ARN` = `terraform output -raw github_actions_role_arn`

Deploy does not run until this variable is set (avoids deploying to a stale/old account ARN).

## 7. Reliability evidence

| Artifact | How to produce |
|----------|----------------|
| Dashboard + alarms | Created by `module.observability` on apply |
| Screenshots | Export from CloudWatch → `production-readiness/screenshots/` |
| Incident drill | `./scripts/reliability-incident-drill.sh` then fill `incident-timeline.md` |
| GO/NO-GO | Update timestamps in `GO-NO-GO.md` after drill |

See `production-readiness/` for the full pack.
