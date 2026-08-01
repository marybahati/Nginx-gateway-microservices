# Gate 1 — Design before creation  
## Assignment 1: Greenfield ECS Fargate (OpenTofu)

**Group:** `group-5`  
**Region:** `eu-west-1` (assigned mentorship region)  
**Tool:** **OpenTofu** (pinned CLI + AWS provider — versions recorded at first `init`)  
**Scope:** Greenfield only. No workload `apply` until this Gate 1 review passes.  
**Naming prefix:** `devops-g5-`  
**Service Connect namespace:** `group5.internal`

**Status:** Design for peer review — **zero workload resources created by IaC yet.**

---

## 0. Mission alignment (what we must be able to do)

```text
Predict → Plan → Review → Apply → Prove → Release → Destroy → Rebuild
```

Live demo loop: spin up → walk modules → prove A→B→C contracts → release SHA → destroy → rebuild from clean checkout.

Cycles: **Discover → Teach → Operate** with rotating platform/release owners.

---

## 1. Dependency graph

### 1.1 Create-order (parents before children)

```text
AWS account + assigned Region (eu-west-1) + engineer credentials
        │
┌─────── Bootstrap stack (separate state) ─────────────────────┐
│  S3 bucket (encrypted, versioned, public access blocked)     │
│  State locking (DynamoDB or native lock as approved)         │
│  NEVER destroyed by workload stack                           │
└──────────────────────────┬───────────────────────────────────┘
                           │
┌─────── Workload root: infra/environments/lab ────────────────┐
│  providers.tf (pinned OpenTofu + hashicorp/aws)              │
│  backend → bootstrap bucket/key                              │
└──────────────────────────┬───────────────────────────────────┘
                           │
modules/network
  VPC devops-g5-vpc (10.0.0.0/16)
  public subnets AZ-1 + AZ-2
  private app subnets AZ-1 + AZ-2
  IGW + public route table
  NAT (lab choice) + EIP + private route table
        │
Shared IAM (platform)
  devops-g5-ecs-execution-role
  devops-g5-ecs-task-role
        │
Security groups
  devops-g5-alb-sg
  devops-g5-service-a-sg
  devops-g5-service-b-sg
  devops-g5-service-c-sg
        │
ECR (per service) + CloudWatch log groups (per service)
        │
modules/ecs-platform
  devops-g5-cluster
  Service Connect namespace group5.internal
        │
modules/alb
  devops-g5-alb (public subnets, ≥2 AZs)
  devops-g5-tg-service-a (target_type = ip, port 3001)
  listener :80 → target group
        │
modules/ecs-service (×3 instantiations)
  A: desired 2, private subnets, ALB attached, assign_public_ip = false
  B: desired 1, private subnets, no ALB, assign_public_ip = false
  C: desired 1, private subnets, no ALB, assign_public_ip = false
  circuit breaker + rollback ON · ECS Exec ON · awslogs ON
        │
Runtime proof → immutable SHA release (pipeline builds; IaC selects tag)
```

### 1.2 Destroy-order (children before parents)

```text
ECS services A/B/C
  → ALB / listener / target group
  → ECS cluster / Service Connect
  → ECR (empty images first) + log groups (if owned by workload)
  → security groups
  → IAM roles (if workload-owned)
  → NAT / EIP / subnets / IGW / VPC
Backend bootstrap stack: REMAINS (excluded from workload destroy)
```

### 1.3 Module dependency (repository shape)

```text
infra/
├── bootstrap/                 # state bucket + lock (separate state)
├── environments/lab/          # wires modules; team apply/destroy
├── modules/network/           # VPC, subnets, routes, egress
├── modules/alb/               # ALB, TG, listener
├── modules/ecs-platform/      # cluster, namespace, shared IAM patterns
├── modules/ecs-service/       # reusable: task def + service + logs wiring
└── tests/                     # architecture checks (≥6 rules as code)
```

One reusable `ecs-service` module; instantiate for A, B, and C.

---

## 2. Ownership map

Existing app ownership remains. For three-person teams, **platform** and **release** roles rotate each cycle.

