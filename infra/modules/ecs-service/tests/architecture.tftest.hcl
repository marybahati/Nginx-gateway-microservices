# Architecture rules as code — run from this module directory:
#   terraform test
#
# Covers Assignment 1 rejects: public IP, latest tag, and contract shape.

run "rejects_latest_image_tag" {
  command = plan

  variables {
    name_prefix        = "devops-g5-iac"
    service_key        = "a"
    container_name     = "service-a"
    container_port     = 3001
    image_tag          = "latest"
    ecr_repository_url = "111111111111.dkr.ecr.eu-west-1.amazonaws.com/devops-g5-iac-service-a"
    cluster_arn        = "arn:aws:ecs:eu-west-1:111111111111:cluster/devops-g5-iac-cluster"
    cluster_name       = "devops-g5-iac-cluster"
    namespace_arn      = "arn:aws:servicediscovery:eu-west-1:111111111111:http-namespace/ns-test"
    private_subnet_ids = ["subnet-aaa", "subnet-bbb"]
    security_group_ids = ["sg-aaa"]
    execution_role_arn = "arn:aws:iam::111111111111:role/exec"
    task_role_arn      = "arn:aws:iam::111111111111:role/task"
    aws_region         = "eu-west-1"
    desired_count      = 2
    assign_public_ip   = false
    owner_tag          = "service-a-owner"
  }

  expect_failures = [
    var.image_tag,
  ]
}

run "rejects_public_task_ip" {
  command = plan

  variables {
    name_prefix        = "devops-g5-iac"
    service_key        = "a"
    container_name     = "service-a"
    container_port     = 3001
    image_tag          = "abcdef1"
    ecr_repository_url = "111111111111.dkr.ecr.eu-west-1.amazonaws.com/devops-g5-iac-service-a"
    cluster_arn        = "arn:aws:ecs:eu-west-1:111111111111:cluster/devops-g5-iac-cluster"
    cluster_name       = "devops-g5-iac-cluster"
    namespace_arn      = "arn:aws:servicediscovery:eu-west-1:111111111111:http-namespace/ns-test"
    private_subnet_ids = ["subnet-aaa", "subnet-bbb"]
    security_group_ids = ["sg-aaa"]
    execution_role_arn = "arn:aws:iam::111111111111:role/exec"
    task_role_arn      = "arn:aws:iam::111111111111:role/task"
    aws_region         = "eu-west-1"
    desired_count      = 2
    assign_public_ip   = true
    owner_tag          = "service-a-owner"
  }

  expect_failures = [
    var.assign_public_ip,
  ]
}

run "accepts_git_sha_tag_private_ip" {
  command = plan

  variables {
    name_prefix        = "devops-g5-iac"
    service_key        = "a"
    container_name     = "service-a"
    container_port     = 3001
    image_tag          = "4289726"
    ecr_repository_url = "111111111111.dkr.ecr.eu-west-1.amazonaws.com/devops-g5-iac-service-a"
    cluster_arn        = "arn:aws:ecs:eu-west-1:111111111111:cluster/devops-g5-iac-cluster"
    cluster_name       = "devops-g5-iac-cluster"
    namespace_arn      = "arn:aws:servicediscovery:eu-west-1:111111111111:http-namespace/ns-test"
    private_subnet_ids = ["subnet-aaa", "subnet-bbb"]
    security_group_ids = ["sg-aaa"]
    execution_role_arn = "arn:aws:iam::111111111111:role/exec"
    task_role_arn      = "arn:aws:iam::111111111111:role/task"
    aws_region         = "eu-west-1"
    desired_count      = 2
    assign_public_ip   = false
    owner_tag          = "service-a-owner"
  }

  assert {
    condition     = aws_ecs_service.this.network_configuration[0].assign_public_ip == false
    error_message = "Tasks must not receive public IPs."
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.this.container_definitions, "4289726")
    error_message = "Task definition must embed the declared Git SHA tag."
  }
}
