# Stage 0 · Bootstrap: the seed project and the Cloud Storage bucket that holds ALL Terraform state.
#
# Terraform needs somewhere to remember what it built. On a laptop that is a file called terraform.tfstate, which is lost with
# the laptop and cannot be shared. The best practice is a versioned bucket in Cloud Storage with locking, so a team shares one
# state safely. This stage creates that bucket. It is the only stage that starts with local state, because the bucket does
# not exist yet; at the end we move its own state into the bucket too.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = ">= 6.0" }
    random = { source = "hashicorp/random", version = ">= 3.5" }
    local  = { source = "hashicorp/local", version = ">= 2.4" }
  }
}

provider "google" {
  region = var.region
}

# Who is running Terraform? We give this person the organization roles the next stages need.
data "google_client_openid_userinfo" "me" {}

resource "random_id" "suffix" {
  byte_length = 2 # project ids must be globally unique, so we add four random characters
}

locals {
  seed_project_id = "${var.prefix}-seed-${random_id.suffix.hex}"
  operator        = "user:${data.google_client_openid_userinfo.me.email}"

  # Every later stage calls Google APIs on behalf of this project, so these APIs are switched on here.
  seed_apis = [
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbilling.googleapis.com",
    "billingbudgets.googleapis.com",
    "iam.googleapis.com",
    "cloudidentity.googleapis.com",
    "orgpolicy.googleapis.com",
    "compute.googleapis.com",
    "storage.googleapis.com",
    "cloudkms.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
}

# ------------------------------------------------------------------ the seed project
resource "google_project" "seed" {
  name                = "Seed Terraform State"
  project_id          = local.seed_project_id
  org_id              = var.org_id
  billing_account     = var.billing_account
  auto_create_network = false # no default VPC: we build our own network later
  deletion_policy     = "DELETE"

  labels = {
    purpose    = "terraform-state"
    managed_by = "terraform"
  }
}

resource "google_project_service" "seed" {
  for_each           = toset(local.seed_apis)
  project            = google_project.seed.project_id
  service            = each.value
  disable_on_destroy = false
}

# ------------------------------------------------------------------ the state bucket
resource "google_storage_bucket" "state" {
  name     = "${local.seed_project_id}-tfstate"
  project  = google_project.seed.project_id
  location = var.region

  uniform_bucket_level_access = true       # access is controlled only by IAM
  public_access_prevention    = "enforced" # this bucket can never be made public
  force_destroy               = false      # refuse to delete a bucket that still holds state

  versioning {
    enabled = true # every change to the state keeps the previous version: our undo button
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 20 # keep the last 20 versions of each state file, delete older ones
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    purpose    = "terraform-state"
    managed_by = "terraform"
  }

  depends_on = [google_project_service.seed]
}

# ------------------------------------------------------------------ roles for the person running Terraform
# Least privilege applies to the operator too: only what the landing zone stages need, at the organization.
resource "google_organization_iam_member" "operator" {
  for_each = toset(var.operator_roles)
  org_id   = var.org_id
  role     = each.value
  member   = local.operator
}

# ------------------------------------------------------------------ files for the next stages
# These two files are written next to the stage folders so every later stage can read them.
resource "local_file" "backend_hcl" {
  filename        = "${path.module}/../backend.hcl"
  file_permission = "0644"
  content         = "bucket = \"${google_storage_bucket.state.name}\"\n"
}

resource "local_file" "generated_tfvars" {
  filename        = "${path.module}/../generated.tfvars"
  file_permission = "0644"
  content         = <<-EOT
    seed_project_id = "${google_project.seed.project_id}"
    state_bucket    = "${google_storage_bucket.state.name}"
  EOT
}