| Owner type | Person (Group 5) | Owns |
|---|---|---|
| **Service A owner** | Mary | Service A ECR, module inputs, task definition, log group, security group, ECS service, **ALB registration**, release evidence for A |
| **Service B owner** | Warga | Service B ECR, module inputs, task definition, log group, security group, ECS service, release evidence for B |
| **Service C owner** | Sharon | Service C ECR, module inputs, task definition, log group, security group, ECS service, release evidence for C |
| **Platform owner** | Weekly rotation: Mary → Warga → Sharon | Backend, providers, VPC, subnets, routes, egress, ECS cluster, Service Connect namespace, ALB, shared IAM, IaC workflow |
| **Release owner** | Rotates each cycle | Plan summary, approval evidence, image SHA selection, runtime release proof, rollback evidence |

### Cycle behaviour

| Cycle | Operator | Coach |
|---|---|---|
| Discover | Platform owner of the week | Others observe / record scars |
| Teach | **Different** engineer from clean checkout | Cycle 1 operator coaches with **questions only** (no keyboard, no answers) |
| Operate | Rotated operator | Team observes; evidence decides |

**Rule:** no one takes over another engineer’s terminal during a cycle or demo.

```text
Owner types. Team observes. Operator narrates. Coach asks questions. Evidence decides.
```

### Application-release ownership (Gate 1 required)

| Step | Who | Tool |
|---|---|---|
| App change + tests | Service owner | GitHub Actions / local tests |
| Build & push **immutable Git SHA** image to ECR | Service owner / pipeline | CodeBuild `buildspecs/service-*.yml` |
| Declare which SHA is deployed | **Release owner** + service owner | IaC variable / `image_tag` input to `ecs-service` module |
| `tofu plan` / review / apply | Operator of the cycle | OpenTofu |
| Prove new SHA via ALB `/version` or `/health` | Release owner | Runtime evidence |
| Rollback | Release owner | Previous SHA in IaC → plan → apply |

**Pipeline builds and pushes SHA tags. IaC selects the deployed SHA.** Console image edits are not accepted.

---

## 3. CIDR and subnet-capacity table

### 3.1 Address plan (custom VPC — not the default VPC)

| Resource | Name | CIDR / size | AZ | Purpose |
|---|---|---|---|---|
| VPC | `devops-g5-vpc` | `10.0.0.0/16` | — | Greenfield boundary |
| Public subnet | `devops-g5-public-1a` | `10.0.0.0/24` | eu-west-1a | Internet-facing ALB ENI + NAT (lab) |
| Public subnet | `devops-g5-public-1b` | `10.0.1.0/24` | eu-west-1b | Internet-facing ALB ENI |
| Private app subnet | `devops-g5-private-1a` | `10.0.10.0/24` | eu-west-1a | Fargate tasks A/B/C |
| Private app subnet | `devops-g5-private-1b` | `10.0.11.0/24` | eu-west-1b | Fargate tasks A/B/C |

### 3.2 Capacity and rolling-deployment headroom

AWS reserves **5 IPs per subnet**. Usable ≈ total − 5 − other ENIs (NAT, VPC endpoints, ALB nodes share public subnet space).

| Subnet | Total IPs | Usable (−5) | Steady-state Fargate ENIs (lab) | Rolling headroom (200% surge) | Verdict |
|---|---|---|---|---|---|
| public-1a `/24` | 256 | ~251 | ALB node + NAT EIP path | ALB scale | OK |
| public-1b `/24` | 256 | ~251 | ALB node | ALB scale | OK |
| private-1a `/24` | 256 | ~251 | Share of A+B+C (desired 2+1+1=4 total across 2 AZs ≈ 2/AZ) | Up to ~2× during rolling (~4–6 ENIs/AZ peak) | **OK — large headroom** |
| private-1b `/24` | 256 | ~251 | Same | Same | **OK** |

**Rule of thumb used:** provision for peak tasks × 2 per AZ. With desired A=2, B=1, C=1 and circuit-breaker rolling deploys, `/24` private subnets are not the bottleneck.

**Placement rule:** Service A desired **2** must land across **two AZs** (prove in Operate). B and C desired **1** each.

---

## 4. Route-table and egress design

| Route table | Associated subnets | Destination | Target | Why |
|---|---|---|---|---|
| `devops-g5-rtb-public` | public-1a, public-1b | `10.0.0.0/16` | local | Intra-VPC |
| | | `0.0.0.0/0` | **Internet Gateway** | ALB client traffic in/out |
| `devops-g5-rtb-private` | private-1a, private-1b | `10.0.0.0/16` | local | ALB→tasks, Service Connect, SG-allowed hops |
| | | `0.0.0.0/0` | **NAT Gateway** (lab: one NAT in public-1a) | ECR pulls, CloudWatch, AWS APIs |

