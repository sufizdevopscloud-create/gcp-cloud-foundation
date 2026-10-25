# Stage 0 · Bootstrap: where Terraform keeps its state

Creates the **seed project**, a **versioned, private Cloud Storage bucket for all Terraform state**, and gives the person running
Terraform the organization roles the other stages need. It also writes `../backend.hcl` and `../generated.tfvars` for the later stages.

```bash
terraform init
terraform apply -var-file=../terraform.tfvars
cp backend.tf.example backend.tf
terraform init -backend-config=../backend.hcl -migrate-state     # moves this stage's own state into the bucket
gcloud auth application-default set-quota-project $(terraform output -raw seed_project_id)
```

**Check:** `gcloud storage ls gs://$(terraform output -raw state_bucket)/` shows a `00-bootstrap/` folder, and the bucket has versioning on
(`gcloud storage buckets describe gs://... --format="value(versioning.enabled)"` prints `True`).
