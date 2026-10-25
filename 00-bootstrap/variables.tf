variable "operator_roles" {
  description = "Organization roles given to the person running Terraform. Remove roles you do not need."
  type        = list(string)
  default = [
    "roles/resourcemanager.organizationAdmin", # grant IAM at the organization (stage 02)
    "roles/resourcemanager.folderAdmin",       # create the folders (stage 01)
    "roles/resourcemanager.projectCreator",    # create the projects (stage 01)
    "roles/compute.xpnAdmin",                  # turn on Shared VPC (stage 03)
    "roles/orgpolicy.policyAdmin",             # set organization policies (stage 04)
    "roles/iam.organizationRoleAdmin",         # create a custom role (stage 04)
    "roles/logging.configWriter",              # create the organization log sink (stage 05)
  ]
}
