const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const path = require("node:path");
const test = require("node:test");

const SERVICE_NAME = "service-b";
const PORT = 3102;

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForHealth(url) {
  let lastError;

  for (let attempt = 0; attempt < 30; attempt += 1) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        return response;
      }
      lastError = new Error(`Health check returned ${response.status}`);
    } catch (error) {
      lastError = error;
    }

    await wait(100);
  }

  throw lastError;
}

test("health endpoint returns clean service JSON", async (t) => {
  const serviceDir = path.resolve(__dirname, "..");
  const child = spawn(process.execPath, ["index.js"], {
    cwd: serviceDir,
    env: {
      ...process.env,
      BIND_HOST: "127.0.0.1",
      PORT: String(PORT),
      NODE_PATH: path.join(serviceDir, "node_modules"),
      OTEL_SDK_DISABLED: "true",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  t.after(() => {
    child.kill("SIGTERM");
  });

  const response = await waitForHealth(`http://127.0.0.1:${PORT}/health?shallow=1`);
  assert.match(response.headers.get("content-type"), /application\/json/);

  const body = await response.json();
  assert.equal(body.service, SERVICE_NAME);
  assert.equal(body.status, "ok");
  assert.ok(body.dependencies);
});
