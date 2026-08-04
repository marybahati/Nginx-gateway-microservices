/**
 * Resolve the base URL that service-c must use to reach the originating
 * service-a task. With Service A desiredCount > 1, Service Connect DNS for
 * "service-a" load-balances and in-memory pendingCallbacks never see the POST.
 */

async function resolveTaskPrivateIp() {
  const metadataUri = process.env.ECS_CONTAINER_METADATA_URI_V4;
  if (!metadataUri) {
    return null;
  }

  try {
    const response = await fetch(`${metadataUri}/task`);
    if (!response.ok) {
      return null;
    }
    const task = await response.json();
    for (const container of task.Containers || []) {
      for (const network of container.Networks || []) {
        const ip = (network.IPv4Addresses || [])[0];
        if (ip) {
          return ip;
        }
      }
    }
  } catch (_error) {
    return null;
  }

  return null;
}

async function resolveCallbackBaseUrl(port) {
  if (process.env.CALLBACK_BASE_URL) {
    return process.env.CALLBACK_BASE_URL.replace(/\/$/, "");
  }

  const taskIp = await resolveTaskPrivateIp();
  if (taskIp) {
    return `http://${taskIp}:${port}`;
  }

  return `http://127.0.0.1:${port}`;
}

function isAllowedCallbackUrl(url, fallbackBase) {
  if (!url || typeof url !== "string") {
    return false;
  }

  let parsed;
  try {
    parsed = new URL(url);
  } catch (_error) {
    return false;
  }

  if (parsed.protocol !== "http:") {
    return false;
  }

  const host = parsed.hostname;
  if (host === "service-a" || host === "127.0.0.1" || host === "localhost") {
    return true;
  }

  // Private VPC ranges used by the lab (and common RFC1918).
  if (
    /^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(host) ||
    /^192\.168\.\d{1,3}\.\d{1,3}$/.test(host) ||
    /^172\.(1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3}$/.test(host)
  ) {
    return true;
  }

  if (fallbackBase) {
    try {
      return new URL(fallbackBase).hostname === host;
    } catch (_error) {
      return false;
    }
  }

  return false;
}

module.exports = {
  resolveCallbackBaseUrl,
  isAllowedCallbackUrl,
};
