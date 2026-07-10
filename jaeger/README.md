# Jaeger in this stack

Jaeger is the distributed tracing backend for the MELT lab.

## What it solves

When a request crosses nginx → service-a → service-b → service-c, Prometheus can show that latency increased, but Jaeger shows **which hop** was slow or failed.

## What data it collects

- Trace spans for incoming HTTP requests
- Outgoing HTTP calls between services (via OpenTelemetry auto-instrumentation)
- Span attributes: service name, route, duration, status, errors

## Where to view it

Open **http://localhost:16686** after `docker compose up`.

## How to debug with it

1. Send a successful request:
   ```bash
   curl -fsS http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: demo-trace-1"
   ```
2. In Jaeger UI, choose **service-a** (or service-b / service-c).
3. Click **Find Traces** and open the latest trace.
4. Confirm the span chain: `service-a` → `service-b` → `service-c` → callback to `service-a`.
5. Trigger a failure:
   ```bash
   curl -fsS http://localhost:8080/service-a/lab/fail -H "X-Request-ID: demo-fail-1"
   ```
6. Find the trace and inspect the failed span on `service-c`.

## Configuration

Services export OTLP HTTP traces to `http://jaeger:4318/v1/traces` inside the Docker network.

No separate OpenTelemetry Collector is required for this lab setup.
