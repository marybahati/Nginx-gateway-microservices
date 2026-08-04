variable "name_prefix" { type = string }
variable "service_key" { type = string }
variable "container_name" { type = string }
variable "ecr_repository_name" { type = string }
variable "ecs_cluster_name" { type = string }
variable "ecs_service_name" { type = string }
variable "buildspec_path" { type = string }
variable "connection_arn" { type = string }
variable "github_full_repository_id" {
  type    = string
  default = "marybahati/Nginx-gateway-microservices"
}
variable "github_branch" {
  type    = string
  default = "main"
}
variable "artifact_bucket" { type = string }
variable "codebuild_role_arn" { type = string }
variable "codepipeline_role_arn" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
variable "owner_tag" { type = string }

# Paths that trigger this pipeline. Empty list = trigger on any change (CodePipeline default).
# Provide glob patterns relative to repo root, e.g. ["services/service-b/**", "shared/**"].
variable "watched_paths" {
  type    = list(string)
  default = []
}

variable "enable_ecs_deploy" {
  type        = bool
  default     = false
  description = "When false (Assignment 1 default), pipeline builds/pushes SHA images only; IaC selects the deployed tag."
}

resource "aws_codebuild_project" "this" {
  name         = "${var.name_prefix}-codebuild-service-${var.service_key}"
  service_role = var.codebuild_role_arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "ECR_REPOSITORY"
      value = var.ecr_repository_name
    }
    environment_variable {
      name  = "CONTAINER_NAME"
      value = var.container_name
    }
    environment_variable {
      name  = "SERVICE_NAME"
      value = "service-${var.service_key}"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = var.buildspec_path
  }

  tags = merge(var.tags, {
    Name  = "${var.name_prefix}-codebuild-service-${var.service_key}"
    Owner = var.owner_tag
  })
}

resource "aws_codepipeline" "this" {
  name          = "${var.name_prefix}-pipeline-service-${var.service_key}"
  role_arn      = var.codepipeline_role_arn
  # Path-filtered push triggers (file_paths) require pipeline type V2.
  pipeline_type = "V2"

  artifact_store {
    location = var.artifact_bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      configuration = {
        ConnectionArn        = var.connection_arn
        FullRepositoryId     = var.github_full_repository_id
        BranchName           = var.github_branch
        DetectChanges        = "false"
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      configuration = {
        ProjectName = aws_codebuild_project.this.name
      }
    }
  }

  dynamic "stage" {
    for_each = var.enable_ecs_deploy ? [1] : []
    content {
      name = "Deploy"
      action {
        name            = "Deploy"
        category        = "Deploy"
        owner           = "AWS"
        provider        = "ECS"
        version         = "1"
        input_artifacts = ["BuildOutput"]
        configuration = {
          ClusterName = var.ecs_cluster_name
          ServiceName = var.ecs_service_name
          FileName    = "imagedefinitions.json"
        }
      }
    }
  }

  tags = merge(var.tags, {
    Name  = "${var.name_prefix}-pipeline-service-${var.service_key}"
    Owner = var.owner_tag
  })

  # Path-filtered trigger: only fire when files under watched_paths change on the branch.
  # When watched_paths is empty the trigger fires on every push (open filter).
  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches {
          includes = [var.github_branch]
        }
        dynamic "file_paths" {
          for_each = length(var.watched_paths) > 0 ? [1] : []
          content {
            includes = var.watched_paths
          }
        }
      }
    }
  }
}

output "pipeline_name" { value = aws_codepipeline.this.name }
output "codebuild_name" { value = aws_codebuild_project.this.name }
