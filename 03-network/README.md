# Stage 3 · Networking: Shared VPC, blocked by default

One Shared VPC in the host project, one subnet per environment shared with the dev, staging and prod projects, and two firewall rules that deny
**all ingress and all egress**. The network team opens traffic one rule at a time by editing `terraform.tfvars` (see `terraform.tfvars.example`).

```bash
terraform init -backend-config=../backend.hcl
terraform apply -var-file=../terraform.tfvars -var-file=../generated.tfvars
```

**Check:** `gcloud compute networks subnets list --project HOST_PROJECT`, and in the console VPC network → Firewall.
