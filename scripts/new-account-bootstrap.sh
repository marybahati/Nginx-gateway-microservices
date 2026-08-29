#!/usr/bin/env bash
# Bootstrap Terraform remote state in a NEW AWS account and prepare lab deploy.
# Region: eu-west-1 only. Run after configuring new account credentials (aws configure / env vars).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${AWS_REGION:-eu-west-1}"
PREFIX="${NAME_PREFIX:-devops-g5-iac}"

if [[ "$REGION" != "eu-west-1" ]]; then
  echo "Group 5 must use eu-west-1 (got $REGION)" >&2
  exit 1
fi

echo "==> Caller identity"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "Account: $ACCOUNT_ID  Region: $REGION"

echo "==> Bootstrap remote state (S3 + DynamoDB lock)"
cd "$ROOT/infra/bootstrap"
terraform init -input=false
terraform apply -input=false -auto-approve

BUCKET="$(terraform output -raw state_bucket)"
LOCK_TABLE="$(terraform output -raw lock_table)"

BACKEND_HCL="$ROOT/infra/environments/lab/backend.hcl"
cat >"$BACKEND_HCL" <<EOF
bucket         = "$BUCKET"
key            = "lab/terraform.tfstate"
region         = "$REGION"
dynamodb_table = "$LOCK_TABLE"
encrypt        = true
EOF
echo "Wrote $BACKEND_HCL"

echo "==> Init workload backend"
cd "$ROOT/infra/environments/lab"
terraform init -backend-config=backend.hcl -reconfigure -input=false

TFVARS="$ROOT/infra/environments/lab/terraform.tfvars"
if [[ ! -f "$TFVARS" ]]; then
  cp terraform.tfvars.example "$TFVARS"
  echo "Created $TFVARS — set github_connection_arn before apply."
fi

cat <<EOF

Next steps:
1. Developer Tools → Connections: create GitHub connection; set github_connection_arn in terraform.tfvars
2. First boot only: build/push images or set use_console_bootstrap_ecr=true with valid SHAs
3. terraform plan -out=lab.tfplan && terraform apply lab.tfplan
4. Prove: curl http://\$(terraform output -raw alb_dns_name)/greet-service-b
5. GitHub repo variable AWS_ROLE_ARN = \$(terraform output -raw github_actions_role_arn)

To clear a stale state lock:
  terraform force-unlock <LOCK_ID>
  # or delete DynamoDB item LockID=$BUCKET/lab/terraform.tfstate
EOF
