terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  backend "s3" {
    bucket         = "devops-g5-iac-tfstate-240462142849"
    key            = "lab/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "devops-g5-iac-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "devops-mentorship"
      Group       = "group-5"
      Environment = "lab"
      ManagedBy   = "terraform"
      Stack       = "devops-g5-iac-lab"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
  validation {
    condition     = var.aws_region == "eu-west-1"
    error_message = "Unapproved Region. Group 5 must use eu-west-1."
  }
}

variable "name_prefix" {
  type    = string
  default = "devops-g5-iac"
}

# Declared immutable image SHAs selected by IaC (Assignment 1 release contract).
# Pipeline builds/pushes SHA tags to devops-g5-iac-service-*; operators update these and apply.
variable "image_tag_a" {
  type    = string
  default = "5f9cf79"
  validation {
    condition     = var.image_tag_a != "latest" && can(regex("^[0-9a-f]{7,40}$", var.image_tag_a))
    error_message = "image_tag_a must be a Git SHA, not latest."
  }
}

variable "image_tag_b" {
  type    = string
  default = "5f9cf79"
  validation {
    condition     = var.image_tag_b != "latest" && can(regex("^[0-9a-f]{7,40}$", var.image_tag_b))
    error_message = "image_tag_b must be a Git SHA, not latest."
  }
}

variable "image_tag_c" {
  type    = string
  default = "5f9cf79"
  validation {
    condition     = var.image_tag_c != "latest" && can(regex("^[0-9a-f]{7,40}$", var.image_tag_c))
    error_message = "image_tag_c must be a Git SHA, not latest."
  }
}

# First boot may pull from console-lab ECR until IaC repos have the declared SHA.
variable "use_console_bootstrap_ecr" {
  type        = bool
  default     = false
  description = "When true, pull images from devops-g5-service-* (console lab). When false, use devops-g5-iac-service-*."
}

# Optional legacy CodePipeline path. New-account default: GitHub Actions OIDC deploy.
variable "enable_codepipeline" {
  type    = bool
  default = false
}

variable "github_connection_arn" {
  type    = string
  default = ""
}

variable "github_full_repository_id" {
  type    = string
  default = "marybahati/Nginx-gateway-microservices"
}

variable "github_branch" {
  type    = string
  default = "main"
}

# When false, ECS desired counts are 0 so CI can push the first SHA images before scale-up.
variable "enable_ecs_tasks" {
  type    = bool
  default = true
}

data "aws_caller_identity" "current" {}

locals {
  azs     = ["eu-west-1a", "eu-west-1b"]
  account = data.aws_caller_identity.current.account_id
  console_ecr = {
    a = "${local.account}.dkr.ecr.${var.aws_region}.amazonaws.com/devops-g5-service-a"
    b = "${local.account}.dkr.ecr.${var.aws_region}.amazonaws.com/devops-g5-service-b"
    c = "${local.account}.dkr.ecr.${var.aws_region}.amazonaws.com/devops-g5-service-c"
  }
  iac_ecr = {
    a = "${local.account}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.name_prefix}-service-a"
    b = "${local.account}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.name_prefix}-service-b"
    c = "${local.account}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.name_prefix}-service-c"
  }
  service_ecr = var.use_console_bootstrap_ecr ? local.console_ecr : local.iac_ecr
  common_tags = {
    Project     = "devops-mentorship"
    Group       = "group-5"
    Environment = "lab"
    ManagedBy   = "terraform"
    Stack       = "devops-g5-iac"
  }
}

module "network" {
  source = "../../modules/network"

  name_prefix          = var.name_prefix
  vpc_cidr             = "10.5.0.0/16"
  azs                  = local.azs
  public_subnet_cidrs  = ["10.5.0.0/24", "10.5.1.0/24"]
  private_subnet_cidrs = ["10.5.10.0/24", "10.5.11.0/24"]
  tags                 = local.common_tags
}

# --- Security groups (SG references only) ---

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "IaC ALB SG - internet port 80"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name  = "${var.name_prefix}-alb-sg"
    Owner = "platform-owner"
  })
}

resource "aws_security_group" "service_a" {
  name        = "${var.name_prefix}-service-a-sg"
  description = "IaC service-a - ALB and callback from C"
  vpc_id      = module.network.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name  = "${var.name_prefix}-service-a-sg"
    Owner = "service-a-owner"
  })
}

resource "aws_security_group" "service_b" {
  name        = "${var.name_prefix}-service-b-sg"
  description = "IaC service-b - from A only"
  vpc_id      = module.network.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name  = "${var.name_prefix}-service-b-sg"
    Owner = "service-b-owner"
  })
}