### Egress decision (lab)

| Option | Choice | Trade-off |
|---|---|---|
| NAT Gateway (1 AZ) | **Selected for lab** | Simple; costs hourly + GB; single-AZ egress SPOF accepted for mentorship |
| NAT per AZ | Deferred | Higher HA and cost |
| VPC endpoints only (ECR/S3/Logs) | Optional later | Cheaper pulls; no third-party egress |

**Fargate tasks:** `assign_public_ip = false` always. No public IP on tasks.

**ALB → task traffic** uses VPC **local** route (never NAT, never IGW).

---

## 5. Security-group matrix and traffic contract

### 5.1 Application ports

| Service | Container port | Discovery name |
|---|---|---|
| service-a | 3001 | `service-a` in `group5.internal` |
| service-b | 3002 | `service-b` |
| service-c | 3003 | `service-c` |

### 5.2 Allow / deny matrix (assignment contract)

| Source | Destination | Port | Result | Enforcement |
|---|---|---|---|---|
| Internet | ALB | 80 | **Allow** | `devops-g5-alb-sg` ingress `0.0.0.0/0:80` |
| ALB SG | Service A app port | 3001 | **Allow** | alb-sg → service-a-sg |
| Service A SG | Service B internal port | 3002 | **Allow** | a-sg → b-sg |
| Service B SG | Service C internal port | 3003 | **Allow** | b-sg → c-sg |
| Service C SG | Service A (callback) | 3001 | **Allow** | c-sg → a-sg (required by app) |
| Internet | Services A, B, or C directly | 3001–3003 | **Deny** | No SG rule; private subnets; no public IPs |
| Service A | Service C | 3003 | **Deny** | No SG rule |

Use **security-group references only**. Rejected: broad app-port ingress from `0.0.0.0/0`, task-IP allowlists, public task IPs.

### 5.3 Runtime acceptance (every cycle)

```text
Internet → ALB succeeds
ALB → A succeeds
A → B by service name succeeds
B → C by service name succeeds
Internet → A/B/C direct denied
A → C denied
```

---

## 6. Expected resource names and tags

### 6.1 Standard tags (every resource)

| Key | Value |
|---|---|
| `Project` | `devops-mentorship` |
| `Group` | `group-5` |
| `Owner` | `platform-owner` \| `service-a-owner` \| `service-b-owner` \| `service-c-owner` |
| `Environment` | `lab` |
| `Name` | resource-specific `devops-g5-…` |

### 6.2 Expected names

| Kind | Name |
|---|---|
| VPC | `devops-g5-vpc` |
| Subnets | `devops-g5-public-1a/1b`, `devops-g5-private-1a/1b` |
| NAT / EIP | `devops-g5-nat`, `devops-g5-nat-eip` |
| Route tables | `devops-g5-rtb-public`, `devops-g5-rtb-private` |
| SGs | `devops-g5-alb-sg`, `devops-g5-service-{a,b,c}-sg` |
| ECR | `devops-g5-service-{a,b,c}` |
| Log groups | `/ecs/devops-g5-service-{a,b,c}` |
| Cluster | `devops-g5-cluster` |
| Namespace | `group5.internal` |
| ALB / TG | `devops-g5-alb`, `devops-g5-tg-service-a` |
| Task family | `devops-g5-td-service-{a,b,c}` |
| ECS service | `devops-g5-svc-service-{a,b,c}` |
| IAM | `devops-g5-ecs-execution-role`, `devops-g5-ecs-task-role` |

Images: **immutable Git SHA tags only** — `latest` rejected by validation/tests.

---

## 7. Three predicted broken dependency edges

| # | Broken edge | User symptom | AWS evidence |
|---|---|---|---|
| 1 | **Private route missing NAT / NAT down** → no path to ECR | New tasks stuck; deploy fails | Stopped reason `CannotPullContainerError` / i/o timeout; private RT has no `0.0.0.0/0` → NAT; NAT not Available |
| 2 | **Missing alb-sg → service-a-sg :3001** | ALB 502/504; targets unhealthy | Target group unhealthy; SG inbound on A missing alb-sg; ECS tasks RUNNING but ALB cannot health-check |
| 3 | **Missing service-c-sg → service-a-sg :3001 (callback)** | `/greet-service-b` returns **504** `downstream_timeout` | A logs `request_failed` / `downstream_timeout`; C callback errors; Exec C→A:3001 fails; forward A→B→C may still look OK |

---

## 8. State-backend design

