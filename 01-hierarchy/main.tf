# Stage 1 · Resource hierarchy: the folders and projects every team will work in.
#
#   Organization
#   ├── Networking     one project that owns the Shared VPC (the "host project")
#   ├── Operations     one project for central logging and monitoring
#   ├── Development    one project where the app team builds
#   └── Production     one project that serves real users
#
# A Staging (UAT) folder and project is the obvious next addition. We leave it out because a new billing account allows only
# about 5 billing-linked projects, and this lab uses exactly five: seed, network host, operations, development and production.
#
# Why folders? Policies and access given to a folder flow down to every project inside it, so we set rules once per
# environment instead of once per project.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = ">= 6.0" }
    random = { source = "hashicorp/random", version = ">= 3.5" }
  }
}

provider "google" {
  region                = var.region
  user_project_override = true
  billing_project       = var.seed_project_id
}

resource "random_id" "suffix" {
  byte_length = 2
}

locals {
  org = "organizations/${var.org_id}"

  folders = {
    networking = "Networking"
    operations = "Operations"
    dev        = "Development"
    prod       = "Production"
  }

  app_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "iam.googleapis.com",
    "artifactregistry.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "bigquery.googleapis.com",
  ]

  # One project per purpose. The key is the short name; the real project id becomes <prefix>-<short name>-<random>.
  projects = {
    net-host = {
      name   = "Network Host"
      folder = "networking"
      env    = "shared"
      team   = "network"
      apis   = ["compute.googleapis.com", "logging.googleapis.com", "monitoring.googleapis.com", "servicenetworking.googleapis.com", "dns.googleapis.com"]
    }
    ops = {
      name   = "Operations Logging Monitoring"
      folder = "operations"
      env    = "shared"
      team   = "operations"
      apis   = ["logging.googleapis.com", "monitoring.googleapis.com", "cloudkms.googleapis.com", "storage.googleapis.com"]
    }
    dev-app = {
      name   = "Dev App"
      folder = "dev"
      env    = "dev"
      team   = "app"
      apis   = local.app_apis
    }
    prod-app = {
      name   = "Prod App"
      folder = "prod"
      env    = "prod"
      team   = "app"
      apis   = local.app_apis
    }
  }

  # One entry per (project, API) pair, so every API is its own resource.
  project_apis = merge([
    for key, p in local.projects : {
      for api in p.apis : "${key}/${api}" => { project = key, api = api }
    }
  ]...)
}

# ------------------------------------------------------------------ folders
resource "google_folder" "folder" {
  for_each            = local.folders
  display_name        = each.value
  parent              = local.org
  deletion_protection = false # a training environment: allow terraform destroy
}

# ------------------------------------------------------------------ projects
resource "google_project" "project" {
  for_each            = local.projects
  name                = each.value.name
  project_id          = "${var.prefix}-${each.key}-${random_id.suffix.hex}"
  folder_id           = google_folder.folder[each.value.folder].name
  billing_account     = var.billing_account
  auto_create_network = false # no default network: the Shared VPC is the only network
  deletion_policy     = "DELETE"

  labels = {
    environment = each.value.env
    team        = each.value.team
    cost-centre = "landing-zone-workshop"
    managed_by  = "terraform"
  }
}

resource "google_project_service" "api" {
  for_each           = local.project_apis
  project            = google_project.project[each.value.project].project_id
  service            = each.value.api
  disable_on_destroy = false
}
