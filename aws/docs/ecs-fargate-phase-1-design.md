# Elastic Container Service on Fargate Phase 1 Design

**Host It · Wire It · Ship It**

| Field | Value |
|---|---|
| Group | `group-5` |
| Naming prefix | `devops-g5-` |
| Service Connect namespace | `group5.internal` |
| Repository | Nginx-gateway-microservices (monorepo) |
| Target network | Default Virtual Private Cloud · public subnets in two Availability Zones · public Internet Protocol address enabled for lab outbound access |
| Status | Design complete · no AWS resources created |

### Standard tags

| Key | Value |
|---|---|
| `Project` | `devops-mentorship` |
| `Group` | `group-5` |
| `Owner` | `service-a-owner` · `service-b-owner` · `service-c-owner` · `platform-owner` |
| `Environment` | `lab` |

### Application baseline

| Service | Port | Role |
|---|---|---|
| service-a | `3001` | Edge service behind the Application Load Balancer. Starts the greet chain and waits for callback. |
| service-b | `3002` | Internal relay. |
| service-c | `3003` | Internal processor; sends callback to service-a. |

```
Client → Application Load Balancer → service-a :3001
                                      │
                                      ├─→ service-b :3002
                                      │         │
                                      │         └─→ service-c :3003
                                      │                   │
                                      └──── POST /greeting-rcvd ◄──┘
```

The `X-Request-ID` header propagates from service-a → service-b → service-c → service-a.

**Traffic design decision:** service-a → service-c is denied. The greet path does not need service-a to call service-c; it needs service-c to call service-a (callback). That callback is included in our contracts.

**Code alignment (done):** `wait-for-deps` waits on service-b only; service-a `/health` checks service-b only; `/lab/fail` calls service-b `/fail` (not service-c). Application Load Balancer health can use `/health` or `/health?shallow=1`. Each service exposes `/version` with `SERVICE_VERSION` / Git commit SHA.

---

## 1. Dependency graph

### 1.1 Create-order graph

```
Identity and Access Management identity(IAM) (console / command line / pipeline roles)
        │
Assigned Region
        │
Default Virtual Private Cloud
        │
Default public subnets (Availability Zone a + Availability Zone b)
        │
Security groups
  ├── devops-g5-alb-sg
  ├── devops-g5-service-a-sg
  ├── devops-g5-service-b-sg
  └── devops-g5-service-c-sg
        │
Elastic Container Registry repositories
  ├── devops-g5-service-a
  ├── devops-g5-service-b
  └── devops-g5-service-c
        │
Elastic Container Service cluster: devops-g5-cluster
        │
Task definitions (Fargate / awsvpc)
  ├── devops-g5-td-service-a
  ├── devops-g5-td-service-b
  └── devops-g5-td-service-c
        │
Elastic Container Service services
  ├── devops-g5-svc-service-a  (desired count 1, Application Load Balancer later)
  ├── devops-g5-svc-service-b  (desired count 1, no Application Load Balancer)
  └── devops-g5-svc-service-c  (desired count 1, no Application Load Balancer)
        │
Service Connect namespace: group5.internal
  discovery names: service-a, service-b, service-c
        │
Target group: devops-g5-tg-service-a  (type: ip, health /health?shallow=1)
        │
Application Load Balancer: devops-g5-alb  (internet-facing, Hypertext Transfer Protocol port 80)
        │
Domain Name System: Application Load Balancer domain name → clients
```

### 1.2 Delivery chain (later phase)

```
GitHub monorepo (main, branch protection)
        │
CodeConnections (one connection, platform-owned)
        │
Per-service CodePipeline
  ├── devops-g5-pipeline-service-a
  ├── devops-g5-pipeline-service-b
  └── devops-g5-pipeline-service-c
        │
Per-service CodeBuild (privileged Docker)
  ├── devops-g5-codebuild-service-a → buildspecs/service-a.yml
  ├── devops-g5-codebuild-service-b → buildspecs/service-b.yml
  └── devops-g5-codebuild-service-c → buildspecs/service-c.yml
        │
Push Git-commit-SHA-tagged image → Elastic Container Registry
        │
Elastic Container Service deploy → new task-definition revision → rolling deploy
```

### 1.3 Supporting attachments

```
Elastic Container Service tasks ──► CloudWatch Logs (per-service log groups)
Elastic Container Service Exec  ──► Systems Manager messaging
Application Load Balancer       ──► access logs / target health
```

### 1.4 Runtime request path

