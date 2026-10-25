output "host_project" {
  value = local.host
}

output "network" {
  value = google_compute_network.vpc.self_link
}

output "subnets" {
  value = { for k, s in google_compute_subnetwork.env : k => "${s.name} ${s.ip_cidr_range}" }
}

output "blocked_by_default" {
  value = "fw-deny-all-ingress and fw-deny-all-egress at priority 65000. Add allow rules (priority below 65000) in terraform.tfvars."
}
