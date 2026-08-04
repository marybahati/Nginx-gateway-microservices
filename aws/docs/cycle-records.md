# Cycle records — Discover / Teach / Operate

Fill these during each cycle. Evidence decides. Mistakes that are detected, explained, and corrected safely do not reduce the score.

---

## Cycle 1 — Discover

**Purpose:** expose wrong assumptions and improve the code.  
**Operator:** _______________  **Date:** _______________

```text
Empty → init → fmt/validate → tests → plan review → apply → release → runtime proof → destroy review → destroy
```

### Full change brief (first create)

```text
Expected additions:
Expected replacements:
User impact:
Security impact:
Cost impact:
Recovery approach:
Reason to proceed:
```

### Instructive failures (2–3 max)

| # | Hypothesis | What happened | Evidence | Correction |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

### Owner contributions (one disproved hypothesis each)

| Owner | Disproved hypothesis / design correction |
|---|---|
| Service A | |
| Service B | |
| Service C | |
| Platform / Release | |

### Runtime proof checklist

- [ ] Internet → ALB
- [ ] ALB → A
- [ ] A → B by name
- [ ] B → C by name
- [ ] Internet → A/B/C direct denied
- [ ] A → C denied
- [ ] Tasks RUNNING; A across 2 AZs; no public IPs
- [ ] Deployed SHA visible; logs exist; ECS Exec works
- [ ] Follow-up plan clean after apply

### Closing question

> What did AWS or Terraform do differently from what you expected?

**Answer:**

---

## Cycle 2 — Teach

**Purpose:** understanding transfers to another engineer.  
**Operator (different from Cycle 1):** _______________  
**Coach (Cycle 1 operator — questions only):** _______________  
**Date:** _______________

### Clean checkout rules

- Independent AWS authentication
- No copied state, `.terraform/`, uncommitted tfvars, or hidden setup notes
- Coach may ask: What does the plan tell you? Which dependency is missing? What evidence separates IAM from networking? Which output feeds this input? What would be replaced?
- Coach may **not** give commands, touch the keyboard, or reveal answers

### Outcome

| Item | Notes |
|---|---|
| Rebuild succeeded? | |
| Hidden guidance needed? | |
| Surprises vs Cycle 1 | |
| Runtime proof complete? | |

---

## Cycle 3 — Operate

**Purpose:** live operational competence (rehearsal for final demo).  
**Operator:** _______________  **Date:** _______________

```text
Empty → reviewed plan → apply → runtime proof → visible release → one safe infra change
→ clean follow-up plan → reviewed destroy → cost sweep
```

### Release evidence

| Step | Evidence link / note |
|---|---|
| SHA built/pushed | |
| `image_tag_*` updated in IaC | |
| Plan reviewed | |
| New task-def revision | |
| SHA via ALB | |
| Safe infra change + clean plan | |

### Destroy + cost sweep

| Check | Result |
|---|---|
| Destroy plan reviewed | |
| Workload gone | |
| Backend/state lock remain | |
| Console `devops-g5-*` untouched | |
| No leftover NAT/ALB/Fargate `-iac` | |

### Red lines (must not happen)

- Credentials/state committed
- Work outside `eu-west-1`
- Console repair of IaC resources
- Unreviewed destructive replacement
- State lock bypassed
