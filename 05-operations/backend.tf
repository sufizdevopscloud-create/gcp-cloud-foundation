# State lives in the shared bucket created by stage 00. The bucket name is passed in at init time:
#   terraform init -backend-config=../backend.hcl
terraform {
  backend "gcs" {
    prefix = "05-operations"
  }
}
