/**
 * wait-for-deps.mjs — Block Service A startup until service-b health responds.
 * Does not wait on service-c (Amazon Web Services traffic contract forbids service-a → service-c).
 */

const deps = [
  process.env.SERVICE_B_HEALTH_URL || "http://service-b:3002/health",
];

const maxAttempts = Number(process.env.WAIT_FOR_DEPS_ATTEMPTS || 30);
const sleepSec = Number(process.env.WAIT_FOR_DEPS_INTERVAL || 2);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitFor(url) {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(2000) });
      if (response.ok) {
        console.log(`Ready: ${url}`);
        return;
      }
    } catch {
      // retry
    }

    if (attempt >= maxAttempts) {
      console.error(`Dependency not ready after ${maxAttempts} attempts: ${url}`);
      process.exit(1);
    }

    console.error(`Waiting for ${url} (attempt ${attempt}/${maxAttempts})...`);
    await sleep(sleepSec * 1000);
  }
}

for (const url of deps) {
  await waitFor(url);
}
