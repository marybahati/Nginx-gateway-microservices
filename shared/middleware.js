const { randomUUID } = require("node:crypto");
const { log, getTraceId } = require("./logger");

function getRequestId(req) {
  return req.headers["x-request-id"] || randomUUID();
}

function normalizeRoute(req) {
  if (req.route?.path) {
    return req.route.path;
  }
  return req.path;
}

function createObservabilityMiddleware(serviceName, metrics) {
  return function observabilityMiddleware(req, res, next) {
    const started = process.hrtime.bigint();
    const requestId = getRequestId(req);

    res.on("finish", () => {
      const durationMs = Number(process.hrtime.bigint() - started) / 1e6;
      const route = normalizeRoute(req);
      const statusCode = String(res.statusCode);
      const labels = {
        service: serviceName,
        method: req.method,
        route,
        status_code: statusCode,
      };

      metrics.httpRequestsTotal.inc(labels);
      metrics.httpRequestDurationSeconds.observe(labels, durationMs / 1000);
      if (res.statusCode >= 500) {
        metrics.httpErrorsTotal.inc(labels);
      }

      log({
        service: serviceName,
        event: res.statusCode >= 500 ? "request_failed" : "request_completed",
        request_id: requestId,
        trace_id: getTraceId(),
        method: req.method,
        path: route,
        status: res.statusCode,
        duration_ms: Math.round(durationMs),
      });
    });

    next();
  };
}

module.exports = { createObservabilityMiddleware, getTraceId, getRequestId };
