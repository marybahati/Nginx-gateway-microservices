const client = require("prom-client");

const register = new client.Registry();
client.collectDefaultMetrics({ register });

function createServiceMetrics(serviceName) {
  const serviceUp = new client.Gauge({
    name: "service_up",
    help: "1 if the service process is running",
    labelNames: ["service"],
    registers: [register],
  });

  const httpRequestsTotal = new client.Counter({
    name: "http_requests_total",
    help: "Total HTTP requests handled by the service",
    labelNames: ["service", "method", "route", "status_code"],
    registers: [register],
  });

  const httpErrorsTotal = new client.Counter({
    name: "http_errors_total",
    help: "Total HTTP responses with status code >= 500",
    labelNames: ["service", "method", "route", "status_code"],
    registers: [register],
  });

  const httpRequestDurationSeconds = new client.Histogram({
    name: "http_request_duration_seconds",
    help: "HTTP request duration in seconds",
    labelNames: ["service", "method", "route", "status_code"],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5],
    registers: [register],
  });

  serviceUp.set({ service: serviceName }, 1);

  return {
    register,
    serviceUp,
    httpRequestsTotal,
    httpErrorsTotal,
    httpRequestDurationSeconds,
  };
}

module.exports = { createServiceMetrics, register };
