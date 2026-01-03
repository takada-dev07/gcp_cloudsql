locals {
  location = var.region

  sql_instance_name = "${var.name_prefix}-sql"
  run_sa_account_id = "${var.name_prefix}-run"

  db_password_secret_id  = "${var.name_prefix}-db-password"
  database_url_secret_id = "${var.name_prefix}-database-url"
}

resource "google_project_service" "services" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_artifact_registry_repository" "repo" {
  depends_on = [google_project_service.services]

  project       = var.project_id
  location      = local.location
  repository_id = var.artifact_registry_repo_id
  format        = "DOCKER"

  description = "Docker images for Cloud Run"
}

# Allow Cloud Run service agent to pull images from Artifact Registry.
# (Without this, deployment can fail with permission errors on image pull.)
resource "google_project_iam_member" "cloud_run_service_agent_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:service-${data.google_project.current.number}@serverless-robot-prod.iam.gserviceaccount.com"
}

resource "random_password" "db_password" {
  length  = 24
  special = false
}

resource "google_sql_database_instance" "db" {
  depends_on = [google_project_service.services]

  project          = var.project_id
  name             = local.sql_instance_name
  database_version = "POSTGRES_16"
  region           = local.location

  deletion_protection = false

  settings {
    tier              = var.cloud_sql_tier
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_SSD"

    backup_configuration {
      enabled = true
    }

    ip_configuration {
      ipv4_enabled = true
      require_ssl  = false
    }
  }
}

resource "google_sql_database" "app" {
  # Destroy ordering:
  # - PostgreSQL user (role) can't be dropped if it still owns objects in the DB.
  # - Deleting the DB first removes those objects, so drop DB before user.
  # Terraform destroys resources in reverse dependency order, so we make the DB
  # depend on the user to enforce: destroy DB -> destroy user.
  depends_on = [google_sql_user.app]

  project  = var.project_id
  name     = var.db_name
  instance = google_sql_database_instance.db.name
}

resource "google_sql_user" "app" {
  project  = var.project_id
  name     = var.db_user
  instance = google_sql_database_instance.db.name
  password = random_password.db_password.result
}

resource "google_secret_manager_secret" "db_password" {
  depends_on = [google_project_service.services]

  project   = var.project_id
  secret_id = local.db_password_secret_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

resource "google_secret_manager_secret" "database_url" {
  depends_on = [google_project_service.services]

  project   = var.project_id
  secret_id = local.database_url_secret_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "database_url" {
  secret = google_secret_manager_secret.database_url.id

  # NOTE: Cloud Run does NOT expand env vars inside other env values.
  # Store the fully-rendered DATABASE_URL as a secret to keep the app unchanged (STEP3 assumption).
  secret_data = "postgresql+asyncpg://${var.db_user}:${random_password.db_password.result}@/${var.db_name}?host=/cloudsql/${google_sql_database_instance.db.connection_name}"
}

resource "google_service_account" "run" {
  depends_on = [google_project_service.services]

  project      = var.project_id
  account_id   = local.run_sa_account_id
  display_name = "Cloud Run runtime service account for ${var.cloud_run_service_name}"
}

resource "google_project_iam_member" "run_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.run.email}"
}

resource "google_project_iam_member" "run_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.run.email}"
}

resource "google_cloud_run_v2_service" "service" {
  provider = google-beta

  depends_on = [
    google_project_service.services,
    google_project_iam_member.cloud_run_service_agent_artifact_reader,
    google_project_iam_member.run_cloudsql_client,
    google_project_iam_member.run_secret_accessor,
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_version.database_url,
  ]

  project  = var.project_id
  name     = var.cloud_run_service_name
  location = local.location

  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.run.email

    containers {
      image = var.container_image

      ports {
        container_port = 8080
      }

      env {
        name  = "ENV"
        value = "prod"
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.db.connection_name]
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  provider = google-beta

  project  = var.project_id
  location = google_cloud_run_v2_service.service.location
  name     = google_cloud_run_v2_service.service.name

  role   = "roles/run.invoker"
  member = "allUsers"
}


