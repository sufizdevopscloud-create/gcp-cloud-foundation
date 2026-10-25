# Stage 3 · Networking: one Shared VPC, one subnet per environment, and everything BLOCKED until the network team allows it.
#
# Shared VPC lets one project (the HOST project, owned by the network team) own the network, while the application projects
# (the SERVICE projects) put their virtual machines and clusters inside subnets that the host shares with them. The network team
# controls addresses and firewall rules in one place; the app teams cannot change the network, they can only use their subnet.

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
  host     = data.terraform_remote_state.hierarchy.outputs.project_ids["net-host"]
  projects = data.terraform_remote_state.hierarchy.outputs.project_ids
  numbers  = data.terraform_remote_state.hierarchy.outputs.project_numbers

  # environment name -> the service project that lives in that environment's folder
  service_projects = {
    dev     = local.projects["dev-app"]
    staging = local.projects["staging-app"]
    prod    = local.projects["prod-app"]
  }

  app_team = "group:gcp-app-team@${var.domain}"
}

# ------------------------------------------------------------------ the host project and the network
resource "google_compute_shared_vpc_host_project" "host" {
  project = local.host
}

resource "google_compute_network" "vpc" {
  project                 = local.host
  name                    = "vpc-shared"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "env" {
  for_each = var.subnets

  project                  = local.host
  name                     = "snet-${each.key}-${var.region}"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = each.value.cidr
  private_ip_google_access = true # VMs without a public address can still reach Google APIs

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = each.value.pods
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = each.value.services
  }

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ------------------------------------------------------------------ share the network with the service projects
resource "google_compute_shared_vpc_service_project" "service" {
  for_each        = local.service_projects
  host_project    = google_compute_shared_vpc_host_project.host.project
  service_project = each.value
}

# ------------------------------------------------------------------ BLOCK EVERYTHING (the starting point)
# Firewall rules are checked in priority order; the LOWER the number, the sooner it is checked. Google always has two hidden
# rules at priority 65535 (allow all out, deny all in). We add our own deny rules at 65000, with logging, so they are visible, and
# egress is blocked too. Any "allow" rule with a number below 65000 will win over these.
resource "google_compute_firewall" "deny_all_ingress" {
  project   = local.host
  name      = "fw-deny-all-ingress"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"
  priority  = 65000

  deny {
    protocol = "all"
  }
  source_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "deny_all_egress" {
  project   = local.host
  name      = "fw-deny-all-egress"
  network   = google_compute_network.vpc.name
  direction = "EGRESS"
  priority  = 65000

  deny {
    protocol = "all"
  }
  destination_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ------------------------------------------------------------------ rules the network team adds later (see terraform.tfvars)
resource "google_compute_firewall" "allow" {
  for_each = var.firewall_allow_rules

  project     = local.host
  name        = each.key
  description = each.value.description
  network     = google_compute_network.vpc.name
  direction   = each.value.direction
  priority    = each.value.priority

  allow {
    protocol = each.value.protocol
    ports    = length(each.value.ports) > 0 ? each.value.ports : null
  }

  source_ranges      = each.value.direction == "INGRESS" ? each.value.ranges : null
  destination_ranges = each.value.direction == "EGRESS" ? each.value.ranges : null
  target_tags        = length(each.value.target_tags) > 0 ? each.value.target_tags : null

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ------------------------------------------------------------------ internet access for private machines (off until the network team turns it on)
resource "google_compute_router" "router" {
  count   = var.enable_nat ? 1 : 0
  project = local.host
  name    = "rtr-${var.region}"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  count                              = var.enable_nat ? 1 : 0
  project                            = local.host
  name                               = "nat-${var.region}"
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ------------------------------------------------------------------ who may use which subnet
# The app team can see the subnets only after the network team gives them "Compute Network User" on the subnet.
locals {
  app_team_access = var.grant_app_team_subnet_access ? { for env in keys(var.subnets) : "${env}/${local.app_team}" => { env = env, member = local.app_team } } : {}
  extra_access = merge([
    for env, members in var.extra_subnet_users : {
      for m in members : "${env}/${m}" => { env = env, member = m }
    }
  ]...)
  subnet_access = merge(local.app_team_access, local.extra_access)
}

resource "google_compute_subnetwork_iam_member" "network_user" {
  for_each   = local.subnet_access
  project    = local.host
  region     = var.region
  subnetwork = google_compute_subnetwork.env[each.value.env].name
  role       = "roles/compute.networkUser"
  member     = each.value.member
}
