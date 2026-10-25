# Stage 5 · Central logging and monitoring.
#
# Logging: every project writes audit logs (who did what). A SINK at the organization level copies those logs from EVERY project
#   into one log bucket in the Operations project, so the operations team has one place to look, and cannot be bypassed by an
#   app team deleting logs in its own project.
# Monitoring: the Operations project gets a "metrics scope" that includes the app projects, so one dashboard shows virtual
#   machines and GKE clusters from Development and Production together.
# Billing: a budget with e-mail alerts, so cost surprises reach the Operations team early.

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

locals {
  ids     = data.terraform_remote_state.hierarchy.outputs.project_ids
  numbers = data.terraform_remote_state.hierarchy.outputs.project_numbers
  ops     = local.ids["ops"]

  monitored = ["dev-app", "prod-app", "net-host"]
  bucket_id = "central-audit"
  bucket    = "projects/${local.ops}/locations/${var.region}/buckets/${local.bucket_id}"
}

# ------------------------------------------------------------------ central log bucket
resource "google_logging_project_bucket_config" "central" {
  project          = local.ops
  location         = var.region
  bucket_id        = local.bucket_id
  retention_days   = var.log_retention_days
  enable_analytics = true # lets us query the logs with SQL (Log Analytics)
  description      = "Audit and network logs from every project in the organization"
}

# ------------------------------------------------------------------ organization-wide sink
resource "google_logging_organization_sink" "central" {
  name             = "sink-central-audit"
  org_id           = var.org_id
  destination      = "logging.googleapis.com/${local.bucket}"
  include_children = true # every folder and project under the organization
  filter           = var.sink_filter

  depends_on = [google_logging_project_bucket_config.central]
}

# The sink writes with its own identity, which must be allowed to write into the bucket.
resource "google_project_iam_member" "sink_writer" {
  project = local.ops
  role    = "roles/logging.bucketWriter"
  member  = google_logging_organization_sink.central.writer_identity
}

# Record who READS and WRITES objects in Cloud Storage, not just who changes settings.
resource "google_organization_iam_audit_config" "storage" {
  org_id  = var.org_id
  service = "storage.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# ------------------------------------------------------------------ one monitoring view over all projects
resource "google_monitoring_monitored_project" "scope" {
  for_each      = toset(local.monitored)
  metrics_scope = "locations/global/metricsScopes/${local.ops}"
  name          = local.ids[each.value]
}

# Count firewall denials that reached the central bucket (the logs you will see when the app team gets blocked).
resource "google_logging_metric" "firewall_denied" {
  project     = local.ops
  name        = "lz_firewall_denied"
  description = "Connections refused by VPC firewall rules, from every project"
  bucket_name = local.bucket
  filter      = "logName:\"compute.googleapis.com%2Ffirewall\" AND jsonPayload.disposition=\"DENIED\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }

  depends_on = [google_logging_project_bucket_config.central]
}

# ------------------------------------------------------------------ alerts by e-mail
resource "google_monitoring_notification_channel" "email" {
  project      = local.ops
  display_name = "Operations team e-mail"
  type         = "email"

  labels = {
    email_address = var.ops_alert_email
  }
}

resource "google_monitoring_alert_policy" "vm_cpu" {
  project      = local.ops
  display_name = "VM CPU above 80 per cent for 5 minutes"
  combiner     = "OR"

  conditions {
    display_name = "High VM CPU"
    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  depends_on            = [google_monitoring_monitored_project.scope]
}

resource "google_monitoring_alert_policy" "firewall_denied" {
  project      = local.ops
  display_name = "Many firewall denials in 5 minutes"
  combiner     = "OR"

  conditions {
    display_name = "Firewall denials spike"
    condition_threshold {
      filter          = "metric.type = \"logging.googleapis.com/user/${google_logging_metric.firewall_denied.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 50
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
}

# ------------------------------------------------------------------ dashboard: compute and GKE across projects
locals {
  tile = { for i, t in [
    { title = "VM CPU utilisation, per VM", filter = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\"", group = "metric.label.instance_name", aligner = "ALIGN_MEAN", reducer = "REDUCE_MEAN" },
    { title = "VM network received (bytes per second)", filter = "metric.type=\"compute.googleapis.com/instance/network/received_bytes_count\" resource.type=\"gce_instance\"", group = "metric.label.instance_name", aligner = "ALIGN_RATE", reducer = "REDUCE_SUM" },
    { title = "VM disk write operations", filter = "metric.type=\"compute.googleapis.com/instance/disk/write_ops_count\" resource.type=\"gce_instance\"", group = "metric.label.instance_name", aligner = "ALIGN_RATE", reducer = "REDUCE_SUM" },
    { title = "GKE node CPU allocatable utilisation, per cluster", filter = "metric.type=\"kubernetes.io/node/cpu/allocatable_utilization\" resource.type=\"k8s_node\"", group = "resource.label.cluster_name", aligner = "ALIGN_MEAN", reducer = "REDUCE_MEAN" },
    { title = "GKE container memory used, per namespace", filter = "metric.type=\"kubernetes.io/container/memory/used_bytes\" resource.type=\"k8s_container\"", group = "resource.label.namespace_name", aligner = "ALIGN_MEAN", reducer = "REDUCE_SUM" },
    { title = "GKE pod restarts, per cluster", filter = "metric.type=\"kubernetes.io/container/restart_count\" resource.type=\"k8s_container\"", group = "resource.label.cluster_name", aligner = "ALIGN_RATE", reducer = "REDUCE_SUM" },
  ] : i => t }
}

resource "google_monitoring_dashboard" "compute_gke" {
  project = local.ops
  dashboard_json = jsonencode({
    displayName = "Landing zone: virtual machines and GKE"
    mosaicLayout = {
      columns = 12
      tiles = [for i, t in local.tile : {
        xPos   = (i % 2) * 6
        yPos   = floor(i / 2) * 4
        width  = 6
        height = 4
        widget = {
          title = t.title
          xyChart = {
            dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = t.filter
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = t.aligner
                    crossSeriesReducer = t.reducer
                    groupByFields      = [t.group]
                  }
                }
              }
            }]
          }
        }
      }]
    }
  })

  depends_on = [google_monitoring_monitored_project.scope]
}

# ------------------------------------------------------------------ budget with e-mail alerts
resource "google_billing_budget" "landing_zone" {
  billing_account = var.billing_account
  display_name    = "${var.prefix} landing zone monthly budget"

  budget_filter {
    projects               = [for k, n in local.numbers : "projects/${n}"]
    calendar_period        = "MONTH"
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(var.budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.email.id]
    disable_default_iam_recipients   = false
  }
}
