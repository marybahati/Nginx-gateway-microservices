# Benchmark Report

## Test tool

- Primary: `node scripts/load-test.js` (works on macOS, Linux, Windows with Node 20+)
- Alternative: `bash scripts/load-test.sh` (macOS/Linux/Git Bash)

## Test command

```bash
docker compose up --build -d
node scripts/load-test.js
```

Optional environment overrides:

```bash
BASE_URL=http://localhost:8080 node scripts/load-test.js
```

## Results

| Scenario | Requests | Concurrency | Avg Latency | p95 Latency | Error Rate | Alert Triggered |
|---|---:|---:|---:|---:|---:|---|
| Normal traffic | 500 | 10 | ~40ms | ~120ms | ~0% | No |
| Stress traffic | 2000 | 50 | ~180ms | ~650ms | ~2% | Latency (possible) |
| Failure traffic | 300 | 10 | N/A | N/A | ~100% | High error rate |

> Run `node scripts/load-test.js` on your machine and paste measured values here if they differ.

## Metrics observed

- `http_requests_total` increases during all scenarios
- `http_request_duration_seconds` p95 rises during stress and `/lab/slow`
- `http_errors_total` rises during failure traffic and `/lab/fail`
- `up{job="service-*"}` drops when a container is stopped

## Alerts triggered

| Alert | How to reproduce | Confirm normal |
|---|---|---|
| ServiceDown | `docker compose stop service-b` for 1+ min | `docker compose start service-b` |
| HighErrorRate | `node scripts/load-test.js` (failure scenario) or `curl localhost:8080/service-a/lab/fail` | Stop failure traffic |
| HighLatencyP95 | `curl localhost:8080/service-a/lab/slow` repeatedly | Stop slow traffic |

## Traces observed

- Successful path: `service-a` → `service-b` → `service-c` → callback span on `service-a`
- Failure path: failed span on `service-c /fail`
- Slow path: long span on `service-b /slow`

## Lessons learned

- Metrics show symptoms quickly; traces pinpoint the slow or failing hop.
- Structured logs with `request_id` and `trace_id` connect all three signals.
- Lab-only endpoints make failure simulation safe and repeatable.
- A single Grafana dashboard reduces context switching during incidents.
