const express = require("express");
const { v4: uuidv4 } = require("uuid");
const { log } = require("../../shared/logger");
const { initTracing } = require("../../shared/tracing");
const { createServiceMetrics } = require("../../shared/metrics");
const { createObservabilityMiddleware } = require("../../shared/middleware");
const { buildHealthResponse } = require("../../shared/health");
const { getServiceVersion } = require("../../shared/version");

initTracing("service-b");

const PORT = Number(process.env.PORT) || 3002;
const BIND_HOST = process.env.BIND_HOST || "127.0.0.1";
const SERVICE_NAME = "service-b";
const SERVICE_VERSION = getServiceVersion();
const SERVICE_C_URL = process.env.SERVICE_C_URL || "http://service-c:3003";
const SERVICE_C_HEALTH_URL =
  process.env.SERVICE_C_HEALTH_URL || "http://service-c:3003/health";
const SLOW_DELAY_MS = Number(process.env.SLOW_DELAY_MS) || 2000;

const metrics = createServiceMetrics(SERVICE_NAME);
const app = express();
app.use(createObservabilityMiddleware(SERVICE_NAME, metrics));

function getRequestId(req) {
  return req.headers["x-request-id"] || uuidv4();
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

app.get("/health", async (req, res) => {
  const shallow = req.query.shallow === "1";
  const health = await buildHealthResponse(
    SERVICE_NAME,
    {
      "service-c": SERVICE_C_HEALTH_URL,
    },
    { shallow }
  );
  res.status(200).json({
    ...health,
    version: SERVICE_VERSION,
  });
});

app.get("/version", (_req, res) => {
  res.status(200).json({
    service: SERVICE_NAME,
    version: SERVICE_VERSION,
    status: "ok",
  });
});

app.get("/metrics", async (_req, res) => {
  res.set("Content-Type", metrics.register.contentType);
  res.end(await metrics.register.metrics());
});

app.get("/greet", async (req, res) => {
  const requestId = getRequestId(req);
  log({
    service: SERVICE_NAME,
    level: "info",
    event: "request_received",
    request_id: requestId,
    method: "GET",
    path: "/greet",
  });

  try {
    const response = await fetch(`${SERVICE_C_URL}/greet-c`, {
      headers: { "X-Request-ID": requestId },
    });

    if (!response.ok) {
      throw new Error(`service_c_error_${response.status}`);
    }

    res.status(200).json({
      request_id: requestId,
      status: "forwarded",
      target: "service-c",
    });
  } catch (error) {
    log({
      service: SERVICE_NAME,
      level: "error",
      event: "request_failed",
      request_id: requestId,
      path: "/greet",
      status: 500,
      error: error.message,
    });
    res.status(500).json({
      request_id: requestId,
      status: "error",
      message: error.message,
    });
  }
});

// Lab-only endpoint for latency and alert testing.
app.get("/slow", async (req, res) => {
  const requestId = getRequestId(req);
  log({
    service: SERVICE_NAME,
    level: "warn",
    event: "lab_slow_endpoint_triggered",
    request_id: requestId,
    path: "/slow",
    delay_ms: SLOW_DELAY_MS,
  });
  await sleep(SLOW_DELAY_MS);
  res.status(200).json({
    request_id: requestId,
    status: "slow",
    message: "Lab-only slow endpoint completed",
    delay_ms: SLOW_DELAY_MS,
  });
});

// Lab-only endpoint for error-rate testing.
app.get("/fail", (req, res) => {
  const requestId = getRequestId(req);
  log({
    service: SERVICE_NAME,
    level: "error",
    event: "lab_fail_endpoint_triggered",
    request_id: requestId,
    path: "/fail",
    error: "controlled failure",
  });
  res.status(500).json({
    request_id: requestId,
    status: "error",
    message: "Lab-only controlled failure",
  });
});

app.use((req, res) => {
  const requestId = getRequestId(req);
  log({
    service: SERVICE_NAME,
    level: "warn",
    event: "route_not_found",
    request_id: requestId,
    path: req.path,
    status: 404,
  });
  res.status(404).json({ error: "Not Found" });
});

app.listen(PORT, BIND_HOST);
