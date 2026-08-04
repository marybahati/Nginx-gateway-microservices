const assert = require("node:assert/strict");
const http = require("node:http");
const { spawn } = require("node:child_process");
const path = require("node:path");
const test = require("node:test");

const SERVICE_NAME = "service-b";
const PORT = 3102;
const PORT2 = 3112;
const PORT3 = 3113;
const PORT4 = 3114;

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

function spawnService(env = {}) {
  const serviceDir = path.resolve(__dirname, "..");
  return spawn(process.execPath, ["index.js"], {
    cwd: serviceDir,
    env: { ...process.env, BIND_HOST: "127.0.0.1", PORT: String(PORT), OTEL_SDK_DISABLED: "true", NODE_PATH: path.join(serviceDir, "node_modules"), ...env },
    stdio: ["ignore", "pipe", "pipe"],
  });
}

test("health endpoint returns clean service JSON", async (t) => {
  const child = spawnService();
  t.after(() => child.kill("SIGTERM"));

  const response = await waitForHealth(`http://127.0.0.1:${PORT}/health?shallow=1`);
  assert.match(response.headers.get("content-type"), /application\/json/);
  const body = await response.json();
  assert.equal(body.service, SERVICE_NAME);
  assert.equal(body.status, "ok");
  assert.ok(body.dependencies);
});

test("greet returns 500 when service-c is unreachable", async (t) => {
  const child = spawnService({ PORT: String(PORT2), SERVICE_C_URL: "http://127.0.0.1:3199" });
  t.after(() => child.kill("SIGTERM"));

  await waitForHealth(`http://127.0.0.1:${PORT2}/health`);
  const response = await fetch(`http://127.0.0.1:${PORT2}/greet`, {
    headers: { "X-Request-ID": "test-fail-b-001" },
  });
  assert.equal(response.status, 500);
  const body = await response.json();
  assert.equal(body.status, "error");
});

test("greet forwards request to service-c and returns forwarded status", async (t) => {
  const fake = http.createServer((_req, res) => {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "processed" }));
  });
  await new Promise((r) => fake.listen(3198, "127.0.0.1", r));
  t.after(() => fake.close());

  const child = spawnService({ PORT: String(PORT3), SERVICE_C_URL: "http://127.0.0.1:3198" });
  t.after(() => child.kill("SIGTERM"));

  await waitForHealth(`http://127.0.0.1:${PORT3}/health`);
  const response = await fetch(`http://127.0.0.1:${PORT3}/greet`, {
    headers: { "X-Request-ID": "test-greet-ok-001" },
  });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.status, "forwarded");
  assert.equal(body.target, "service-c");
  assert.equal(body.request_id, "test-greet-ok-001");
});

test("version endpoint returns service name and version fields", async (t) => {
  const child = spawnService({ PORT: String(PORT4) });
  t.after(() => child.kill("SIGTERM"));

  await waitForHealth(`http://127.0.0.1:${PORT4}/health`);
  const response = await fetch(`http://127.0.0.1:${PORT4}/version`);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.service, SERVICE_NAME);
  assert.ok(body.version, "version field must be present");
  assert.equal(body.status, "ok");
});
