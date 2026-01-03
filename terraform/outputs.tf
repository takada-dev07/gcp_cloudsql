output "artifact_registry_repo" {
  description = "Artifact Registry repository resource name"
  value       = google_artifact_registry_repository.repo.name
}

output "image_repository" {
  description = "Artifact Registry image name (you can append :tag)"
  value       = "${local.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repo.repository_id}/${var.cloud_run_service_name}"
}

output "cloudsql_connection_name" {
  description = "Cloud SQL instance connection name (project:region:instance)"
  value       = google_sql_database_instance.db.connection_name
}

output "cloud_run_service_name" {
  description = "Cloud Run service name"
  value       = google_cloud_run_v2_service.service.name
}

output "cloud_run_url" {
  description = "Cloud Run service URL"
  value       = google_cloud_run_v2_service.service.uri
}

output "db_password_secret_id" {
  description = "Secret Manager secret id for DB password"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "database_url_secret_id" {
  description = "Secret Manager secret id for DATABASE_URL"
  value       = google_secret_manager_secret.database_url.secret_id
}


