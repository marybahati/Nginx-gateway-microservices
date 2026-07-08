async function checkDependency(name, url) {
  try {
    const checkUrl = url.includes("?") ? `${url}&shallow=1` : `${url}?shallow=1`;
    const response = await fetch(checkUrl, { signal: AbortSignal.timeout(2000) });
    return response.ok ? "ok" : "degraded";
  } catch {
    return "unreachable";
  }
}

async function buildHealthResponse(serviceName, dependencies = {}, options = {}) {
  if (options.shallow) {
    return {
      service: serviceName,
      status: "ok",
      dependencies: {},
    };
  }
  const dependencyEntries = await Promise.all(
    Object.entries(dependencies).map(async ([name, url]) => [
      name,
      await checkDependency(name, url),
    ])
  );

  const dependencyStatus = Object.fromEntries(dependencyEntries);
  const hasUnreachable = Object.values(dependencyStatus).includes("unreachable");
  const hasDegraded = Object.values(dependencyStatus).includes("degraded");

  return {
    service: serviceName,
    status: hasUnreachable || hasDegraded ? "degraded" : "ok",
    dependencies: dependencyStatus,
  };
}

module.exports = { buildHealthResponse };
