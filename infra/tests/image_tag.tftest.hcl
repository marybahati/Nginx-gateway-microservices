# Architecture rules as code — run from infra/environments/lab after init:
#   terraform test
#
# These unit-style tests validate module contracts without a live apply.

run "rejects_latest_image_tag" {
  command = plan

  variables {
    image_tag = "latest"
  }

  expect_failures = [
    var.image_tag,
  ]
}