| Requirement | Design |
|---|---|
| Separate bootstrap stack | `infra/bootstrap/` creates backend only |
| S3 | Encrypted, versioned, **Block Public Access** on |
| Locking | Enabled (DynamoDB lock table or approved OpenTofu lock mechanism) |
| Separation | Backend state **≠** workload state; different key/prefix |
| Destroy | Workload `destroy` **must not** delete backend |
| Local state | **Not** team source of truth |
| Pinning | OpenTofu version + `hashicorp/aws` provider version pinned; lock file committed |
| Safety | No credentials, `*.tfstate`, plans, or secret tfvars in Git |

Console may **inspect** only — never create/repair IaC-managed resources.

---

## 9. Five architecture decision cards

For each: risk reduced · trade-off · Well-Architected pillar · evidence.

### Decision 1 — Two Availability Zones

| | |
|---|---|
| **Risk reduced** | Single-AZ failure takes down ALB or all Service A tasks |
| **Trade-off** | Double subnet/NAT-adjacent cost complexity; must size capacity per AZ |
| **Pillar** | Reliability |
| **Evidence** | ALB subnets in 2 AZs; Service A tasks placed in both private AZs; kill one AZ’s task → greet still works via remaining A |

### Decision 2 — Private Fargate tasks

| | |
|---|---|
| **Risk reduced** | Direct internet reachability to app ports; bypass of ALB |
| **Trade-off** | Need NAT or endpoints for pulls; slightly harder debugging |
| **Pillar** | Security |
| **Evidence** | Task ENIs show no public IP; laptop curl to task IP fails; ECR pull succeeds via private RT → NAT |

### Decision 3 — Security-group references instead of IP allowlists

| | |
|---|---|
| **Risk reduced** | Broken rules after every scale/deploy when task IPs churn |
| **Trade-off** | Must understand SG chaining; mis-ordered rules harder to spot in console |
| **Pillar** | Security |
| **Evidence** | SG rules show source = SG ID not CIDR (except ALB:80); scale A 2→3 without SG edits; A→C still denied |

### Decision 4 — Immutable image SHA

| | |
|---|---|
| **Risk reduced** | Silent drift from mutable `latest`; unreproducible rollbacks |
| **Trade-off** | IaC must be updated per release; more plan noise |
| **Pillar** | Operational Excellence / Reliability |
| **Evidence** | Config rejects `latest`; `/version` or health shows deployed SHA; rollback = previous SHA in IaC |

### Decision 5 — Remote, versioned, locked state

| | |
|---|---|
| **Risk reduced** | Two engineers overwrite state; lost state; no audit of prior configs |
| **Trade-off** | Bootstrap complexity; must protect backend from destroy |
| **Pillar** | Operational Excellence / Reliability |
| **Evidence** | Second `tofu apply` from another laptop waits on lock; S3 versioning shows prior state; workload destroy leaves backend intact |

---

## 10. Required implementation checklist (post–Gate 1)

| Requirement | Design choice |
|---|---|
| Custom VPC ≥ 2 AZs | `10.0.0.0/16` + 2 public + 2 private |
| Fargate `awsvpc`, no public IPs | `assign_public_ip = false` |
| ALB ≥ 2 public subnets | public-1a + public-1b |
| Target group `ip` | `devops-g5-tg-service-a` |
| Only Service A on ALB | B/C internal only |
| Desired counts | A=**2**, B=**1**, C=**1** |
| Service Connect | `group5.internal` |
| Name-based calls | A→B, B→C; no task IPs |
| Logs, Exec, circuit breaker + rollback | Enabled on services |
| Immutable SHA tags | Validation + tests reject `latest` |
| Naming + tags | `devops-g5-*` + Project/Group/Owner/Environment |

### Architecture rules as code (implement ≥6 in `infra/tests` / validations)

Reject or detect: public task IP; ALB &lt; 2 AZs; TG type ≠ `ip`; app port open to `0.0.0.0/0`; ALB cannot reach A; A cannot reach B; B cannot reach C; A can reach C; missing tags; wrong Region; image tag `latest`.

---

## 11. One-line summary

**Group 5 will greenfield A→B→C on OpenTofu in a custom 2-AZ VPC (public ALB + private Fargate, SG-referenced contracts, SHA releases, remote locked state) — design first, then Discover / Teach / Operate with rotating owners.**

**No workload resources are created until this design is peer-reviewed.** Then: bootstrap backend → first workload plan → apply.
