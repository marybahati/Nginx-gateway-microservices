const express = require("express");
const { log } = require("../../shared/logger");

const PORT = Number(process.env.PORT) || 3003;
const BIND_HOST = process.env.BIND_HOST || "127.0.0.1";
const SERVICE_NAME = "service-c";
const SERVICE_A_CALLBACK_URL =
  process.env.SERVICE_A_CALLBACK_URL || "http://service-a.internal:3001";

const app = express();

function getRequestId(req) {
  return req.headers["x-request-id"] || "unknown";
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

app.get("/greet-c", async (req, res) => {
  const requestId = getRequestId(req);
  log({
    service: SERVICE_NAME,
    event: "request_received",
    request_id: requestId,
    method: "GET",
    path: "/greet-c",
    status: 200,
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

app.listen(PORT, BIND_HOST);
