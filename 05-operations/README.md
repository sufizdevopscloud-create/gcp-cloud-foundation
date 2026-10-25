# Stage 5 · Central logging and monitoring

An organization-wide log sink into one bucket in the Operations project (Log Analytics on), a monitoring view over the app projects, a dashboard for VMs
and GKE, e-mail alerts, and a monthly budget.

1. `cp terraform.tfvars.example terraform.tfvars` and set `ops_alert_email`.
2. Deploy:

```bash
terraform init -backend-config=../backend.hcl
terraform apply -var-file=../terraform.tfvars -var-file=../generated.tfvars
```

**Check:** Operations project → Logging → Log Analytics, bucket `central-audit`: run the query "who created or deleted something in the last hour".
