const { trace, context } = require("@opentelemetry/api");

function resolveLevel(entry) {
  if (entry.level) {
    return entry.level;
  }
  if (entry.error || (entry.status && entry.status >= 500)) {
    return "error";
  }
  if (entry.event === "request_failed") {
    return "error";
  }
  return "info";
}

function getTraceId() {
  const span = trace.getSpan(context.active());
  if (!span) {
    return undefined;
  }
  return span.spanContext().traceId;
}

function log(entry) {
  const logEntry = {
    timestamp: new Date().toISOString(),
    level: resolveLevel(entry),
    trace_id: entry.trace_id || getTraceId(),
    ...entry,
  };
  console.log(JSON.stringify(logEntry));
}

module.exports = { log, getTraceId };
