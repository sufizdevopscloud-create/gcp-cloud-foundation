output "policies_enforced" {
  value = concat(sort(keys(google_organization_policy.boolean)), ["compute.vmExternalIpAccess (deny all)"], length(var.allowed_locations) > 0 ? ["gcp.resourceLocations"] : [])
}

output "kms_key" {
  value = google_kms_crypto_key.data.id
}

output "encrypted_bucket" {
  value = google_storage_bucket.sensitive.url
}

output "custom_role" {
  value = google_organization_iam_custom_role.vm_operator.id
}
