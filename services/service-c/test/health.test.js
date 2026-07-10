const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const path = require("node:path");
const test = require("node:test");

const SERVICE_NAME = "service-c";
const PORT = 3103;
const PORT2 = 3113;

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
    env: { ...process.env, BIND_HOST: "127.0.0.1", PORT: String(PORT), OTEL_SDK_DISABLED: "true", ...env },
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

test("greet-c returns 500 when service-a callback is unreachable", async (t) => {
  const child = spawnService({ PORT: String(PORT2), SERVICE_A_CALLBACK_URL: "http://127.0.0.1:3199" });
  t.after(() => child.kill("SIGTERM"));

  await waitForHealth(`http://127.0.0.1:${PORT2}/health`);
  const response = await fetch(`http://127.0.0.1:${PORT2}/greet-c`, {
    headers: { "X-Request-ID": "test-fail-c-001" },
  });
  assert.equal(response.status, 500);
  const body = await response.json();
  assert.equal(body.status, "error");
});
