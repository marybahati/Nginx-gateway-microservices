#!/usr/bin/env node
/**
 * Repeatable load test for the MELT lab.
 * Works on macOS, Linux, and Windows (Git Bash / WSL).
 *
 * Usage:
 *   node scripts/load-test.js
 *   BASE_URL=http://localhost:8080 node scripts/load-test.js
 */

const BASE_URL = process.env.BASE_URL || "http://localhost:8080";

const scenarios = [
  { name: "normal", path: "/service-a/greet-service-b", requests: 500, concurrency: 10 },
  { name: "stress", path: "/service-a/greet-service-b", requests: 2000, concurrency: 50 },
  { name: "failure", path: "/service-a/lab/fail", requests: 300, concurrency: 10 },
];

function logEvent(event) {
  console.log(
    JSON.stringify({
      timestamp: new Date().toISOString(),
      level: "info",
      service: "load-test",
      event,
    })
  );
}

async function runRequest(url, requestId) {
  const started = Date.now();
  try {
    const response = await fetch(url, {
      headers: { "X-Request-ID": requestId },
    });
    return {
      ok: response.ok,
      status: response.status,
      durationMs: Date.now() - started,
    };
  } catch (error) {
    return {
      ok: false,
      status: 0,
      durationMs: Date.now() - started,
      error: error.message,
    };
  }
}

async function runScenario({ name, path, requests, concurrency }) {
  logEvent("load_test_started");
  console.log(`\n=== ${name} ===`);
  console.log(`URL: ${BASE_URL}${path}`);
  console.log(`Requests: ${requests}, Concurrency: ${concurrency}`);

  const url = `${BASE_URL}${path}`;
  const results = [];
  let inFlight = 0;
  let index = 0;

  await new Promise((resolve) => {
    const launch = () => {
      while (inFlight < concurrency && index < requests) {
        const current = index++;
        inFlight += 1;
        const requestId = `load-${name}-${current}-${Date.now()}`;
        runRequest(url, requestId).then((result) => {
          results.push(result);
          inFlight -= 1;
          if (results.length === requests) {
            resolve();
            return;
          }
          launch();
        });
      }
    };
    launch();
  });

  const durations = results.map((r) => r.durationMs).sort((a, b) => a - b);
  const errors = results.filter((r) => !r.ok || r.status >= 500).length;
  const avg = durations.reduce((sum, value) => sum + value, 0) / durations.length;
  const p95 = durations[Math.floor(durations.length * 0.95) - 1] || 0;

  console.log(`Avg latency: ${avg.toFixed(1)}ms`);
  console.log(`p95 latency: ${p95}ms`);
  console.log(`Error rate: ${((errors / results.length) * 100).toFixed(1)}%`);
  logEvent("load_test_completed");
}

async function main() {
  console.log("MELT load test (Node.js)");
  for (const scenario of scenarios) {
    await runScenario(scenario);
  }
  console.log("\nDone. Check Grafana, Prometheus alerts, Jaeger, and Loki.");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
