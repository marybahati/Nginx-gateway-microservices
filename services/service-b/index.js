const express = require("express");
const { log } = require("../../shared/logger");

const PORT = Number(process.env.PORT) || 3002;
const SERVICE_NAME = "service-b";
const SERVICE_C_URL = process.env.SERVICE_C_URL || "http://service-c.internal:3003";

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

app.get("/greet", async (req, res) => {
  const requestId = getRequestId(req);
  log({
    service: SERVICE_NAME,
    event: "request_received",
    request_id: requestId,
    method: "GET",
    path: "/greet",
    status: 200,
  });

  try {
    const response = await fetch(`${SERVICE_C_URL}/greet-c`, {
      headers: { "X-Request-ID": requestId },
    });

    if (!response.ok) {
      throw new Error(`service_c_error_${response.status}`);
    }

    log({
      service: SERVICE_NAME,
      event: "request_forwarded",
      request_id: requestId,
      path: "/greet",
      target: "service-c",
      status: response.status,
    });

    res.status(200).json({
      request_id: requestId,
      status: "forwarded",
      target: "service-c",
    });
  } catch (error) {
    log({
      service: SERVICE_NAME,
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
