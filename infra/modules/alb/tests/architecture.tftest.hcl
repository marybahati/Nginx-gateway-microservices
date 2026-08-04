# ALB contract tests — run from this module directory:
#   terraform test

run "rejects_fewer_than_two_public_subnets" {
  command = plan

  variables {
    name_prefix           = "devops-g5-iac"
    vpc_id                = "vpc-aaa"
    public_subnet_ids     = ["subnet-only-one"]
    alb_security_group_id = "sg-alb"
  }

  expect_failures = [
    aws_lb.this,
  ]
}

run "target_group_is_ip_type" {
  command = plan

  variables {
    name_prefix           = "devops-g5-iac"
    vpc_id                = "vpc-aaa"
    public_subnet_ids     = ["subnet-aaa", "subnet-bbb"]
    alb_security_group_id = "sg-alb"
  }

  assert {
    condition     = aws_lb_target_group.service_a.target_type == "ip"
    error_message = "Target group type must be ip for Fargate."
  }

  assert {
    condition     = length(aws_lb.this.subnets) >= 2
    error_message = "ALB must span at least two AZs."
  }
}
