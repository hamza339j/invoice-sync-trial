resource "google_cloud_run_v2_job" "invoice_sync" {
  name                = var.job_name
  location            = var.region
  deletion_protection = false

  template {
    template {
      service_account = google_service_account.runtime.email

      vpc_access {
        egress = "ALL_TRAFFIC"
        network_interfaces {
          network    = google_compute_network.vpc.id
          subnetwork = google_compute_subnetwork.subnet.id
        }
      }

      containers {
        image = var.job_image
        env {
          name = "DB_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.db_password.secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].template[0].containers[0].image]
  }

  depends_on = [
    google_secret_manager_secret_iam_member.runtime_accessor,
    google_project_service.enabled,
  ]
}
