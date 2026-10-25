# Stage 2 · User onboarding

Five Cloud Identity groups (org admins, network admins, operations admins, infra team, app team), their members, and their roles.

1. Create the users in the admin console (admin.google.com → Directory → Users → *Bulk update users* with `../users-template.csv`).
2. `cp terraform.tfvars.example terraform.tfvars` and put the user emails in `group_members`.
3. Deploy:

```bash
terraform init -backend-config=../backend.hcl
terraform apply -var-file=../terraform.tfvars -var-file=../generated.tfvars
```

**Check:** admin console → Directory → Groups; console → IAM on a folder shows **groups**, not people. Sign in as an app team user: they can
see the folders and read, and nothing else.