resource "aws_security_group" "service_c" {
  name        = "${var.name_prefix}-service-c-sg"
  description = "IaC service-c - from B only"
  vpc_id      = module.network.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name  = "${var.name_prefix}-service-c-sg"
    Owner = "service-c-owner"
  })
}

resource "aws_security_group_rule" "alb_to_a" {
  type                     = "ingress"
  from_port                = 3001
  to_port                  = 3001
  protocol                 = "tcp"
  security_group_id        = aws_security_group.service_a.id
  source_security_group_id = aws_security_group.alb.id
  description              = "ALB to service-a"
}

resource "aws_security_group_rule" "a_to_b" {
  type                     = "ingress"
  from_port                = 3002
  to_port                  = 3002
  protocol                 = "tcp"
  security_group_id        = aws_security_group.service_b.id
  source_security_group_id = aws_security_group.service_a.id
  description              = "service-a to service-b"
}

resource "aws_security_group_rule" "b_to_c" {
  type                     = "ingress"
  from_port                = 3003
  to_port                  = 3003
  protocol                 = "tcp"
  security_group_id        = aws_security_group.service_c.id
  source_security_group_id = aws_security_group.service_b.id
  description              = "service-b to service-c"
}

resource "aws_security_group_rule" "c_to_a_callback" {
  type                     = "ingress"
  from_port                = 3001
  to_port                  = 3001
  protocol                 = "tcp"
  security_group_id        = aws_security_group.service_a.id
  source_security_group_id = aws_security_group.service_c.id
  description              = "service-c callback to service-a"
}

# --- ECR for pipeline SHA pushes (IaC stack) ---

resource "aws_ecr_repository" "services" {
  for_each = toset(["service-a", "service-b", "service-c"])

  name                 = "${var.name_prefix}-${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name  = "${var.name_prefix}-${each.key}"
    Owner = "service-${trimprefix(each.key, "service-")}-owner"
  })
}

module "ecs_platform" {
  source = "../../modules/ecs-platform"

  name_prefix    = var.name_prefix
  namespace_name = "group5-iac.internal"
  tags           = local.common_tags
}

module "alb" {
  source = "../../modules/alb"

  name_prefix           = var.name_prefix
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = aws_security_group.alb.id
  tags                  = local.common_tags
}

# First boot: pull console-lab SHA images. Ongoing releases: GitHub pipelines → iac ECR → ECS.
# Create B/C before A so Service Connect injects peer names into /etc/hosts on first A tasks.
# After all three exist, terraform_data force-redeploys so every task sees the full mesh
# (C needs A for callback; A needs B/C for the greet chain).
module "service_b" {
  source = "../../modules/ecs-service"

  name_prefix        = var.name_prefix
  service_key        = "b"
  container_name     = "service-b"
  container_port     = 3002
  image_tag          = var.image_tag_b
  ecr_repository_url = local.service_ecr.b
  cluster_arn        = module.ecs_platform.cluster_arn
  cluster_name       = module.ecs_platform.cluster_name
  namespace_arn      = module.ecs_platform.namespace_arn
  private_subnet_ids = module.network.private_subnet_ids
  security_group_ids = [aws_security_group.service_b.id]
  execution_role_arn = module.ecs_platform.execution_role_arn
  task_role_arn      = module.ecs_platform.task_role_arn
  aws_region         = var.aws_region
  desired_count      = var.enable_ecs_tasks ? 1 : 0
  assign_public_ip   = false
  owner_tag          = "service-b-owner"
  environment = {
    SERVICE_C_URL        = "http://service-c:3003"
    SERVICE_C_HEALTH_URL = "http://service-c:3003/health"
  }
  tags = local.common_tags
}

module "service_c" {
  source = "../../modules/ecs-service"

  name_prefix        = var.name_prefix
  service_key        = "c"
  container_name     = "service-c"
  container_port     = 3003
  image_tag          = var.image_tag_c
  ecr_repository_url = local.service_ecr.c
  cluster_arn        = module.ecs_platform.cluster_arn
  cluster_name       = module.ecs_platform.cluster_name
  namespace_arn      = module.ecs_platform.namespace_arn
  private_subnet_ids = module.network.private_subnet_ids
  security_group_ids = [aws_security_group.service_c.id]
  execution_role_arn = module.ecs_platform.execution_role_arn
  task_role_arn      = module.ecs_platform.task_role_arn
  aws_region         = var.aws_region
  desired_count      = var.enable_ecs_tasks ? 1 : 0
  assign_public_ip   = false
  owner_tag          = "service-c-owner"
  environment = {
    SERVICE_A_CALLBACK_URL = "http://service-a:3001"
    SERVICE_A_HEALTH_URL   = "http://service-a:3001/health"
  }
  tags = local.common_tags

