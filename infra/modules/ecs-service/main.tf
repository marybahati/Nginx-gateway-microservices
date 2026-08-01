variable "name_prefix" { type = string }
variable "service_key" {
  type        = string
  description = "a | b | c"
}
variable "container_name" { type = string }
variable "container_port" { type = number }
variable "image_tag" {
  type = string
  validation {
    condition     = var.image_tag != "latest" && can(regex("^[0-9a-f]{7,40}$", var.image_tag))
    error_message = "image_tag must be an immutable Git SHA (7-40 hex), not latest."
  }
}
variable "ecr_repository_url" { type = string }
variable "cluster_arn" { type = string }
variable "cluster_name" { type = string }
variable "namespace_arn" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "execution_role_arn" { type = string }
variable "task_role_arn" { type = string }
variable "aws_region" { type = string }
variable "desired_count" {
  type = number
}
variable "cpu" {
  type    = string
  default = "256"
}
variable "memory" {
  type    = string
  default = "512"
}
variable "environment" {
  type    = map(string)
  default = {}
}
variable "assign_public_ip" {
  type    = bool
  default = false
  validation {
    condition     = var.assign_public_ip == false
    error_message = "Fargate tasks must not receive public IPs."
  }
}
variable "enable_load_balancer" {
  type    = bool
  default = false
}
variable "target_group_arn" {
  type    = string
  default = null
}
variable "owner_tag" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  service_name     = "${var.name_prefix}-svc-service-${var.service_key}"
  task_family      = "${var.name_prefix}-td-service-${var.service_key}"
  log_group_name   = "/ecs/${var.name_prefix}-service-${var.service_key}"
  discovery_name   = "service-${var.service_key}"
  image_uri        = "${var.ecr_repository_url}:${var.image_tag}"
  env_list = [
    for k, v in merge(
      {
        BIND_HOST         = "0.0.0.0"
        PORT              = tostring(var.container_port)
        OTEL_SDK_DISABLED = "true"
        SERVICE_VERSION   = var.image_tag
      },
      var.environment
    ) : { name = k, value = v }
  ]
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = 14
  tags = merge(var.tags, {
    Name  = local.log_group_name
    Owner = var.owner_tag
  })
}

resource "aws_ecs_task_definition" "this" {
  family                   = local.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = local.image_uri
      essential = true
      portMappings = [
        {
          name          = var.container_name
          containerPort = var.container_port
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      environment = local.env_list
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = var.container_name
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -sf http://127.0.0.1:${var.container_port}/health?shallow=1 || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 90
      }
    }
  ])

  tags = merge(var.tags, {
    Name  = local.task_family
    Owner = var.owner_tag
  })
}

resource "aws_ecs_service" "this" {
  name                   = local.service_name
  cluster                = var.cluster_arn
  task_definition        = aws_ecs_task_definition.this.arn
  desired_count          = var.desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true
  force_new_deployment   = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = var.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = var.enable_load_balancer ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  service_connect_configuration {
    enabled   = true
    namespace = var.namespace_arn
    service {
      port_name      = var.container_name
      discovery_name = local.discovery_name
      client_alias {
        port     = var.container_port
        dns_name = local.discovery_name
      }
    }
  }

  tags = merge(var.tags, {
    Name  = local.service_name
    Owner = var.owner_tag
  })

  depends_on = [aws_cloudwatch_log_group.this]

  # CodePipeline ECS deploy owns new task-definition revisions (SHA images).
  # Terraform still owns desired_count, network, Service Connect, circuit breaker.
  lifecycle {
    ignore_changes = [task_definition, force_new_deployment]
  }
}

output "service_name" { value = aws_ecs_service.this.name }
output "task_definition_arn" { value = aws_ecs_task_definition.this.arn }
output "log_group_name" { value = aws_cloudwatch_log_group.this.name }
output "image_uri" { value = local.image_uri }
output "discovery_name" { value = local.discovery_name }
