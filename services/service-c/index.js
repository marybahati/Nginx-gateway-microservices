const express = require("express");
const { v4: uuidv4 } = require("uuid");
const { log } = require("../../shared/logger");
const { initTracing } = require("../../shared/tracing");
const { createServiceMetrics } = require("../../shared/metrics");
const { createObservabilityMiddleware } = require("../../shared/middleware");
const { buildHealthResponse } = require("../../shared/health");

initTracing("service-c");

const PORT = Number(process.env.PORT) || 3003;
const BIND_HOST = process.env.BIND_HOST || "127.0.0.1";
const SERVICE_NAME = "service-c";
const SERVICE_A_CALLBACK_URL =
  process.env.SERVICE_A_CALLBACK_URL || "http://service-a:3001";
const SERVICE_A_HEALTH_URL =
  process.env.SERVICE_A_HEALTH_URL || "http://service-a:3001/health";
const SLOW_DELAY_MS = Number(process.env.SLOW_DELAY_MS) || 1500;

const metrics = createServiceMetrics(SERVICE_NAME);
const app = express();
app.use(express.json());
app.use(createObservabilityMiddleware(SERVICE_NAME, metrics));

function getRequestId(req) {
  return req.headers["x-request-id"] || uuidv4();
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

app.get("/health", async (req, res) => {
  const shallow = req.query.shallow === "1";
  const health = await buildHealthResponse(SERVICE_NAME, {}, { shallow });
  res.status(200).json(health);
});

app.get("/metrics", async (_req, res) => {
  res.set("Content-Type", metrics.register.contentType);
  res.end(await metrics.register.metrics());
});

app.get("/greet-c", async (req, res) => {
  const requestId = getRequestId(req);
  log({
    service: SERVICE_NAME,
    level: "info",
    event: "request_received",
    request_id: requestId,
    method: "GET",
    path: "/greet-c",
  });

  try {
    const callbackBody = {
      request_id: requestId,
      source_service: "service-c",
      message: "Greeting processed",
      timestamp: new Date().toISOString(),
    };

    const callbackResponse = await fetch(`${SERVICE_A_CALLBACK_URL}/greeting-rcvd`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Request-ID": requestId,
      },
      body: JSON.stringify(callbackBody),
    });

    if (!callbackResponse.ok) {
      throw new Error(`callback_error_${callbackResponse.status}`);
    }

    log({
      service: SERVICE_NAME,
      level: "info",
      event: "callback_sent",
      request_id: requestId,
      path: "/greet-c",
      target: "service-a",
      status: callbackResponse.status,
    });

    res.status(200).json({
      request_id: requestId,
      status: "processed",
      callback_sent: true,
    });
  } catch (error) {
    log({
      service: SERVICE_NAME,
      level: "error",
      event: "request_failed",
      request_id: requestId,
      path: "/greet-c",
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

// Lab-only endpoint for latency testing.
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
