# Stage 2 · User onboarding: five Cloud Identity groups, and the roles each group gets on the folders.
#
# People never get roles directly. We put people in a GROUP, and give the group a role on a FOLDER. When someone joins or leaves a
# team we change group membership, and the access follows. The users themselves are created in the Cloud Identity admin console
# (admin.google.com): Terraform manages the groups and who is in them, not the user accounts.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = ">= 6.0" }
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

data "google_organization" "this" {
  organization = "organizations/${var.org_id}"
}

locals {
  h           = data.terraform_remote_state.hierarchy.outputs
  org         = "organizations/${var.org_id}"
  folder      = local.h.folder_ids
  env_folders = ["dev", "staging", "prod"]

  # ---------------------------------------------------------------- the five teams
  groups = {
    org_admins = {
      id          = "gcp-org-admins"
      display     = "GCP Org Admins"
      description = "Owns the organization: folders, projects, organization policies. Keep this group very small."
    }
    network_admins = {
      id          = "gcp-network-admins"
      display     = "GCP Network Admins"
      description = "Owns the Shared VPC, subnets, routes, firewall rules and peering."
    }
    operations_admins = {
      id          = "gcp-operations-admins"
      display     = "GCP Operations Admins"
      description = "Watches central logs, dashboards and billing, and sets budget alerts."
    }
    infra_team = {
      id          = "gcp-infra-team"
      display     = "GCP Infra Team"
      description = "Grants IAM access to the app team, but only from an approved list of roles."
    }
    app_team = {
      id          = "gcp-app-team"
      display     = "GCP App Team"
      description = "Builds and runs the applications in Development, Staging and Production."
    }
  }

  email  = { for k, g in local.groups : k => "${g.id}@${var.domain}" }
  member = { for k, e in local.email : k => "group:${e}" }

  # ---------------------------------------------------------------- roles at the organization
  org_roles = {
    org_admins = [
      "roles/resourcemanager.organizationAdmin",
      "roles/resourcemanager.folderAdmin",
      "roles/resourcemanager.projectCreator",
      "roles/orgpolicy.policyAdmin",
      "roles/compute.xpnAdmin",
    ]
    # Everyone can SEE the folders and projects in the console, and nothing more.
    network_admins    = ["roles/browser"]
    operations_admins = ["roles/browser"]
    infra_team        = ["roles/browser"]
    app_team          = ["roles/browser"]
  }

  org_grants = merge([
    for group, roles in local.org_roles : {
      for role in roles : "${group}/${role}" => { group = group, role = role }
    }
  ]...)

  # ---------------------------------------------------------------- roles on folders
  folder_roles = {
    network_admins = {
      networking = ["roles/compute.networkAdmin", "roles/compute.securityAdmin", "roles/compute.xpnAdmin", "roles/logging.viewer"]
      dev        = ["roles/compute.networkViewer"]
      staging    = ["roles/compute.networkViewer"]
      prod       = ["roles/compute.networkViewer"]
    }
    operations_admins = {
      operations = ["roles/logging.admin", "roles/monitoring.admin"]
      dev        = ["roles/monitoring.viewer", "roles/logging.viewer"]
      staging    = ["roles/monitoring.viewer", "roles/logging.viewer"]
      prod       = ["roles/monitoring.viewer", "roles/logging.viewer"]
    }
    # The app team starts with READ-ONLY access. To create anything they must ask the Infra team (exercise).
    app_team = {
      dev     = ["roles/viewer"]
      staging = ["roles/viewer"]
      prod    = ["roles/viewer"]
    }
  }

  folder_grants = merge(
    flatten([
      for group, folders in local.folder_roles : [
        for folder, roles in folders : {
          for role in roles : "${group}/${folder}/${role}" => { group = group, folder = folder, role = role }
        }
      ]
    ])...
  )

  # The Infra team may only hand out these roles. The condition below enforces it.
  infra_condition = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(",", [for r in var.infra_grantable_roles : "'${r}'"])}])"

  memberships = merge([
    for group, emails in var.group_members : {
      for e in emails : "${group}/${e}" => { group = group, email = e }
    }
  ]...)
}

# ------------------------------------------------------------------ the organization must be backed by Cloud Identity
resource "terraform_data" "require_directory" {
  lifecycle {
    precondition {
      condition     = data.google_organization.this.directory_customer_id != ""
      error_message = "This organization is not linked to a Cloud Identity or Workspace domain, so groups cannot be created. Create a free Cloud Identity account for your domain (see the Onboarding lesson), then use the organization id that Google creates for it."
    }
  }
}

# ------------------------------------------------------------------ groups
resource "google_cloud_identity_group" "group" {
  for_each             = local.groups
  parent               = "customers/${data.google_organization.this.directory_customer_id}"
  display_name         = each.value.display
  description          = each.value.description
  initial_group_config = "EMPTY"

  group_key {
    id = local.email[each.key]
  }

  labels = {
    "cloudidentity.googleapis.com/groups.discussion_forum" = ""
  }

  depends_on = [terraform_data.require_directory]
}

resource "google_cloud_identity_group_membership" "member" {
  for_each = local.memberships
  group    = google_cloud_identity_group.group[each.value.group].id

  preferred_member_key {
    id = each.value.email
  }

  roles {
    name = "MEMBER"
  }
}

# ------------------------------------------------------------------ roles
resource "google_organization_iam_member" "org" {
  for_each = local.org_grants
  org_id   = var.org_id
  role     = each.value.role
  member   = local.member[each.value.group]
}

resource "google_folder_iam_member" "folder" {
  for_each = local.folder_grants
  folder   = local.folder[each.value.folder]
  role     = each.value.role
  member   = local.member[each.value.group]
}

# The Infra team can change IAM on the three environment folders, but ONLY by granting roles from the approved list.
resource "google_folder_iam_member" "infra_iam_admin" {
  for_each = toset(local.env_folders)
  folder   = local.folder[each.value]
  role     = "roles/resourcemanager.projectIamAdmin"
  member   = local.member.infra_team

  condition {
    title       = "Grant only approved team roles"
    description = "The Infra team cannot hand out Owner, Editor or any role that is not in the approved list."
    expression  = local.infra_condition
  }
}

# Extra grants you add during the exercises (for example giving the app team a role in dev).
resource "google_folder_iam_member" "extra" {
  for_each = { for g in var.extra_grants : "${g.group}/${g.folder}/${g.role}" => g }
  folder   = local.folder[each.value.folder]
  role     = each.value.role
  member   = local.member[each.value.group]
}

# The Operations team can see the billing data and manage budgets.
resource "google_billing_account_iam_member" "ops" {
  for_each           = var.grant_billing_roles ? toset(["roles/billing.viewer", "roles/billing.costsManager"]) : toset([])
  billing_account_id = var.billing_account
  role               = each.value
  member             = local.member.operations_admins
}
