# What goes wrong when you deploy a real application into this landing zone

The foundation is **deliberately strict**: everything is blocked until someone opens it. When the app team deploys a 3-tier application
(web, API, database), they meet the problems below in roughly this order. Each one has a cause and a fix owned by a specific team.

| # | What the app team sees | Why | Fix, and who does it |
|---|---|---|---|
| 1 | `Required 'compute.instances.create' permission` | The app team starts with the **Viewer** role only | **Infra team** grants `roles/compute.instanceAdmin.v1` on the project (allowed list only; Owner is refused) |
| 2 | `Required 'compute.subnetworks.use' permission` when creating a VM in the shared subnet | A service project may only use a Shared VPC subnet it has been given | **Network team**: set `grant_app_team_subnet_access = true` (stage 3), or grant `roles/compute.networkUser` on one subnet |
| 3 | `Constraint constraints/compute.vmExternalIpAccess violated` | The organization policy denies public IPs | Not a bug. Create the VM **without** an external IP |
| 4 | SSH times out | Ingress is blocked | **Network team** adds `allow-iap-ssh` (35.235.240.0/20, tcp 22, tag `ssh`); the VM needs the tag and OS Login access |
| 5 | `apt-get update` hangs, or the container cannot pull an image | Egress is blocked and the VM has no internet route | **Network team**: `enable_nat = true` and an egress allow rule for 80 and 443 (or use Private Google Access plus Artifact Registry) |
| 6 | GKE: `Google Compute Engine: Required 'compute.subnetworks.use'` or `...hostServiceAgentUser` | GKE's own service accounts also need access to the shared subnet | **Network team**: `enable_gke_sharing = true` |
| 7 | GKE nodes `NotReady`, image pulls fail | Egress to Google and the control plane is blocked | Allow egress to Google APIs (Private Google Access is on), enable NAT for public registries, allow the control-plane range |
| 8 | Cloud SQL: `Constraint constraints/sql.restrictPublicIp violated` | Databases may not have a public IP | Use **private IP**: Service Networking peering from the host project |
| 9 | A load balancer returns 502 | Health-check traffic is blocked | **Network team** allows `130.211.0.0/22` and `35.191.0.0/16` on the application port |
| 10 | Cannot create a bucket in `us-central1` or a global resource | `gcp.resourceLocations` allows only Mumbai and Delhi | Create it in `asia-south1`, or ask the org admins to widen the list |
| 11 | `403` creating a bucket with public access | Public access prevention is enforced | Not a bug. Use a load balancer, or signed URLs |
| 12 | The dashboard shows nothing for the new cluster | The project is not in the Operations metrics scope | Operations team adds the project in stage 5 (`monitored` list) |

**How to find the cause quickly:** Network Intelligence Center → *Connectivity Tests* (names the exact firewall rule or route), the
firewall and flow logs in the central audit bucket (Operations project → Logging → Log Analytics), and the *Policy Troubleshooter* for IAM.