  depends_on = [module.service_b]
}

module "service_a" {
  source = "../../modules/ecs-service"

  name_prefix          = var.name_prefix
  service_key          = "a"
  container_name       = "service-a"
  container_port       = 3001
  image_tag            = var.image_tag_a
  ecr_repository_url   = local.service_ecr.a
  cluster_arn          = module.ecs_platform.cluster_arn
  cluster_name         = module.ecs_platform.cluster_name
  namespace_arn        = module.ecs_platform.namespace_arn
  private_subnet_ids   = module.network.private_subnet_ids
  security_group_ids   = [aws_security_group.service_a.id]
  execution_role_arn   = module.ecs_platform.execution_role_arn
  task_role_arn        = module.ecs_platform.task_role_arn
  aws_region           = var.aws_region
  desired_count        = var.enable_ecs_tasks ? 2 : 0
  assign_public_ip     = false
  enable_load_balancer = true
  target_group_arn     = module.alb.target_group_arn
  owner_tag            = "service-a-owner"
  environment = {
    SERVICE_B_URL        = "http://service-b:3002"
    SERVICE_B_HEALTH_URL = "http://service-b:3002/health"
  }
  tags = local.common_tags

  depends_on = [module.service_b, module.service_c]
}

# Service Connect freezes peer /etc/hosts at task start. Bounce once after the mesh exists.
resource "terraform_data" "service_connect_mesh_refresh" {
  depends_on = [module.service_a, module.service_b, module.service_c]

  input = join(",", [
    module.ecs_platform.cluster_name,
    module.service_a.service_name,
    module.service_b.service_name,
    module.service_c.service_name,
  ])

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      CLUSTER='${module.ecs_platform.cluster_name}'
      REGION='${var.aws_region}'
      for svc in '${module.service_a.service_name}' '${module.service_b.service_name}' '${module.service_c.service_name}'; do
        aws ecs update-service --region "$REGION" --cluster "$CLUSTER" --service "$svc" --force-new-deployment >/dev/null
        echo "Service Connect mesh refresh: forced deployment for $svc"
      done
    EOT
  }
}

# --- GitHub Actions OIDC (primary CI/CD for new account) ---

module "github_oidc" {
  source = "../../modules/github-oidc"

  name_prefix             = var.name_prefix
  github_org_repo         = var.github_full_repository_id
  aws_region              = var.aws_region
  ecr_repository_arns     = [for r in aws_ecr_repository.services : r.arn]
  ecs_cluster_arn         = module.ecs_platform.cluster_arn
  ecs_execution_role_arn  = module.ecs_platform.execution_role_arn
  ecs_task_role_arn       = module.ecs_platform.task_role_arn
  tags                    = local.common_tags
}

# --- Optional CI/CD: CodeConnections → CodePipeline (disabled unless enable_codepipeline) ---

resource "aws_s3_bucket" "pipeline_artifacts" {
  count  = var.enable_codepipeline ? 1 : 0
  bucket = "${var.name_prefix}-pipeline-artifacts-${local.account}"
  tags = merge(local.common_tags, {
    Name  = "${var.name_prefix}-pipeline-artifacts"
    Owner = "platform-owner"
  })
}

resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  count                   = var.enable_codepipeline ? 1 : 0
  bucket                  = aws_s3_bucket.pipeline_artifacts[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  count  = var.enable_codepipeline ? 1 : 0
  bucket = aws_s3_bucket.pipeline_artifacts[0].id
  versioning_configuration { status = "Enabled" }
}

data "aws_iam_policy_document" "codebuild_assume" {
  count = var.enable_codepipeline ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  count              = var.enable_codepipeline ? 1 : 0
  name               = "${var.name_prefix}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume[0].json
  tags               = merge(local.common_tags, { Name = "${var.name_prefix}-codebuild-role", Owner = "platform-owner" })
}

resource "aws_iam_role_policy" "codebuild" {
  count = var.enable_codepipeline ? 1 : 0
  name  = "${var.name_prefix}-codebuild"
  role  = aws_iam_role.codebuild[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.pipeline_artifacts[0].arn,
          "${aws_s3_bucket.pipeline_artifacts[0].arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr-public:GetAuthorizationToken",
          "sts:GetServiceBearerToken"
        ]
        Resource = "*"
      }
    ]
  })
}

