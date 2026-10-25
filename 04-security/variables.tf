variable "allowed_locations" {
  description = "Locations where new resources may be created (a 'value group' such as in:asia-south1-locations). Empty list turns the rule off."
  type        = list(string)
  default     = ["in:asia-south1-locations", "in:asia-south2-locations"]
}

variable "domain_restricted_sharing_values" {
  description = "Cloud Identity customer ids allowed in IAM policies (like C0abc1234). Empty = rule off. Find yours with: gcloud organizations describe ORG_ID (directoryCustomerId)."
  type        = list(string)
  default     = []
}
