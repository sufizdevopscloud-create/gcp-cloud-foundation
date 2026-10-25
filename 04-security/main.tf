# Stage 4 · Security setup: organization policies, encryption keys (KMS) and least privilege.
#
# Three ideas, in the order we meet them:
#   1. Organization policies are RULES FOR THE WHOLE ORGANIZATION. Even a project owner cannot break them. They stop mistakes
#      before they happen, for example nobody can create a public bucket or a service account key.
#   2. KMS keys let YOU control the encryption key, instead of Google, and switch access off by disabling the key.
#   3. Least privilege: give only the permissions a job needs, nothing more. We build a small custom role as an example.

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

data "terraform_remote_state" "hierarchy" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "01-hierarchy"
  }
}

locals {
  ops_project = data.terraform_remote_state.hierarchy.outputs.project_ids["ops"]

  # Rules that are simply ON (enforced) for every project in the organization.
  boolean_policies = {
    "iam.disableServiceAccountKeyCreation"            = "No downloadable service account keys: use short-lived credentials instead."
    "iam.disableServiceAccountKeyUpload"              = "Nobody can upload their own key to a service account."
    "iam.automaticIamGrantsForDefaultServiceAccounts" = "New projects do not hand the default service account the Editor role."
    "compute.requireOsLogin"                          = "SSH access to VMs is tied to the person's IAM identity, not shared keys."
    "compute.skipDefaultNetworkCreation"              = "New projects do not get the open default VPC."
    "compute.requireShieldedVm"                       = "VMs must use Shielded VM images (secure boot and integrity monitoring)."
    "compute.disableSerialPortAccess"                 = "No interactive serial console on VMs."
    "storage.uniformBucketLevelAccess"                = "Bucket access is controlled by IAM only, never by per-object ACLs."
    "storage.publicAccessPrevention"                  = "No bucket or object can be made public."
    "sql.restrictPublicIp"                            = "Cloud SQL databases may not have a public IP address."
  }
}

# ------------------------------------------------------------------ organization policies
resource "google_organization_policy" "boolean" {
  for_each   = local.boolean_policies
  org_id     = var.org_id
  constraint = "constraints/${each.key}"

  boolean_policy {
    enforced = true
  }
}

# No VM may have a public IP address.
resource "google_organization_policy" "no_external_ip" {
  org_id     = var.org_id
  constraint = "constraints/compute.vmExternalIpAccess"

  list_policy {
    deny {
      all = true
    }
  }
}

# New resources may only be created in these places (Mumbai and Delhi by default).
resource "google_organization_policy" "locations" {
  count      = length(var.allowed_locations) > 0 ? 1 : 0
  org_id     = var.org_id
  constraint = "constraints/gcp.resourceLocations"

  list_policy {
    allow {
      values = var.allowed_locations
    }
  }
}

# Optional: only identities from your own Cloud Identity may be given roles (no personal Gmail accounts, no allUsers).
resource "google_organization_policy" "domain_restricted_sharing" {
  count      = length(var.domain_restricted_sharing_values) > 0 ? 1 : 0
  org_id     = var.org_id
  constraint = "constraints/iam.allowedPolicyMemberDomains"

  list_policy {
    allow {
      values = var.domain_restricted_sharing_values
    }
  }
}

# ------------------------------------------------------------------ encryption keys (KMS) and a bucket that uses one
resource "random_id" "ring" {
  byte_length = 2 # a key ring can never be deleted, so a fresh name keeps repeat workshops from colliding
}

resource "google_kms_key_ring" "ring" {
  project  = local.ops_project
  name     = "kr-foundation-${random_id.ring.hex}"
  location = var.region
}

resource "google_kms_crypto_key" "data" {
  name            = "key-sensitive-data"
  key_ring        = google_kms_key_ring.ring.id
  rotation_period = "7776000s" # a new key version every 90 days

  lifecycle {
    prevent_destroy = false
  }
}

# Cloud Storage reads and writes with the key through its own service account, so that account must be allowed to use it.
data "google_storage_project_service_account" "gcs" {
  project = local.ops_project
}

resource "google_kms_crypto_key_iam_member" "gcs_uses_key" {
  crypto_key_id = google_kms_crypto_key.data.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

resource "google_storage_bucket" "sensitive" {
  project                     = local.ops_project
  name                        = "${local.ops_project}-sensitive"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # training environment

  encryption {
    default_kms_key_name = google_kms_crypto_key.data.id
  }

  versioning {
    enabled = true
  }

  depends_on = [google_kms_crypto_key_iam_member.gcs_uses_key]
}

# ------------------------------------------------------------------ least privilege: a custom role that can run VMs but not create or delete them
resource "google_organization_iam_custom_role" "vm_operator" {
  org_id      = var.org_id
  role_id     = "lzVmOperator"
  title       = "Landing zone VM operator"
  description = "Start, stop, reset and view virtual machines. Cannot create or delete them."
  permissions = [
    "compute.instances.get",
    "compute.instances.list",
    "compute.instances.start",
    "compute.instances.stop",
    "compute.instances.reset",
    "compute.zones.list",
    "compute.projects.get",
  ]
}
