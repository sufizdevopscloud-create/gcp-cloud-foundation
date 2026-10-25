variable "group_members" {
  description = "Who is in each team. Keys: org_admins, network_admins, operations_admins, infra_team, app_team. Values: email addresses of users that already exist in Cloud Identity."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.group_members) : contains(["org_admins", "network_admins", "operations_admins", "infra_team", "app_team"], k)])
    error_message = "group_members keys must be: org_admins, network_admins, operations_admins, infra_team, app_team."
  }
}

variable "infra_grantable_roles" {
  description = "The only roles the Infra team is allowed to grant on the environment folders."
  type        = list(string)
  default = [
    "roles/compute.instanceAdmin.v1",
    "roles/compute.osLogin",
    "roles/iap.tunnelResourceAccessor",
    "roles/container.developer",
    "roles/storage.objectAdmin",
    "roles/storage.admin",
    "roles/iam.serviceAccountUser",
    "roles/cloudsql.client",
    "roles/artifactregistry.writer",
    "roles/logging.viewer",
    "roles/monitoring.viewer",
    "roles/viewer",
  ]
}

variable "extra_grants" {
  description = "Extra roles for a team on an environment folder, added during the exercises. Example: { group = \"app_team\", folder = \"dev\", role = \"roles/compute.instanceAdmin.v1\" }"
  type = list(object({
    group  = string
    folder = string
    role   = string
  }))
  default = []
}

variable "grant_billing_roles" {
  description = "Give the Operations group billing viewer and cost manager on the billing account. Needs Billing Account Administrator."
  type        = bool
  default     = true
}
