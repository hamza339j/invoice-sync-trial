resource "google_monitoring_notification_channel" "email" {
  display_name = "invoice-sync failure alerts"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
  depends_on = [google_project_service.enabled]
}

resource "google_monitoring_alert_policy" "job_failed" {
  display_name = "Cloud Run Job ${var.job_name} failed"
  combiner     = "OR"

  conditions {
    display_name = "${var.job_name} failed executions > 0"
    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"cloud_run_job\"",
        "resource.labels.job_name = \"${var.job_name}\"",
        "metric.type = \"run.googleapis.com/job/completed_execution_count\"",
        "metric.labels.result = \"failed\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  alert_strategy {
    auto_close = "1800s"
  }
}
