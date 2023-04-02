# Enable services
variable "gcp_service_list" {
    description = "The list of apis necessary for the project"
    type        = list(string)
    default = [
        "compute.googleapis.com",
        "cloudapis.googleapis.com",
        "vpcaccess.googleapis.com",
        "servicenetworking.googleapis.com",
        "cloudbuild.googleapis.com",
        "sql-component.googleapis.com",
        "sqladmin.googleapis.com",
        "storage.googleapis.com",
        "secretmanager.googleapis.com",
        "run.googleapis.com",
        "artifactregistry.googleapis.com",
        "redis.googleapis.com"
    ]

# Set permissions	
variable "build_roles_list" {
    description = "The list of roles that build needs for"
    type        = list(string)
    default = [
        "roles/run.developer",
        "roles/vpaccess.user",
        "roles/iam.serviceAccountUser",
        "roles/run.admin",
        "roles/secretmanager.secretAccessor",
        "roles/artifactregistry.admin",
    ]
}

variable "project_id" {
  type        = string
  description = "The project ID to manage the Cloud SQL resources"
}

variable "project_number" {
  type        = string
  description = "The project number to manage the Cloud SQL resources"
}

variable "zone" {
  type        = string
  description = "The zone for the master instance."
  default     = "us-central1-a"
}

variable "basename" {
  type        = string
  description = "The name of the Cloud SQL resources"
}



