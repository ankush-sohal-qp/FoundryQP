# Decision: Terraform (not OpenTofu) for this fleet

Status: decided (Phase 3 tool choice)
Date: 2026-06-02

## Decision
Use **Terraform** for OCI provisioning, not OpenTofu.

## Why
- Terraform v1.12+ has a **native `oci` state backend** with built-in locking via OCI Object
  Storage `If-None-Match` conditional writes. Locking works out of the box.
- OpenTofu does **NOT** have the native `oci` backend (issue #1011, open as of 2026). Choosing
  it forces you onto the S3-compat path that Oracle **deprecated**, plus `use_lockfile`
  uncertainty — i.e. you'd spend effort building a lock rig the native backend gives free.
- For a 28-VM single-region fleet, the elaborate external-lock setups (DynamoDB-style) are
  pure ceremony. Native backend eliminates the whole problem.

This is the one place the SRE research's headline recommendation (OpenTofu) was overridden —
it recommended OpenTofu while its longest section fought the exact locking pain that choice
causes. The tool choice and the backend pain were causally linked; native backend resolves both.

## When to reconsider
- Org mandates OpenTofu org-wide → it's a `s/terraform/tofu/` migration; revisit locking
  (S3-compat + `use_lockfile`) at that point.
- HashiCorp licensing (BSL) becomes a blocker for your use → re-evaluate.
