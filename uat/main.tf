locals {
	kpmg-project-info = {
		project_number = "123456"
		project_id = "project_name"
		region = "europe-west3"
	}
}

# Enable services
resource "google_project_service" "all" {
    for_each                   = var.gcp_service_list
    project                    = locals.kpmg-project-info.project_number
    service                    = each.key
    disable_on_destroy 		   = false
}

# Set permissions
resource "google_project_iam_member" "allbuild" {
    for_each   = var.build_roles_list
    project    = locals.kpmg-project-info.project_number
    role       = each.key
    member     = "serviceAccount:${local.sabuild}"
    depends_on = [google_project_service.all]
}

# Create networking for SQL instance
resource "google_compute_global_address" "google_managed_services_vpn_connector" {
    name          = "google-managed-services-vpn-connector"
    purpose       = "VPC_PEERING"
    address_type  = "INTERNAL"
    prefix_length = 16
    network       = local.defaultnetwork
    project       = locals.kpmg-project-info.project_id
    depends_on    = [google_project_service.all]
}
resource "google_service_networking_connection" "vpcpeerings" {
    network                 = local.defaultnetwork
    service                 = "servicenetworking.googleapis.com"
    reserved_peering_ranges = [google_compute_global_address.google_managed_services_vpn_connector.name]
}

# Create VPC access connector 
resource "google_vpc_access_connector" "connector" {
    provider      = google-beta
    project       = locals.kpmg-project-info.project_id
    name          = "vpc-connector"
    ip_cidr_range = "10.8.0.0/28"
    network       = "default"
    region        = locals.kpmg-project-info.region
    depends_on    = [google_compute_global_address.google_managed_services_vpn_connector, google_project_service.all]
}

# Create Redis Server
resource "google_redis_instance" "todo_cache" {
    authorized_network      = local.defaultnetwork
    connect_mode            = "DIRECT_PEERING"
    location_id             = var.zone
    memory_size_gb          = 1
    name                    = "${var.basename}-cache"
    project                 = locals.kpmg-project-info.project_id
    redis_version           = "REDIS_6_X"
    region                  = locals.kpmg-project-info.region
    reserved_ip_range       = "10.137.125.88/29"
    tier                    = "BASIC"
    transit_encryption_mode = "DISABLED"
    depends_on              = [google_project_service.all]
}

# Create SQL server
resource "google_sql_database_instance" "todo_database" {
    name="${var.basename}-db-${random_id.id.hex}"
    database_version = "MYSQL_5_7"
    region           = locals.kpmg-project-info.region
    project          = locals.kpmg-project-info.project_id
    settings {
        tier                  = "db-g1-small"
        disk_autoresize       = true
        disk_autoresize_limit = 0
        disk_size             = 10
        disk_type             = "PD_SSD"
        ip_configuration {
            ipv4_enabled    = false
            private_network = local.defaultnetwork
        }
        location_preference {
            zone = var.zone
        }
    }
    deletion_protection = false
    depends_on = [
        google_project_service.all,
        google_service_networking_connection.vpcpeerings
    ]
    # This handles loading the schema after the database installs.
    provisioner "local-exec" {
        working_dir = "${path.module}/code/database"
        command     = "./load_schema.sh ${var.project_id} ${google_sql_database_instance.todo_database.name}"
    }
}

# Create Artifact Registry repository
resource "google_artifact_registry_repository" "todo_app" {
    provider      = google-beta
    format        = "DOCKER"
    location      = locals.kpmg-project-info.region
    project       = locals.kpmg-project-info.project_id
    repository_id = "${var.basename}-app"
    depends_on    = [google_project_service.all]
}

# Create Artifact Registry repository
resource "google_artifact_registry_repository" "todo_app" {
    provider      = google-beta
    format        = "DOCKER"
    location      = locals.kpmg-project-info.region
    project       = locals.kpmg-project-info.project_id
    repository_id = "${var.basename}-app"
    depends_on    = [google_project_service.all]
}

