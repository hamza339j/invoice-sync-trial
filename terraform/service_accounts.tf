resource "google_service_account" "runtime" {
  account_id   = "invoice-sync-runtime"
  display_name = "invoice-sync Job runtime"
}

resource "google_service_account" "deployer" {
  account_id   = "gh-deployer"
  display_name = "GitHub Actions deployer"
}

resource "google_project_iam_member" "deployer_run" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_service_account_iam_member" "deployer_actas_runtime" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "invoice-sync"
  format        = "DOCKER"
  depends_on    = [google_project_service.enabled]
}

resource "google_artifact_registry_repository_iam_member" "deployer_push" {
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.deployer.email}"
}
