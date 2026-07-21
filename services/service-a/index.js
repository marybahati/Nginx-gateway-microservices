const express = require("express");
const { v4: uuidv4 } = require("uuid");
const { log } = require("../../shared/logger");
const { initTracing } = require("../../shared/tracing");
const { createServiceMetrics } = require("../../shared/metrics");
const { createObservabilityMiddleware } = require("../../shared/middleware");
const { buildHealthResponse } = require("../../shared/health");
const { getServiceVersion } = require("../../shared/version");

initTracing("service-a");

const PORT = Number(process.env.PORT) || 3001;
const BIND_HOST = process.env.BIND_HOST || "127.0.0.1";
const SERVICE_NAME = "service-a";
const SERVICE_VERSION = getServiceVersion();
const SERVICE_B_URL = process.env.SERVICE_B_URL || "http://service-b:3002";
const SERVICE_B_HEALTH_URL =
  process.env.SERVICE_B_HEALTH_URL || "http://service-b:3002/health";
const CALLBACK_TIMEOUT_MS = Number(process.env.CALLBACK_TIMEOUT_MS) || 30000;

const metrics = createServiceMetrics(SERVICE_NAME);
const app = express();
app.use(express.json());
app.use(createObservabilityMiddleware(SERVICE_NAME, metrics));

const pendingCallbacks = new Map();

function getRequestId(req) {
  return req.headers["x-request-id"] || uuidv4();
}

function waitForCallback(requestId) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pendingCallbacks.delete(requestId);
      reject(new Error("downstream_timeout"));
    }, CALLBACK_TIMEOUT_MS);

    pendingCallbacks.set(requestId, (payload) => {
      clearTimeout(timeout);
      pendingCallbacks.delete(requestId);
      resolve(payload);
    });
  });
}

app.get("/health", async (req, res) => {
  const shallow = req.query.shallow === "1";
  const health = await buildHealthResponse(
    SERVICE_NAME,
    {
      "service-b": SERVICE_B_HEALTH_URL,
    },
    { shallow }
  );
  res.status(200).json({
    ...health,
    version: SERVICE_VERSION,
    status: health.status === "ok" ? "ok" : health.status,
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

app.get("/greet-service-b", async (req, res) => {
  const requestId = getRequestId(req);
  log({
    service: SERVICE_NAME,
    level: "info",
    event: "request_received",
    request_id: requestId,
    method: "GET",
    path: "/greet-service-b",
  });

  const callbackPromise = waitForCallback(requestId);

  try {
    const response = await fetch(`${SERVICE_B_URL}/greet`, {
      headers: { "X-Request-ID": requestId },
    });

    if (!response.ok) {
      throw new Error(`service_b_error_${response.status}`);
    }

    log({
      service: SERVICE_NAME,
      level: "info",
      event: "request_forwarded",
      request_id: requestId,
      path: "/greet-service-b",
      target: "service-b",
      status: response.status,
    });

    await callbackPromise;

    res.status(200).json({
      request_id: requestId,
      status: "success",
      message: "Request completed successfully",
    });
  } catch (error) {
    const status = error.message === "downstream_timeout" ? 504 : 500;
    log({
      service: SERVICE_NAME,
      level: "error",
      event: "request_failed",
      request_id: requestId,
      path: "/greet-service-b",
      status,
      error: error.message,
    });
    res.status(status).json({
      request_id: requestId,
      status: "error",
      message: error.message,
    });
  }
});

// Lab-only routes exposed through the gateway for load tests and demos.
app.get("/lab/slow", async (req, res) => {
  const requestId = getRequestId(req);
  try {
    const response = await fetch(`${SERVICE_B_URL}/slow`, {
      headers: { "X-Request-ID": requestId },
    });
    const body = await response.json();
    res.status(response.status).json(body);
  } catch (error) {
    res.status(500).json({ request_id: requestId, status: "error", message: error.message });
  }
});

// Lab-only: failure path via service-b (must not call service-c — AWS traffic contract).
app.get("/lab/fail", async (req, res) => {
  const requestId = getRequestId(req);
  try {
    const response = await fetch(`${SERVICE_B_URL}/fail`, {
      headers: { "X-Request-ID": requestId },
    });
    const body = await response.json();
    res.status(response.status).json(body);
  } catch (error) {
    res.status(500).json({ request_id: requestId, status: "error", message: error.message });
  }
});

app.post("/greeting-rcvd", (req, res) => {
  const requestId = req.body.request_id || getRequestId(req);
  const sourceService = req.body.source_service || "service-c";

  log({
    service: SERVICE_NAME,
    level: "info",
    event: "callback_received",
    request_id: requestId,
    path: "/greeting-rcvd",
    source_service: sourceService,
    status: 200,
  });

  const resolve = pendingCallbacks.get(requestId);
  if (resolve) {
    resolve(req.body);
  }

  res.status(200).json({ status: "received" });
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
