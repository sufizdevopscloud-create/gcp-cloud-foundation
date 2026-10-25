output "group_emails" {
  value = local.email
}

output "customer_id" {
  value = data.google_organization.this.directory_customer_id
}
