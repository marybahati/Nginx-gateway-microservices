variable "name_prefix" { type = string }
variable "aws_region" { type = string }
variable "alb_arn_suffix" { type = string }
variable "target_group_arn_suffix" { type = string }
variable "cluster_name" { type = string }
variable "service_a_name" { type = string }
variable "service_a_log_group" { type = string }
variable "alert_email" {
  type        = string
  default     = ""
  description = "Optional email for SNS alarm notifications."
}
variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  alb_dimension = {
    LoadBalancer = var.alb_arn_suffix
  }
  tg_dimension = {
    TargetGroup  = var.target_group_arn_suffix
    LoadBalancer = var.alb_arn_suffix
  }
  ecs_dimension = {
    ClusterName = var.cluster_name
    ServiceName = var.service_a_name
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-reliability-alerts"
  tags = merge(var.tags, {
    Name  = "${var.name_prefix}-reliability-alerts"
    Owner = "platform-owner"
  })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Availability — customer-facing 5xx from Service A target group.
resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  alarm_name          = "${var.name_prefix}-alb-target-5xx"
  alarm_description   = "WHAT: ALB target 5xx rate is elevated for Service A. WHY: Users see failed greet requests (504/502). WHERE: Check ECS service-a tasks, CloudWatch logs /ecs/${var.name_prefix}-service-a, then service-b/c chain."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 5
  treat_missing_data  = "notBreaching"

  metric_name = "HTTPCode_Target_5XX_Count"
  namespace   = "AWS/ApplicationELB"
  period      = 60
  statistic   = "Sum"
  dimensions  = local.tg_dimension

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = merge(var.tags, { Name = "${var.name_prefix}-alb-target-5xx", Owner = "platform-owner" })
}

# Availability — unhealthy targets behind the ALB.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.name_prefix}-alb-unhealthy-hosts"
  alarm_description   = "WHAT: One or more Service A targets are unhealthy. WHY: Greet journey cannot complete for some requests. WHERE: ECS console → service-a tasks; verify /health?shallow=1 and target group health."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 1
  treat_missing_data  = "notBreaching"

  metric_name = "UnHealthyHostCount"
  namespace   = "AWS/ApplicationELB"
  period      = 60
  statistic   = "Maximum"
  dimensions  = local.tg_dimension

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = merge(var.tags, { Name = "${var.name_prefix}-alb-unhealthy-hosts", Owner = "platform-owner" })
}

# Latency — p95 target response time (greet journey proxy).
resource "aws_cloudwatch_metric_alarm" "alb_latency_p95" {
  alarm_name          = "${var.name_prefix}-alb-latency-p95"
  alarm_description   = "WHAT: p95 ALB target response time exceeds 2s for 5 minutes. WHY: Users experience slow greet responses before timeout. WHERE: Trace CloudWatch logs for downstream_timeout; check service-b/c latency and CPU."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 2
  treat_missing_data  = "notBreaching"

  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p95"
  dimensions          = local.tg_dimension

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = merge(var.tags, { Name = "${var.name_prefix}-alb-latency-p95", Owner = "platform-owner" })
}

# Saturation — Service A CPU pressure.
resource "aws_cloudwatch_metric_alarm" "service_a_cpu" {
  alarm_name          = "${var.name_prefix}-service-a-cpu-high"
  alarm_description   = "WHAT: Service A average CPU above 80% for 10 minutes. WHY: Approaching capacity; greet latency and timeouts may follow. WHERE: ECS service-a → metrics; consider scale-out or investigate hot loops."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 80
  treat_missing_data  = "notBreaching"

  metric_name = "CPUUtilization"
  namespace   = "AWS/ECS"
  period      = 300
  statistic   = "Average"
  dimensions  = local.ecs_dimension

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = merge(var.tags, { Name = "${var.name_prefix}-service-a-cpu-high", Owner = "platform-owner" })
}

# Correctness — log-derived greet failures on Service A.
resource "aws_cloudwatch_log_metric_filter" "greet_failures" {
  name           = "${var.name_prefix}-greet-failures"
  log_group_name = var.service_a_log_group
  pattern        = "{ $.event = \"request_failed\" && $.path = \"/greet-service-b\" }"

  metric_transformation {
    name      = "GreetRequestFailures"
    namespace = "${var.name_prefix}/Application"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "greet_failures" {
  alarm_name          = "${var.name_prefix}-greet-failures"
  alarm_description   = "WHAT: Service A logged greet request failures. WHY: User journey broken even if ALB health is green (callback/LB issues). WHERE: Logs /ecs/${var.name_prefix}-service-a filter request_failed; see golden-scar runbook."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 3
  treat_missing_data  = "notBreaching"

  metric_name = "GreetRequestFailures"
  namespace   = "${var.name_prefix}/Application"
  period      = 300
  statistic   = "Sum"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = merge(var.tags, { Name = "${var.name_prefix}-greet-failures", Owner = "platform-owner" })
}

resource "aws_cloudwatch_dashboard" "reliability" {
  dashboard_name = "${var.name_prefix}-reliability"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Greet journey — ALB target requests & 5xx"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", label = "Requests" }],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", ".", ".", { stat = "Sum", label = "5xx", yAxis = "right" }],
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Greet journey — p95 latency (ALB target)"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix, { stat = "p95" }],
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Service A saturation"
          region = var.aws_region
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_a_name],
            [".", "MemoryUtilization", ".", ".", ".", "."],
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Greet failures (log metric)"
          region = var.aws_region
          metrics = [
            ["${var.name_prefix}/Application", "GreetRequestFailures"],
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
    ]
  })
}

output "sns_topic_arn" { value = aws_sns_topic.alerts.arn }
output "dashboard_name" { value = aws_cloudwatch_dashboard.reliability.dashboard_name }
output "alarm_names" {
  value = [
    aws_cloudwatch_metric_alarm.alb_target_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name,
    aws_cloudwatch_metric_alarm.alb_latency_p95.alarm_name,
    aws_cloudwatch_metric_alarm.service_a_cpu.alarm_name,
    aws_cloudwatch_metric_alarm.greet_failures.alarm_name,
  ]
}
