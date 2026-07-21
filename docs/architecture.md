# Architecture

This document explains how application traffic and telemetry move through the stack.

## Service architecture

```
Client / load test
        |
        v
   nginx :8080  (only public app entry)
        |
        v
   service-a :3001  (orchestrator)
        |
        v
   service-b :3002  (relay)
        |
        v
   service-c :3003  (processor + callback)
        |
        +---- callback POST /greeting-rcvd ----> service-a
```

| Component | Port (container) | Host access | Role |
|---|---|---|---|
| nginx | 8080 | `localhost:8080` | Public gateway |
| service-a | 3001 | via nginx only | Starts request chain, waits for callback |
| service-b | 3002 | internal | Forwards to service-c |
| service-c | 3003 | internal | Processes and callbacks to service-a |
| prometheus | 9090 | `localhost:9090` | Metrics storage and alerts |
| grafana | 3000 | `localhost:3030` | Operating view |
| jaeger | 16686 | `localhost:16686` | Trace UI |
| loki | 3100 | `http://localhost:3100/ready` | Log storage (API only — no browser UI; view logs in Grafana) |
| promtail | 9080 | internal | Ships container logs to Loki |

## Request flow

1. Client calls `GET /service-a/greet-service-b` through nginx.
2. nginx forwards to `service-a` with `X-Request-ID`.
3. `service-a` calls `service-b /greet`.
4. `service-b` calls `service-c /greet-c`.
5. `service-c` POSTs callback to `service-a /greeting-rcvd`.
6. `service-a` completes the original HTTP response.

Lab-only routes exposed through the gateway:

- `GET /service-a/lab/slow` → `service-b /slow`
- `GET /service-a/lab/fail` → `service-b /fail`

## Telemetry flow

```
Application services
  |-- /metrics --------> Prometheus scrape
  |-- OTLP traces ----> Jaeger (4318)
  |-- JSON stdout ----> Docker logs ----> Promtail ----> Loki
  |
  +-- Grafana reads Prometheus + Loki
```

## Metrics collection flow

1. Each service exposes `/metrics` using `prom-client`.
2. Prometheus scrapes by Compose DNS name:
   - `service-a:3001`
   - `service-b:3002`
   - `service-c:3003`
3. Metrics are stored on the `prometheus-data` volume.
4. Grafana dashboard panels query Prometheus for:
   - service up/down
   - request rate
   - error rate
   - p95 latency
   - firing alerts

## Tracing flow

1. Each service starts OpenTelemetry on boot.
2. Auto-instrumentation creates spans for incoming and outgoing HTTP.
3. Trace context propagates across internal `fetch()` calls.
4. Spans export to Jaeger OTLP HTTP endpoint `http://jaeger:4318/v1/traces`.
5. Engineers search traces in Jaeger UI by service name.

## Logging flow

1. Services emit one JSON object per line to stdout.
2. Logs include `timestamp`, `level`, `service`, `request_id`, `trace_id`, `duration_ms` where applicable.
3. Minimum access path: `docker compose logs service-a`
4. Recommended path:
   - Promtail discovers containers via Docker socket
   - Promtail parses JSON fields and pushes to Loki
   - Grafana Explore/dashboard shows logs correlated by `request_id` / `trace_id`

## Alerting flow

1. `alert-rules.yml` defines three rules:
   - **ServiceDown** — scrape target unavailable
   - **HighErrorRate** — `rate(http_errors_total[2m]) > 0.1`
   - **HighLatencyP95** — p95 latency above 500ms
2. Prometheus evaluates rules every 15s.
3. View firing alerts at `http://localhost:9090/alerts` and in Grafana.

## Operational events documented

| Event | How it appears |
|---|---|
| Load test started | `load-test` JSON log with `event=load_test_started` |
| Load test completed | `load-test` JSON log with `event=load_test_completed` |
| Failure triggered | `lab_fail_endpoint_triggered` in service-c logs |
| Alert fired | Prometheus `ALERTS{alertstate="firing"}` metric |
| Service recovered | `docker compose start service-b` + health returns `ok` |

## Known limitations

- Grafana admin password is `admin` for lab use only.
- No Alertmanager notification channel is configured; alerts are viewed in Prometheus/Grafana.
- Promtail requires Docker socket access and works on Docker Desktop (macOS/Windows) and Linux Docker Engine.
- Trace volume during stress tests can make Jaeger UI noisy; filter by service or time range.
- `service-a /health` returns HTTP 200 with `"status": "degraded"` when dependencies are unreachable (body reflects dependency state; use Prometheus `up` for hard down).