```
Internet users
      │ port 80
      ▼
devops-g5-alb  (replaces Nginx)
      │ port 3001  (Application Load Balancer security group → service-a security group)
      ▼
service-a.group5.internal :3001   [Elastic Container Service service-a × 1]
      │ port 3002  (service-a security group → service-b security group)  Service Connect
      ▼
service-b.group5.internal :3002   [Elastic Container Service service-b × 1]
      │ port 3003  (service-b security group → service-c security group)  Service Connect
      ▼
service-c.group5.internal :3003   [Elastic Container Service service-c × 1]
      │ port 3001  (service-c security group → service-a security group)  Service Connect callback
      ▼
service-a  POST /greeting-rcvd
```

**Denied edges**

- Internet → service-a / service-b / service-c application ports
- service-a → service-c
- Application Load Balancer → service-b or Application Load Balancer → service-c

### 1.5 Dependency answers

| Question | Answer |
|---|---|
| What must exist before a Fargate task can start? | Cluster, task definition revision, subnets, security group, execution role, and a pullable Elastic Container Registry image. Service Connect namespace if Domain Name System names are required at start. |
| What must exist before Elastic Container Service can pull an image? | Elastic Container Registry repository and image tag; execution role with Elastic Container Registry pull and CloudWatch log permissions; network path to Elastic Container Registry (public subnet and public Internet Protocol address in this lab). |
| What must exist before the Application Load Balancer can route traffic? | Application Load Balancer, listener on port 80, target group (Internet Protocol target type), healthy service-a tasks, Application Load Balancer security group → service-a security group on port 3001, service-a listening on `0.0.0.0:3001`. |
| What depends on the named container port? | Task definition port mapping name, Service Connect port, security-group destination port, Application Load Balancer target-group port, and deploy artifact container name. |
| Which resources survive task replacement? | Cluster, services, task definition family, Application Load Balancer, target group, security groups, Elastic Container Registry images, Service Connect namespace, pipelines. Task Elastic Network Interfaces and ephemeral public Internet Protocol addresses do not. |
| Which resources generate cost while idle? | Running Fargate tasks, Application Load Balancer, Elastic Container Registry storage, CloudWatch log storage and ingestion. The default Virtual Private Cloud itself does not. |

---

## 2. Failure predictions

| # | Broken edge | User symptom | AWS evidence |
|---|---|---|---|
| 1 | **Elastic Container Service → Elastic Container Registry** — wrong image tag, missing pull permissions, or bad execution role | Application Load Balancer never becomes healthy; service-a does not reach steady RUNNING / HEALTHY | Elastic Container Service service events show image pull failure; stopped-task reason; CloudWatch may be empty if the task never starts |
| 2 | **service-a → service-b port 3002** — wrong Service Connect name, wrong named port, or service-a security group not allowed into service-b security group | Client reaches Application Load Balancer → service-a, but greet fails. Shallow service-a health can still look OK | Elastic Container Service Exec from service-a: `curl http://service-b:3002/health` times out or is refused; security group rules missing service-a → service-b; service-a logs show forward failure |
| 3 | **service-c → service-a port 3001 callback** — wrong callback Uniform Resource Locator or service-c security group blocked from service-a security group | Forward path service-a → service-b → service-c may succeed in logs, but the client waits and then gets **504 `downstream_timeout`** | Elastic Container Service Exec service-c → service-a fails; service-a logs show pending callback timeout; service-c logs show callback error; security group missing service-c → service-a port 3001 |

These cover host (image pull), forward wiring (service-a → service-b), and the callback this application depends on (service-c → service-a).

---

## 3. Traffic contracts

**Permitted path**

`Internet → Application Load Balancer port 80 → service-a port 3001 → service-b port 3002 → service-c port 3003 → (callback) service-a port 3001`

### 3.1 Allow / deny matrix

| Source | Destination | Port | Allowed | Enforcement |
|---|---|---|---|---|
| Internet | Application Load Balancer | 80 | Yes | `devops-g5-alb-sg` ingress from `0.0.0.0/0` port 80 |
| Internet | service-a | 3001 | No | `devops-g5-service-a-sg` — no internet ingress |
| Internet | service-b | 3002 | No | `devops-g5-service-b-sg` — no internet ingress |
| Internet | service-c | 3003 | No | `devops-g5-service-c-sg` — no internet ingress |
| Application Load Balancer | service-a | 3001 | Yes | Application Load Balancer security group → service-a security group reference on port 3001 |
| service-a | service-b | 3002 | Yes | service-a security group → service-b security group reference on port 3002 |
| service-a | service-c | 3003 | No | No matching security group rule |
| service-b | service-c | 3003 | Yes | service-b security group → service-c security group reference on port 3003 |
| service-c | service-a | 3001 | Yes | service-c security group → service-a security group reference on port 3001 (callback) |

A public Internet Protocol address on Fargate tasks does not mean public access. Security groups enforce the contract.

### 3.2 Pair agreements

