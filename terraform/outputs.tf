output "project_id" {
  value = var.project_id
}

output "job_name" {
  value = google_cloud_run_v2_job.invoice_sync.name
}

output "runtime_service_account_email" {
  value = google_service_account.runtime.email
}

output "deployer_service_account_email" {
  value = google_service_account.deployer.email
}

output "secret_id" {
  value = google_secret_manager_secret.db_password.secret_id
}

output "vpc_network" {
  value = google_compute_network.vpc.id
}

output "vpc_subnet" {
  value = google_compute_subnetwork.subnet.id
}

output "workload_identity_pool_id" {
  value = google_iam_workload_identity_pool.github.name
}

output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "alert_policy_id" {
  value = google_monitoring_alert_policy.job_failed.id
}

output "notification_channel_id" {
  value = google_monitoring_notification_channel.email.id
}

output "github_actions_variables" {
  value = {
    GCP_PROJECT_ID = var.project_id
    WIF_PROVIDER   = google_iam_workload_identity_pool_provider.github.name
    DEPLOYER_SA    = google_service_account.deployer.email
    JOB_NAME       = google_cloud_run_v2_job.invoice_sync.name
  }
}
