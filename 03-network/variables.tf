variable "subnets" {
  description = "One subnet per environment. Pods and services are the secondary ranges GKE uses."
  type = map(object({
    cidr     = string
    pods     = string
    services = string
  }))
  default = {
    dev  = { cidr = "10.10.0.0/20", pods = "10.64.0.0/16", services = "10.65.0.0/20" }
    prod = { cidr = "10.30.0.0/20", pods = "10.68.0.0/16", services = "10.69.0.0/20" }
  }
}

variable "firewall_allow_rules" {
  description = "Allow rules added by the network team. Everything not allowed here stays blocked. Key = rule name."
  type = map(object({
    description = optional(string, "")
    direction   = optional(string, "INGRESS")
    priority    = optional(number, 1000)
    protocol    = optional(string, "tcp")
    ports       = optional(list(string), [])
    ranges      = list(string)
    target_tags = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.firewall_allow_rules) : contains(["INGRESS", "EGRESS"], r.direction) && r.priority < 65000])
    error_message = "direction must be INGRESS or EGRESS, and priority must be below 65000 or the deny rule wins."
  }
}

variable "enable_nat" {
  description = "Create Cloud NAT so machines without a public address can reach the internet (an egress allow rule is still needed)."
  type        = bool
  default     = false
}

variable "grant_app_team_subnet_access" {
  description = "Give the app team Compute Network User on the three subnets. Off at first: this is the fix for the exercise."
  type        = bool
  default     = false
}

variable "extra_subnet_users" {
  description = "Extra members per environment who may use that subnet, for example { dev = [\"group:other@example.com\"] }."
  type        = map(list(string))
  default     = {}
}

variable "enable_gke_sharing" {
  description = "Grant the GKE service accounts of the dev project what it needs to build clusters in the shared subnets."
  type        = bool
  default     = false
}
