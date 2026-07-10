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

Measured on 2026-07-10 against the full stack (`docker compose up --build -d`) via `node scripts/load-test.js`:

| Scenario | Requests | Concurrency | Avg Latency | p95 Latency | Error Rate | Alert Triggered |
|---|---:|---:|---:|---:|---:|---|
| Normal traffic | 500 | 10 | 164.6ms | 237ms | 0.0% | No |
| Stress traffic | 2000 | 50 | 595.6ms | 835ms | 0.0% | No (burst too short — see below) |
| Failure traffic | 300 | 10 | 65.1ms | 81ms | 100.0% | No (burst too short — see below) |

The `load-test.js` failure scenario fires 300 requests in ~2 seconds. That is not enough to trip `HighErrorRate`, because Prometheus `rate()` needs at least two scrape samples showing the counter at different values within the window (scrape interval is 15s), and the `for: 2m` clause requires the condition to hold continuously. A separate **sustained** run below did trigger it.

## Sustained runs (used to actually confirm alert firing)

| Alert | Reproduction | Result |
|---|---|---|
| `ServiceDown` | `docker compose stop service-b` | `up{job="service-b"}` dropped to `0`; rule transitioned `inactive` → `firing`. `service-a /health` reported `"status":"degraded","service-b":"unreachable"`; `GET /greet-service-b` returned `500 fetch failed`. Recovered to `firing` → `inactive` and `200` OK within seconds of `docker compose start service-b`. |
| `HighErrorRate` | Continuous `curl .../lab/fail` for ~40s (looped, not single burst) | `sum by (service) (rate(http_errors_total[2m]))` rose to ~0.58/s on service-a and service-c; rule went `inactive` → `pending` → `firing` after the `for: 2m` window elapsed; cleared back to `inactive` once failure traffic stopped. |
| `HighLatencyP95` | Continuous `curl .../lab/slow` for ~140s | p95 latency (`histogram_quantile(0.95, ...)`) rose to ~4.8s on service-a and service-b (threshold 0.5s); rule transitioned `inactive` → `firing`. |

## Metrics observed

- `http_requests_total` increased from ~0 to 11,068+ across the load test scenarios
- `http_errors_total` increased to 600 (300 each on service-a and service-c) after the failure scenario, and kept climbing under sustained `/lab/fail` traffic
- `http_request_duration_seconds` p95 rose from ~0.24s (normal) to ~4.8s under sustained `/lab/slow` traffic
- `up{job="service-b"}` dropped to `0` immediately after `docker compose stop service-b` and returned to `1` after restart

## Alerts triggered

All three alerts were confirmed to actually transition to `firing` in Prometheus (`http://localhost:9090/alerts` / `/api/v1/rules`), not just defined as rules:

| Alert | How to reproduce | Confirm normal |
|---|---|---|
| ServiceDown | `docker compose stop service-b` for 1+ min | `docker compose start service-b` |
| HighErrorRate | Sustained `curl localhost:8080/service-a/lab/fail` loop for 2+ min (a single quick burst is not enough — see note above) | Stop failure traffic and wait ~2 min |
| HighLatencyP95 | Sustained `curl localhost:8080/service-a/lab/slow` loop for 2+ min | Stop slow traffic and wait ~2 min |

## Traces observed

- Successful path: confirmed in Jaeger — one trace with 5 spans spanning `service-a` → `service-b` → `service-c` plus the callback span back to `service-a`
- Failure path: confirmed — `service-c /fail` span tagged `error=true`, `http.status_code=500`, propagated up through `service-a`'s span
- Slow path: long-duration span on `service-b /slow` matching the elevated `http_request_duration_seconds` observed in Prometheus

## Lessons learned

- Metrics show symptoms quickly; traces pinpoint the slow or failing hop.
- Structured logs with `request_id` and `trace_id` connect all three signals.
- Lab-only endpoints make failure simulation safe and repeatable.
- A single Grafana dashboard reduces context switching during incidents.
- Prometheus `rate()` + a `for:` clause both need *sustained* signal, not a single fast burst — a 300-request failure burst finishing in ~2 seconds does not trip `HighErrorRate`, because the counter jumps directly from its pre-burst value to its post-burst value inside one scrape interval with no intermediate sample. Demoing an alert firing requires looping the failure/slow endpoint for at least the alert's `for:` duration.
