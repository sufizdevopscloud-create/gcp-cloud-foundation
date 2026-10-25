# Stage 1 · Resource hierarchy

Five folders (Networking, Operations, Development, Staging, Production) and one project in each, with labels and the APIs each project needs.

```bash
terraform init -backend-config=../backend.hcl
terraform plan  -var-file=../terraform.tfvars -var-file=../generated.tfvars
terraform apply -var-file=../terraform.tfvars -var-file=../generated.tfvars
terraform output summary
```

**Check:** `gcloud resource-manager folders list --organization=ORG_ID`, and in the console *IAM & Admin → Manage resources*.
**Limit:** a billing account may only allow a few linked projects. If apply fails with a billing quota error, request an increase.
