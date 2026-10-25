# GCP Cloud Foundation Project (a landing zone you build step by step)

A small, readable **landing zone** for Google Cloud, built live in a workshop. Each stage is one short Terraform project with one job.
All Terraform state is kept in a versioned **Cloud Storage bucket**, never in folders on your laptop.

```
Organization
├── Networking    → project: Shared VPC host         (network team)
├── Operations    → project: central logs, dashboards, budgets   (operations team)
├── Development   → project: app team builds here
└── Production    → project: real users

5 teams (Cloud Identity groups): GCP Org Admins · Network Admins · Operations Admins · Infra Team · App Team
```

| Stage | Folder | What it builds |
|---|---|---|
| 0 | [`00-bootstrap`](00-bootstrap) | The seed project and the **GCS bucket that stores all Terraform state** |
| 1 | [`01-hierarchy`](01-hierarchy) | **Resource hierarchy**: 4 folders and 4 projects (host, ops, dev, prod) |
| 2 | [`02-onboarding`](02-onboarding) | **User onboarding**: 5 Cloud Identity groups and the roles they get on each folder |
| 3 | [`03-network`](03-network) | **Networking**: Shared VPC, one subnet per environment, **everything blocked** until the network team opens it |
| 4 | [`04-security`](04-security) | **Security**: organization policies, KMS key, least-privilege custom role |
| 5 | [`05-operations`](05-operations) | **Central logging and monitoring**: org-wide log sink, dashboards, alerts, budget |

## Before you start

1. **A Cloud Identity (free) account for your domain.** Free Cloud Identity gives you an organization and up to 50 users. Sign up at <https://workspace.google.com/signup/gcpidentity/welcome>, verify your domain with a DNS TXT record, and create the first admin user. Google then creates your **organization** automatically (find it with `gcloud organizations list`).
   *If your organization has no domain attached, Terraform stage 2 stops with a clear message: groups only exist inside a Cloud Identity domain.*
2. **A billing account** you can link projects to (`gcloud billing accounts list`). The signed-in admin needs **Billing Account User** on it. Check the project quota: a new billing account may allow only about 5 linked projects, and this lab needs 5 (seed, network host, operations, development, production).
3. **Tools:** `gcloud`, `terraform` 1.5 or newer, `git`.
4. **Sign in as the Cloud Identity super admin** (an Organization Administrator who is also a Groups Admin):

```bash
gcloud auth login
gcloud auth application-default login          # tick "Select all" on the permissions page
```

## Run it

```bash
git clone https://github.com/sufizdevopscloud-create/gcp-cloud-foundation.git
cd gcp-cloud-foundation
cp terraform.tfvars.example terraform.tfvars   # fill in org_id, billing_account, domain
```

**Stage 0: the state bucket** (the only stage that begins with local state, because the bucket does not exist yet):

```bash
cd 00-bootstrap
terraform init
terraform apply -var-file=../terraform.tfvars
cp backend.tf.example backend.tf
terraform init -backend-config=../backend.hcl -migrate-state     # type yes: state moves into the bucket
gcloud auth application-default set-quota-project $(terraform output -raw seed_project_id)
```

**Stages 1 to 5** follow the same pattern. For stage `NN-name`:

```bash
cd ../01-hierarchy
terraform init -backend-config=../backend.hcl
terraform plan  -var-file=../terraform.tfvars -var-file=../generated.tfvars
terraform apply -var-file=../terraform.tfvars -var-file=../generated.tfvars
```

Stage 2 and later also read a stage-local `terraform.tfvars` (copy `terraform.tfvars.example` in that folder). There is a shortcut: `scripts/tf.sh 01-hierarchy plan`.

## Exercises (each stage has them on the workshop site)

* **Hierarchy:** add a new environment folder, change a label, find who the folders inherit from.
* **Onboarding:** the app team can only *view*. They ask the Infra team for a role, and watch the Infra team be *refused* when asking for Owner.
* **Networking:** the app team cannot use the subnet, cannot SSH, cannot reach the internet, cannot build a GKE cluster. The network team unblocks each, one rule at a time.
* **Security:** try to create a public bucket, a service account key and a VM with a public IP, and read the refusals.
* **Operations:** find who did what in the central audit log, read the dashboard, and receive a budget alert.

The most common problems you will hit when you deploy a real application are in [`docs/CHALLENGES.md`](docs/CHALLENGES.md).

## Clean up (reverse order)

```bash
cd 05-operations && terraform destroy -var-file=../terraform.tfvars -var-file=../generated.tfvars
# then 04-security, 03-network, 02-onboarding, 01-hierarchy in turn, and 00-bootstrap last
```

KMS key rings cannot be deleted (the key versions are scheduled for deletion), so a few cents of residue is normal.

## Cost

Small for a workshop: no virtual machines are created by the foundation itself. Cloud Logging, flow logs and Cloud NAT (if you turn it on) are billed by use; the budget in stage 5 warns you early.
