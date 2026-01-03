variable "project_id" {
  type        = string
  description = "GCP project id"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "asia-northeast1"
}

variable "name_prefix" {
  type        = string
  description = "Resource name prefix (lowercase, numbers, hyphens recommended)"
  default     = "fastapi-app"
}

variable "cloud_run_service_name" {
  type        = string
  description = "Cloud Run service name"
  default     = "fastapi-app"
}

variable "artifact_registry_repo_id" {
  type        = string
  description = "Artifact Registry repository id"
  default     = "fastapi-app"
}

variable "container_image" {
  type        = string
  description = "Container image to deploy to Cloud Run. First apply can use a public dummy image."
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "db_name" {
  type        = string
  description = "Database name"
  default     = "app"
}

variable "db_user" {
  type        = string
  description = "Database user name"
  default     = "app"
}

variable "cloud_sql_tier" {
  type        = string
  description = "Cloud SQL machine tier (learning small size)"
  default     = "db-f1-micro"
}