| Pair | Protocol | Port | Service Connect name | Security group reference | Endpoint | Timeout |
|---|---|---|---|---|---|---|
| Client → Application Load Balancer | Hypertext Transfer Protocol | 80 | Application Load Balancer domain name | Internet → alb-sg | Application Load Balancer listener | about 5 seconds client curl |
| Application Load Balancer → service-a | Hypertext Transfer Protocol | 3001 | — (target group Internet Protocol type) | alb-sg → service-a-sg | `GET /health?shallow=1` | Application Load Balancer health interval (30 seconds, see 3.3) |
| service-a → service-b | Hypertext Transfer Protocol | 3002 | `service-b` in `group5.internal` | service-a-sg → service-b-sg | `GET /health` | 5 second probe; application uses its own timeout |
| service-b → service-c | Hypertext Transfer Protocol | 3003 | `service-c` in `group5.internal` | service-b-sg → service-c-sg | `GET /health` | 5 second probe |
| service-c → service-a | Hypertext Transfer Protocol | 3001 | `service-a` in `group5.internal` | service-c-sg → service-a-sg | `POST /greeting-rcvd` | less than or equal to `CALLBACK_TIMEOUT_MS` (default 30 seconds) |

**Timeout interaction check:** the ALB's default idle timeout is 60 seconds, comfortably above the application's `CALLBACK_TIMEOUT_MS` default of 30 seconds. A client waiting on `/greet-service-b` will receive the application's own 504 `downstream_timeout` before the ALB would ever cut the connection — confirmed so the two timeouts don't interact unexpectedly.

### 3.3 Application Load Balancer health check settings

| Setting | Value |
|---|---|
| Path | `/health?shallow=1` |
| Interval | 30 seconds |
| Timeout | 5 seconds |
| Healthy threshold | 2 consecutive successes |
| Unhealthy threshold | 3 consecutive failures |

These numbers directly determine observed recovery time in Phase 4.3 (kill a task) — worst case, an unhealthy target is pulled from rotation within roughly 2–3 health-check cycles (60–90 seconds) of the underlying task actually failing, though ECS typically deregisters a stopped task's target faster via the stopping lifecycle hook.

### 3.4 Runtime verification plan

| Test | Where | Expected |
|---|---|---|
| Internet → Application Load Balancer | Engineer machine | Allowed |
| Application Load Balancer → service-a | Public request | Allowed |
| service-a → service-b | Elastic Container Service Exec in service-a | Allowed |
| service-b → service-c | Elastic Container Service Exec in service-b | Allowed |
| service-c → service-a | Elastic Container Service Exec in service-c | Allowed |
| Internet → service-a / service-b / service-c application ports | Engineer machine | Denied |
| service-a → service-c | Elastic Container Service Exec in service-a | Denied |

---

## 4. Resource ownership

Owners may advise each other; they do not operate another owner's console.

### 4.1 Ownership map

| Role | Person | Type | Owns |
|---|---|---|---|
| Platform owner | Weekly rotation: **Mary → Warga → Sharon → Mary…** (one week each) | Rotated | Cluster, Service Connect namespace `group5.internal`, Application Load Balancer, target group, listener, CodeConnections, shared Identity and Access Management patterns, naming and tagging |
| Service A owner | **Mary** | Individual | Image, Elastic Container Registry `devops-g5-service-a`, task definition, `devops-g5-service-a-sg`, Elastic Container Service service-a (desired **1**, Application Load Balancer later), pipeline for service-a, scar log for service-a |
| Service B owner | **Warga** | Individual | Image, Elastic Container Registry `devops-g5-service-b`, task definition, `devops-g5-service-b-sg`, Elastic Container Service service-b (desired **1**, no Application Load Balancer), pipeline for service-b, scar log for service-b |
| Service C owner | **Sharon** | Individual | Image, Elastic Container Registry `devops-g5-service-c`, task definition, `devops-g5-service-c-sg`, Elastic Container Service service-c (desired **1**, no Application Load Balancer), pipeline for service-c, scar log for service-c |

### 4.2 Resource to owner

| Resource | Owner | Notes |
|---|---|---|
| `devops-g5-cluster` | Platform | Fargate |
| `group5.internal` | Platform | Service Connect |
| `devops-g5-alb` | Platform | Internet-facing, two Availability Zones |
| `devops-g5-tg-service-a` | Platform | type `ip`, `/health?shallow=1`, port 3001 |
| Execution role(s) | Platform (+ service owners) | Elastic Container Registry pull + CloudWatch logs |
| Task role(s) | Platform (+ service owners) | Runtime + Elastic Container Service Exec / Systems Manager |
| `devops-g5-alb-sg` | Platform | Ingress port 80 from internet |
| `devops-g5-service-a-sg` | Service A | Ingress from alb-sg port 3001 and service-c-sg port 3001 |
| `devops-g5-service-b-sg` | Service B | Ingress from service-a-sg port 3002 |
| `devops-g5-service-c-sg` | Service C | Ingress from service-b-sg port 3003 |
| Elastic Container Registry / task definition / Elastic Container Service service / pipeline for each service | Matching service owner | Git commit SHA tags only · no `latest` |
| CloudWatch log groups | Matching service owner | From task logging config |
| CodeConnections | Platform | One connection for all pipelines |
| Branch protection on `main` | Platform + team | Pull requests required · approvals required · no direct push |

