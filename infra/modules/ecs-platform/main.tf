variable "name_prefix" { type = string }
variable "namespace_name" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags = merge(var.tags, {
    Name  = "${var.name_prefix}-ecs-execution-role"
    Owner = "platform-owner"
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags = merge(var.tags, {
    Name  = "${var.name_prefix}-ecs-task-role"
    Owner = "platform-owner"
  })
}

# ECS Exec (SSM messages)
resource "aws_iam_role_policy" "task_exec" {
  name = "${var.name_prefix}-ecs-exec"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_service_discovery_http_namespace" "this" {
  name        = var.namespace_name
  description = "Service Connect namespace for ${var.name_prefix}"
  tags = merge(var.tags, {
    Name  = var.namespace_name
    Owner = "platform-owner"
  })
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = merge(var.tags, {
    Name  = "${var.name_prefix}-cluster"
    Owner = "platform-owner"
  })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

output "cluster_id" { value = aws_ecs_cluster.this.id }
output "cluster_name" { value = aws_ecs_cluster.this.name }
output "cluster_arn" { value = aws_ecs_cluster.this.arn }
output "namespace_arn" { value = aws_service_discovery_http_namespace.this.arn }
output "namespace_name" { value = aws_service_discovery_http_namespace.this.name }
output "execution_role_arn" { value = aws_iam_role.execution.arn }
output "task_role_arn" { value = aws_iam_role.task.arn }
