const assert = require("node:assert/strict");
const { spawn, createServer } = require("node:net");
const { createServer: createHttpServer } = require("node:http");
const { spawn: spawnProc } = require("node:child_process");
const path = require("node:path");
const test = require("node:test");

const SERVICE_NAME = "service-a";
const PORT = 3101;
const STUB_B_PORT = 3102;
const STUB_C_PORT = 3103;

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForHealth(url) {
  let lastError;
  for (let attempt = 0; attempt < 30; attempt += 1) {
    try {
      const response = await fetch(url);
      if (response.ok) return response;
      lastError = new Error(`Health check returned ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    await wait(100);
  }
  throw lastError;
}

function startStubB(stubBPort, stubCPort) {
  const http = require("node:http");
  const server = http.createServer(async (req, res) => {
    if (req.url === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "healthy" }));
      return;
    }
    if (req.url === "/greet") {
      // Forward to stub C
      const requestId = req.headers["x-request-id"] || "stub-id";
      await fetch(`http://127.0.0.1:${stubCPort}/greet-c`, {
        headers: { "X-Request-ID": requestId },
      }).catch(() => {});
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "forwarded" }));
      return;
    }
    res.writeHead(404);
    res.end();
  });
  return new Promise((resolve) => server.listen(stubBPort, "127.0.0.1", () => resolve(server)));
}

function startStubC(stubCPort, serviceAPort) {
  const http = require("node:http");
  const server = http.createServer(async (req, res) => {
    if (req.url === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "healthy" }));
      return;
    }
    if (req.url === "/greet-c") {
      const requestId = req.headers["x-request-id"] || "stub-id";
      // Callback to service A
      await fetch(`http://127.0.0.1:${serviceAPort}/greeting-rcvd`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ request_id: requestId, source_service: "service-c", message: "stub", timestamp: new Date().toISOString() }),
      }).catch(() => {});
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "processed" }));
      return;
    }
    res.writeHead(404);
    res.end();
  });
  return new Promise((resolve) => server.listen(stubCPort, "127.0.0.1", () => resolve(server)));
}

function spawnService(env = {}) {
  const serviceDir = path.resolve(__dirname, "..");
  return spawnProc(process.execPath, ["index.js"], {
    cwd: serviceDir,
    env: {
      ...process.env,
      BIND_HOST: "127.0.0.1",
      PORT: String(PORT),
      NODE_PATH: path.join(serviceDir, "node_modules"),
      OTEL_SDK_DISABLED: "true",
      ...env
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
}

test("health endpoint returns clean service JSON", async (t) => {
  const child = spawnService({
    SERVICE_B_URL: `http://127.0.0.1:${STUB_B_PORT}`,
  });
  t.after(() => child.kill("SIGTERM"));

  const response = await waitForHealth(`http://127.0.0.1:${PORT}/health?shallow=1`);
  assert.match(response.headers.get("content-type"), /application\/json/);
  const body = await response.json();
  assert.equal(body.service, SERVICE_NAME);
  assert.equal(body.status, "ok");
  assert.ok(body.dependencies);
});

test("greet-service-b completes the A→B→C chain", async (t) => {
  const stubB = await startStubB(STUB_B_PORT, STUB_C_PORT);
  const stubC = await startStubC(STUB_C_PORT, PORT);
  const child = spawnService({
    SERVICE_B_URL: `http://127.0.0.1:${STUB_B_PORT}`,
  });
  t.after(() => {
    child.kill("SIGTERM");
    stubB.close();
    stubC.close();
  });

  await waitForHealth(`http://127.0.0.1:${PORT}/health`);
  const response = await fetch(`http://127.0.0.1:${PORT}/greet-service-b`, {
    headers: { "X-Request-ID": "test-chain-001" },
  });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.status, "success");
  assert.equal(body.request_id, "test-chain-001");
});

test("greet-service-b returns 500 when service-b is unreachable", async (t) => {
  // No stub B started — port 3199 nothing listening
  const child = spawnService({
    SERVICE_B_URL: "http://127.0.0.1:3199",
  });
  t.after(() => child.kill("SIGTERM"));

  await waitForHealth(`http://127.0.0.1:${PORT}/health`);
  const response = await fetch(`http://127.0.0.1:${PORT}/greet-service-b`, {
    headers: { "X-Request-ID": "test-fail-001" },
  });
  assert.equal(response.status, 500);
  const body = await response.json();
  assert.equal(body.status, "error");
});
