output "seed_project_id" {
  value = google_project.seed.project_id
}

output "state_bucket" {
  value = google_storage_bucket.state.name
}

output "next_steps" {
  value = <<-EOT
    1. Make this stage use the bucket too:
         cp backend.tf.example backend.tf
         terraform init -backend-config=../backend.hcl -migrate-state
    2. Tell your Terraform login which project to use for quota:
         gcloud auth application-default set-quota-project ${google_project.seed.project_id}
    3. Go to 01-hierarchy.
  EOT
}