data "aws_iam_policy_document" "codepipeline_assume" {
  count = var.enable_codepipeline ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  count              = var.enable_codepipeline ? 1 : 0
  name               = "${var.name_prefix}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume[0].json
  tags               = merge(local.common_tags, { Name = "${var.name_prefix}-codepipeline-role", Owner = "platform-owner" })
}

resource "aws_iam_role_policy" "codepipeline" {
  count = var.enable_codepipeline ? 1 : 0
  name  = "${var.name_prefix}-codepipeline"
  role  = aws_iam_role.codepipeline[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketVersioning", "s3:ListBucket"]
        Resource = [aws_s3_bucket.pipeline_artifacts[0].arn, "${aws_s3_bucket.pipeline_artifacts[0].arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
        Resource = var.github_connection_arn
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService",
          "ecs:TagResource"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "*"
        Condition = {
          StringEqualsIfExists = {
            "iam:PassedToService" = ["ecs-tasks.amazonaws.com"]
          }
        }
      }
    ]
  })
}

module "pipeline_a" {
  count  = var.enable_codepipeline ? 1 : 0
  source = "../../modules/cicd-service"

  name_prefix               = var.name_prefix
  service_key               = "a"
  container_name            = "service-a"
  ecr_repository_name       = aws_ecr_repository.services["service-a"].name
  ecs_cluster_name          = module.ecs_platform.cluster_name
  ecs_service_name          = module.service_a.service_name
  buildspec_path            = "buildspecs/iac/service-generic.yml"
  connection_arn            = var.github_connection_arn
  github_full_repository_id = var.github_full_repository_id
  github_branch             = var.github_branch
  artifact_bucket           = aws_s3_bucket.pipeline_artifacts[0].bucket
  codebuild_role_arn        = aws_iam_role.codebuild[0].arn
  codepipeline_role_arn     = aws_iam_role.codepipeline[0].arn
  watched_paths             = ["services/service-a/**", "shared/**"]
  owner_tag                 = "service-a-owner"
  tags                      = local.common_tags
}

module "pipeline_b" {
  count  = var.enable_codepipeline ? 1 : 0
  source = "../../modules/cicd-service"

  name_prefix               = var.name_prefix
  service_key               = "b"
  container_name            = "service-b"
  ecr_repository_name       = aws_ecr_repository.services["service-b"].name
  ecs_cluster_name          = module.ecs_platform.cluster_name
  ecs_service_name          = module.service_b.service_name
  buildspec_path            = "buildspecs/iac/service-generic.yml"
  connection_arn            = var.github_connection_arn
  github_full_repository_id = var.github_full_repository_id
  github_branch             = var.github_branch
  artifact_bucket           = aws_s3_bucket.pipeline_artifacts[0].bucket
  codebuild_role_arn        = aws_iam_role.codebuild[0].arn
  codepipeline_role_arn     = aws_iam_role.codepipeline[0].arn
  watched_paths             = ["services/service-b/**", "shared/**"]
  owner_tag                 = "service-b-owner"
  tags                      = local.common_tags
}

module "pipeline_c" {
  count  = var.enable_codepipeline ? 1 : 0
  source = "../../modules/cicd-service"

  name_prefix               = var.name_prefix
  service_key               = "c"
  container_name            = "service-c"
  ecr_repository_name       = aws_ecr_repository.services["service-c"].name
  ecs_cluster_name          = module.ecs_platform.cluster_name
  ecs_service_name          = module.service_c.service_name
  buildspec_path            = "buildspecs/iac/service-generic.yml"
  connection_arn            = var.github_connection_arn
  github_full_repository_id = var.github_full_repository_id
  github_branch             = var.github_branch
  artifact_bucket           = aws_s3_bucket.pipeline_artifacts[0].bucket
  codebuild_role_arn        = aws_iam_role.codebuild[0].arn
  codepipeline_role_arn     = aws_iam_role.codepipeline[0].arn
  watched_paths             = ["services/service-c/**", "shared/**"]
  owner_tag                 = "service-c-owner"
  tags                      = local.common_tags
}

# --- Architecture checks (≥6 Assignment 1 rules as code) ---

check "alb_spans_two_azs" {
  assert {
    condition     = length(module.network.public_subnet_ids) >= 2
    error_message = "ALB must span at least two AZs."
  }
}

check "target_group_is_ip" {
  assert {
    condition     = module.alb.target_group_type == "ip"
    error_message = "Target group type must be ip for Fargate."
  }
}

