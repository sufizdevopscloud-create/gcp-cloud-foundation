# Optional exercise: let GKE clusters in the dev and staging projects use the shared subnets.
#
# GKE needs two extra permissions before it can create a cluster in a Shared VPC subnet. We leave this OFF at first so the app team
# hits the real error message, then switch enable_gke_sharing to true. Wait a minute after the first GKE cluster attempt, so that
# Google has created the service accounts named below.

locals {
  gke_envs = var.enable_gke_sharing ? ["dev", "staging"] : []

  gke_service_accounts = merge([
    for env in local.gke_envs : {
      "${env}/gke-robot"   = { env = env, member = "serviceAccount:service-${local.numbers["${env}-app"]}@container-engine-robot.iam.gserviceaccount.com" }
      "${env}/google-apis" = { env = env, member = "serviceAccount:${local.numbers["${env}-app"]}@cloudservices.gserviceaccount.com" }
    }
  ]...)
}

resource "google_compute_subnetwork_iam_member" "gke_network_user" {
  for_each   = local.gke_service_accounts
  project    = local.host
  region     = var.region
  subnetwork = google_compute_subnetwork.env[each.value.env].name
  role       = "roles/compute.networkUser"
  member     = each.value.member
}

resource "google_project_iam_member" "gke_host_agent" {
  for_each = toset(local.gke_envs)
  project  = local.host
  role     = "roles/container.hostServiceAgentUser"
  member   = "serviceAccount:service-${local.numbers["${each.value}-app"]}@container-engine-robot.iam.gserviceaccount.com"
}
