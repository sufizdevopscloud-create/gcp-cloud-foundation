# Stage 4 · Security setup

Organization policies (no service account keys, no public IPs, no public buckets, approved regions only, OS Login, Shielded VMs, no public Cloud SQL),
a KMS key with 90-day rotation protecting a bucket, and a least-privilege custom role `lzVmOperator`.

```bash
terraform init -backend-config=../backend.hcl
terraform apply -var-file=../terraform.tfvars -var-file=../generated.tfvars
```

**Check:** try `gcloud storage buckets create gs://$RANDOM-test --location=us-central1` and read the refusal.
Optional: set `domain_restricted_sharing_values` (your Cloud Identity customer id) to block personal Gmail accounts and `allUsers` in IAM.
