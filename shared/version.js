function getServiceVersion() {
  return (
    process.env.SERVICE_VERSION ||
    process.env.GIT_SHA ||
    process.env.IMAGE_TAG ||
    "dev"
  );
}

module.exports = { getServiceVersion };
