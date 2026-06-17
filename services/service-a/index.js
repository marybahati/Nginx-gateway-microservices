const express = require("express");
const { v4: uuidv4 } = require("uuid");
const { log } = require("../../shared/logger");

const PORT = Number(process.env.PORT) || 3001;
const SERVICE_NAME = "service-a";
const SERVICE_B_URL = process.env.SERVICE_B_URL || "http://service-b.internal:3002";
const CALLBACK_TIMEOUT_MS = Number(process.env.CALLBACK_TIMEOUT_MS) || 30000;

const app = express();
app.use(express.json());

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

app.get("/health", (req, res) => {
  const requestId = getRequestId(req);
  log({
    service: SERVICE_NAME,
    event: "request_received",
    request_id: requestId,
    method: "GET",
    path: "/health",
    status: 200,
  });
  res.status(200).json({
    service: SERVICE_NAME,
    status: "healthy",
    port: PORT,
    message: `Hello ${SERVICE_NAME} listening on ${PORT}`,
  });
});

app.get("/greet-service-b", async (req, res) => {
  const requestId = getRequestId(req);
  log({
    service: SERVICE_NAME,
    event: "request_received",
    request_id: requestId,
    method: "GET",
    path: "/greet-service-b",
    status: 200,
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
      event: "request_forwarded",
      request_id: requestId,
      path: "/greet-service-b",
      target: "service-b",
      status: response.status,
    });

    await callbackPromise;

    log({
      service: SERVICE_NAME,
      event: "request_completed",
      request_id: requestId,
      path: "/greet-service-b",
      status: 200,
    });

    res.status(200).json({
      request_id: requestId,
      status: "success",
      message: "Request completed successfully",
    });
  } catch (error) {
    const status = error.message === "downstream_timeout" ? 504 : 500;
    log({
      service: SERVICE_NAME,
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

app.post("/greeting-rcvd", (req, res) => {
  const requestId = req.body.request_id || getRequestId(req);
  const sourceService = req.body.source_service || "service-c";

  log({
    service: SERVICE_NAME,
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
    event: "route_not_found",
    request_id: requestId,
    path: req.path,
    status: 404,
  });
  res.status(404).json({ error: "Not Found" });
});

app.listen(PORT);