# Create secrets
resource "google_secret_manager_secret" "redishost" {
    project = locals.kpmg-project-info.project_number
    replication {
        automatic = true
    }
    secret_id  = "redishost"
    depends_on = [google_project_service.all]
}
resource "google_secret_manager_secret_version" "redishost" {
    enabled     = true
    secret      = "projects/${var.project_number}/secrets/redishost"
    secret_data = google_redis_instance.todo_cache.host
    depends_on  = [google_project_service.all, google_redis_instance.todo_cache, google_secret_manager_secret.redishost]
}
resource "google_secret_manager_secret" "sqlhost" {
    project = locals.kpmg-project-info.project_number
    replication {
        automatic = true
    }
    secret_id  = "sqlhost"
    depends_on = [google_project_service.all]
}
resource "google_secret_manager_secret_version" "sqlhost" {
    enabled     = true
    secret      = "projects/${var.project_number}/secrets/sqlhost"
    secret_data = google_sql_database_instance.todo_database.private_ip_address
    depends_on  = [google_project_service.all, google_sql_database_instance.todo_database, google_secret_manager_secret.sqlhost]
}

# Create artifact for middleware
resource "null_resource" "cloudbuild_api" {
  provisioner "local-exec" {
    working_dir = "${path.module}/code/middleware"
    command     = "gcloud builds submit . --substitutions=_REGION=${var.region},_BASENAME=${var.basename}"
  }
  depends_on = [
    google_artifact_registry_repository.todo_app,
    google_secret_manager_secret_version.redishost,
    google_secret_manager_secret_version.sqlhost,
    google_project_service.all
  ]
}

# Deploy API container to Cloud Run
resource "google_cloud_run_service" "api" {
    name     = "${var.basename}-api"
    location = locals.kpmg-project-info.region
    project  = locals.kpmg-project-info.project_id

    template {
        spec {
            containers {
                image = "${locals.kpmg-project-info.region}-docker.pkg.dev/${var.project_id}/${var.basename}-app/api"
                env {
                    name = "REDISHOST"
                    value_from {
                        secret_key_ref {
                            name = google_secret_manager_secret.redishost.secret_id
                            key  = "latest"
                        }
                    }
                }
                env {
                    name = "todo_host"
                    value_from {
                        secret_key_ref {
                        name = google_secret_manager_secret.sqlhost.secret_id
                        key  = "latest"
                        }
                    }
                }
                env {
                    name  = "todo_user"
                    value = "todo_user"
                }
                env {
                    name  = "todo_pass"
                    value = "todo_pass"
                }
                env {
                    name  = "todo_name"
                    value = "todo"
                }
                env {
                    name  = "REDISPORT"
                    value = "6379"
                }
            }
        }
        metadata {
            annotations = {
                "autoscaling.knative.dev/maxScale"        = "1000"
                "run.googleapis.com/cloudsql-instances"   = google_sql_database_instance.todo_database.connection_name
                "run.googleapis.com/client-name"          = "terraform"
                "run.googleapis.com/vpc-access-egress"    = "all"
                "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.connector.id
            }
        }
    }
    autogenerate_revision_name = true
    depends_on = [
        null_resource.cloudbuild_api,
        google_project_iam_member.secretmanager_secretAccessor
    ]
} 

# Open Cloud Run API Service to be world readable.
resource "google_cloud_run_service_iam_policy" "noauth_api" {
    location    = google_cloud_run_service.api.location
    project     = google_cloud_run_service.api.project
    service     = google_cloud_run_service.api.name
    policy_data = data.google_iam_policy.noauth.policy_data
}

# Create artifact for front end
resource "null_resource" "cloudbuild_fe" {
    provisioner "local-exec" {
        working_dir = "${path.module}/code/frontend"
        command     = "gcloud builds submit . --substitutions=_REGION=${var.region},_BASENAME=${var.basename}"
    }
    depends_on = [
        google_artifact_registry_repository.todo_app,
        google_cloud_run_service.api
    ]
}

# Deploy front end container to Cloud Run
resource "google_cloud_run_service" "fe" {
    name     = "${var.basename}-fe"
    location = locals.kpmg-project-info.region
    project  = locals.kpmg-project-info.project_id
    template {
        spec {
            containers {
                image = "${locals.kpmg-project-info.region}-docker.pkg.dev/${var.project_id}/${var.basename}-app/fe"
                ports {
                    container_port = 80
                }
            }
        }
    }
    depends_on = [null_resource.cloudbuild_fe]
}

# Open Cloud Run front end service to be world readable
resource "google_cloud_run_service_iam_policy" "noauth_fe" {
    location    = google_cloud_run_service.fe.location
    project     = google_cloud_run_service.fe.project
    service     = google_cloud_run_service.fe.name
    policy_data = data.google_iam_policy.noauth.policy_data
}

