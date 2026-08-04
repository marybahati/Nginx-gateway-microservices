# Architecture rules as code

Assignment 1 requires automatic reject/detect for at least six unsafe designs.

## Where the rules live

| Rule | Mechanism | Location |
|---|---|---|
| Task receives a public IP | variable validation + check + module test | `modules/ecs-service` + lab checks |
| ALB spans fewer than two AZs | precondition + check + module test | `modules/alb` + lab checks |
| Target group type is not `ip` | check + module test | `modules/alb` + lab checks |
| App port open to `0.0.0.0/0` | design: SG refs only (no such rule exists) | lab SG resources |
| ALB cannot reach Service A | check on SG rule | lab `alb_can_reach_service_a` |
| Service A cannot reach Service B | check on SG rule | lab `service_a_can_reach_service_b` |
| Service B cannot reach Service C | check on SG rule | lab `service_b_can_reach_service_c` |
| Service A can reach Service C | check proves no A→C ingress | lab `service_a_cannot_reach_service_c_directly` |
| Required tags missing | check | lab `required_tags_present` |
| Unapproved Region | variable validation + check | lab `aws_region` |
| Image tag is `latest` | variable validation + check + module test | ecs-service + lab |

## Run module tests

```bash
cd infra/modules/ecs-service && terraform test
cd infra/modules/alb && terraform test
```

## Run root checks

```bash
cd infra/environments/lab
terraform init
terraform plan   # evaluates check blocks
```
