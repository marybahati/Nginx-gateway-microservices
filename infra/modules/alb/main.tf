variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "alb_security_group_id" { type = string }
variable "service_a_port" {
  type    = number
  default = 3001
}
variable "health_check_path" {
  type    = string
  default = "/health?shallow=1"
}
variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  tags = merge(var.tags, {
    Name  = "${var.name_prefix}-alb"
    Owner = "platform-owner"
  })

  lifecycle {
    precondition {
      condition     = length(var.public_subnet_ids) >= 2
      error_message = "ALB must span at least two public subnets / AZs."
    }
  }
}

resource "aws_lb_target_group" "service_a" {
  name        = "${var.name_prefix}-tg-service-a"
  port        = var.service_a_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  # Keep drains short so Service Connect mesh refreshes / pipeline deploys finish promptly.
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, {
    Name  = "${var.name_prefix}-tg-service-a"
    Owner = "platform-owner"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a.arn
  }
}

output "alb_arn" { value = aws_lb.this.arn }
output "alb_arn_suffix" { value = aws_lb.this.arn_suffix }
output "alb_dns_name" { value = aws_lb.this.dns_name }
output "target_group_arn" { value = aws_lb_target_group.service_a.arn }
output "target_group_arn_suffix" { value = aws_lb_target_group.service_a.arn_suffix }
output "listener_arn" { value = aws_lb_listener.http.arn }
output "target_group_type" { value = aws_lb_target_group.service_a.target_type }
