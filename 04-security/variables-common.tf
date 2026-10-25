# Variables that every stage uses. This file is identical in every stage folder (run scripts/sync-common.sh after editing it).

variable "org_id" {
  description = "Numeric ID of your Google Cloud organization (gcloud organizations list)."
  type        = string
}

variable "billing_account" {
  description = "Billing account that every project is linked to (gcloud billing accounts list)."
  type        = string
}

variable "domain" {
  description = "Primary domain of your Cloud Identity account, for example example.com. Used for group addresses."
  type        = string
}

variable "prefix" {
  description = "Short prefix for names and project ids."
  type        = string
  default     = "lz"
}

variable "region" {
  description = "Default region for subnets, buckets and log storage."
  type        = string
  default     = "asia-south1"
}

# Written for you by stage 00 into generated.tfvars.
variable "seed_project_id" {
  description = "The seed project that holds the Terraform state bucket. Created by stage 00."
  type        = string
  default     = ""
}

variable "state_bucket" {
  description = "Name of the Cloud Storage bucket that holds all Terraform state. Created by stage 00."
  type        = string
  default     = ""
}
