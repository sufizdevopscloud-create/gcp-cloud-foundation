output "central_log_bucket" {
  value = google_logging_project_bucket_config.central.id
}

output "sink_writer_identity" {
  value = google_logging_organization_sink.central.writer_identity
}

output "dashboard" {
  value = "Console > Monitoring > Dashboards (project ${local.ops}): ${google_monitoring_dashboard.compute_gke.id}"
}

output "budget" {
  value = google_billing_budget.landing_zone.display_name
}