check "image_not_latest" {
  assert {
    condition     = var.image_tag_a != "latest" && var.image_tag_b != "latest" && var.image_tag_c != "latest"
    error_message = "latest image tag is not accepted."
  }
}

check "region_is_eu_west_1" {
  assert {
    condition     = var.aws_region == "eu-west-1"
    error_message = "Unapproved Region. Group 5 must use eu-west-1."
  }
}

check "iac_ecr_immutable" {
  assert {
    condition     = alltrue([for r in aws_ecr_repository.services : r.image_tag_mutability == "IMMUTABLE"])
    error_message = "IaC ECR repos must be IMMUTABLE."
  }
}

check "tasks_have_no_public_ip" {
  assert {
    condition     = module.service_a.assign_public_ip == false && module.service_b.assign_public_ip == false && module.service_c.assign_public_ip == false
    error_message = "Fargate tasks must not receive public IPs."
  }
}

check "alb_can_reach_service_a" {
  assert {
    condition     = aws_security_group_rule.alb_to_a.source_security_group_id == aws_security_group.alb.id && aws_security_group_rule.alb_to_a.from_port == 3001
    error_message = "ALB security group must be allowed into Service A on port 3001."
  }
}

check "service_a_can_reach_service_b" {
  assert {
    condition     = aws_security_group_rule.a_to_b.source_security_group_id == aws_security_group.service_a.id && aws_security_group_rule.a_to_b.from_port == 3002
    error_message = "Service A must be allowed into Service B on port 3002."
  }
}

check "service_b_can_reach_service_c" {
  assert {
    condition     = aws_security_group_rule.b_to_c.source_security_group_id == aws_security_group.service_b.id && aws_security_group_rule.b_to_c.from_port == 3003
    error_message = "Service B must be allowed into Service C on port 3003."
  }
}

check "service_a_cannot_reach_service_c_directly" {
  assert {
    condition = length([
      for r in [
        aws_security_group_rule.alb_to_a,
        aws_security_group_rule.a_to_b,
        aws_security_group_rule.b_to_c,
        aws_security_group_rule.c_to_a_callback,
      ] : r if r.security_group_id == aws_security_group.service_c.id && r.source_security_group_id == aws_security_group.service_a.id
    ]) == 0
    error_message = "Service A must not have a direct ingress path into Service C."
  }
}

check "required_tags_present" {
  assert {
    condition     = local.common_tags.Project == "devops-mentorship" && local.common_tags.Group == "group-5" && local.common_tags.Environment == "lab"
    error_message = "Required Project/Group/Environment tags are missing."
  }
}

check "pipelines_or_gha" {
  assert {
    condition     = var.enable_codepipeline ? length(module.pipeline_a) == 1 : module.github_oidc.role_arn != ""
    error_message = "Either CodePipeline or GitHub Actions OIDC deploy role must be configured."
  }
}

# App-port ingress must use SG references only (no 0.0.0.0/0 on 3001/3002/3003).
check "no_public_app_port_ingress_on_service_a" {
  assert {
    condition = alltrue([
      for rule in [
        aws_security_group_rule.alb_to_a,
        aws_security_group_rule.c_to_a_callback,
      ] : rule.cidr_blocks == null || length(coalesce(rule.cidr_blocks, [])) == 0
    ])
    error_message = "Service A application port must not be open to 0.0.0.0/0."
  }
}

output "alb_dns_name" { value = module.alb.alb_dns_name }
output "greet_url" { value = "http://${module.alb.alb_dns_name}/greet-service-b" }
output "cluster_name" { value = module.ecs_platform.cluster_name }
output "namespace" { value = module.ecs_platform.namespace_name }
output "vpc_id" { value = module.network.vpc_id }
output "name_prefix" { value = var.name_prefix }
output "deployed_image_tags" {
  value = {
    a = var.image_tag_a
    b = var.image_tag_b
    c = var.image_tag_c
  }
}
output "iac_ecr_urls" {
  value = { for k, r in aws_ecr_repository.services : k => r.repository_url }
}
output "pipelines" {
  value = var.enable_codepipeline ? {
    a = module.pipeline_a[0].pipeline_name
    b = module.pipeline_b[0].pipeline_name
    c = module.pipeline_c[0].pipeline_name
  } : {}
}
output "github_actions_role_arn" {
  value = module.github_oidc.role_arn
}
output "release_path" {
  value = "push/merge main → GitHub Actions (OIDC) → build SHA → ECR devops-g5-iac-service-* → ECS deploy → prove via ALB /version"
}
