variable "ops_alert_email" {
  description = "E-mail address that receives monitoring alerts and budget alerts."
  type        = string
}

variable "budget_amount" {
  description = "Monthly budget for all landing zone projects, in the currency of your billing account."
  type        = number
  default     = 5000
}

variable "budget_currency" {
  description = "Currency code of the billing account (gcloud billing accounts list shows it)."
  type        = string
  default     = "INR"
}

variable "log_retention_days" {
  description = "How long the central log bucket keeps logs."
  type        = number
  default     = 30
}

variable "sink_filter" {
  description = "Which logs the organization sink copies to the central bucket."
  type        = string
  default     = "logName:\"cloudaudit.googleapis.com\" OR logName:\"compute.googleapis.com%2Ffirewall\" OR logName:\"compute.googleapis.com%2Fvpc_flows\""
}
