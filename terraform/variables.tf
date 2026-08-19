variable "project_id" {
  type        = string
  description = "Sandbox project to deploy into."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "github_repo" {
  type        = string
  description = "OWNER/REPO allowed to authenticate via WIF."
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "alert_email" {
  type        = string
  description = "Recipient for the Job failure alert."
}

variable "job_name" {
  type    = string
  default = "invoice-sync"
}

variable "job_image" {
  type    = string
  default = "us-docker.pkg.dev/cloudrun/container/job:latest"
}