### 4.3 Elastic Container Service plan

| Service | Desired count | CPU | Memory | Application Load Balancer | Public Internet Protocol address | Circuit breaker + rollback | Elastic Container Service Exec |
|---|---|---|---|---|---|---|---|
| service-a | **1** | 256 (.25 vCPU) | 512 MB | Yes (after Application Load Balancer is wired) | Enabled | Enabled | Enabled |
| service-b | **1** | 256 (.25 vCPU) | 512 MB | No | Enabled | Enabled | Enabled |
| service-c | **1** | 256 (.25 vCPU) | 512 MB | No | Enabled | Enabled | Enabled |

**CPU/memory justification:** all three services are thin Node.js HTTP relays/orchestrators with no heavy compute or in-memory data processing. service-a holds request state slightly longer (up to 30 seconds while awaiting the service-c callback), so it gets the same headroom as B and C rather than less, to avoid memory pressure under concurrent in-flight requests during load testing (Phase 4.3).

**Fargate platform version:** `LATEST` (currently maps to 1.4.0 or newer) for all task definitions — required for Service Connect and ECS Exec support.

---

## 5. Expected resource names

All AWS resource names use prefix `devops-g5-`. The Service Connect namespace is `group5.internal`.

### 5.1 Platform and networking

| Resource | Name |
|---|---|
| Elastic Container Service cluster | `devops-g5-cluster` |
| Service Connect namespace | `group5.internal` |
| Application Load Balancer | `devops-g5-alb` |
| Application Load Balancer security group | `devops-g5-alb-sg` |
| Target group (service-a only) | `devops-g5-tg-service-a` |
| Elastic Container Service execution role | `devops-g5-ecs-execution-role` |
| Elastic Container Service task role | `devops-g5-ecs-task-role` |
| CloudWatch log group service-a | `/ecs/devops-g5-service-a` |
| CloudWatch log group service-b | `/ecs/devops-g5-service-b` |
| CloudWatch log group service-c | `/ecs/devops-g5-service-c` |
| Fargate platform version | `LATEST` (1.4.0+) |

### 5.2 Per-service hosting

| Resource | service-a | service-b | service-c |
|---|---|---|---|
| Elastic Container Registry repository | `devops-g5-service-a` | `devops-g5-service-b` | `devops-g5-service-c` |
| Task definition family | `devops-g5-td-service-a` | `devops-g5-td-service-b` | `devops-g5-td-service-c` |
| Container name | `service-a` | `service-b` | `service-c` |
| Named port mapping | `service-a` → 3001 | `service-b` → 3002 | `service-c` → 3003 |
| Elastic Container Service service | `devops-g5-svc-service-a` | `devops-g5-svc-service-b` | `devops-g5-svc-service-c` |
| Security group | `devops-g5-service-a-sg` | `devops-g5-service-b-sg` | `devops-g5-service-c-sg` |
| Service Connect name | `service-a` | `service-b` | `service-c` |
| CPU / Memory | 256 / 512 MB | 256 / 512 MB | 256 / 512 MB |

### 5.3 Delivery names (reserved)

| Resource | service-a | service-b | service-c |
|---|---|---|---|
| CodeBuild | `devops-g5-codebuild-service-a` | `devops-g5-codebuild-service-b` | `devops-g5-codebuild-service-c` |
| CodePipeline | `devops-g5-pipeline-service-a` | `devops-g5-pipeline-service-b` | `devops-g5-pipeline-service-c` |
| Build specification | `buildspecs/service-a.yml` | `buildspecs/service-b.yml` | `buildspecs/service-c.yml` |
| CodeConnections | `devops-g5-github-connection` (shared) | shared | shared |

**Forward note on IAM:** the CodePipeline role created during Phase 5 setup must not be granted unrestricted `iam:PassRole`. Scope it to the exact `devops-g5-ecs-execution-role` and `devops-g5-ecs-task-role` ARNs used by this group's services. Flagged here ahead of Phase 5 so the platform owner isn't surprised by the requirement when setting up the pipeline.

### 5.4 Image tagging

| Rule | Example |
|---|---|
| Tag with Git commit SHA | `devops-g5-service-a:a81f23c` |
| Do not use | `latest` |
| Runtime version | `/health` or `/version` returns `"version": "<sha>"` |