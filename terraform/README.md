# OKE cluster as code (Terraform — official module)

Stands up a production-posture OKE cluster from one definition, using Oracle's official,
Registry-verified module `oracle-terraform-modules/oke` (v5.x). This is the "machine layer" as IaC.

## Why the official module (not hand-rolled)
A hand-rolled first draft was reviewed and scored ~50% vs best practice: it mirrored the
Quick-Create cluster's *insecure* defaults (public API to 0.0.0.0/0, public workers, root
compartment, security lists, no tags). The official module's DEFAULTS are Oracle's recommended
secure posture, for free:
- **private workers** + **private control-plane endpoint** (reached via a bastion + operator host
  the module provisions, with kubectl/helm pre-installed)
- **NSGs per component** (not hand-maintained security lists)
- NAT + service gateway auto-created; everything tagged for cost/ownership

`terraform plan` => **72 resources** (vs the hand-roll's 14) — the extra ~58 are exactly the NSGs,
bastion/operator, private-endpoint wiring, and IAM the hand-roll was missing.

## Use
```bash
oci session authenticate --profile-name oktest6 --region ap-mumbai-1   # session token, ~1h
cp terraform.tfvars.example terraform.tfvars                            # fill tenancy + compartment
terraform init      # downloads the official module + providers
terraform plan      # preview — creates NOTHING (shows "72 to add")
terraform apply     # build (~15-20 min); creates real resources, costs money
```
After `apply`, `operator_ssh_command` output SSHes you to the operator host, which can run
`kubectl` against the private cluster.

## Files
- `providers.tf` — Terraform + provider pins (oci >= 7.30 per the module) + the `oci.home` provider
  the module needs for IAM. SecurityToken auth (correct for local; CI would use OIDC/instance-principal).
- `oke.tf` — the single module call + its inputs (cluster, network, workers, bastion/operator, tags).
- `terraform.tfvars.example` — the only per-environment values (tenancy, compartment). Real
  `terraform.tfvars` is gitignored.

## Production TODO (documented, not done)
- **Dedicated compartment** instead of root tenancy (only root exists in this account today).
- **Remote backend** with locking (OCI Object Storage) instead of local state — see `providers.tf`.
