# OKE cluster via Oracle's OFFICIAL, Registry-verified module.
# This replaces ~300 lines of hand-rolled VCN/subnets/gateways/seclists/cluster/nodepool with
# one module call whose DEFAULTS are Oracle's recommended secure posture:
#   - private workers (worker_is_public = false)
#   - private control-plane endpoint (control_plane_is_public = false)
#   - NSGs per component (not hand-maintained security lists)
#   - NAT + service gateway created automatically
# We reach the private cluster via a bastion + operator host the module stands up for us.
#
# Module: https://registry.terraform.io/modules/oracle-terraform-modules/oke (v5.x, verified)

variable "config_file_profile" {
  type    = string
  default = "oktest6"
}
variable "region" {
  type    = string
  default = "ap-mumbai-1"
}
variable "tenancy_id" {
  type = string
}
variable "compartment_id" {
  description = "Dedicated compartment for the cluster (NOT the root tenancy — blast-radius + IAM scoping)."
  type        = string
}
variable "ssh_public_key_path" {
  description = "Public key placed on bastion/operator/workers for SSH access."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
variable "kubernetes_version" {
  type    = string
  default = "v1.34.1"
}

module "oke" {
  source  = "oracle-terraform-modules/oke/oci"
  version = "~> 5.4"

  # the module needs both the regional provider and the home-region one (for IAM resources)
  providers = {
    oci      = oci
    oci.home = oci.home
  }

  # --- identity / provider passthrough ---
  tenancy_id          = var.tenancy_id
  compartment_id      = var.compartment_id
  region              = var.region
  config_file_profile = var.config_file_profile
  ssh_public_key_path = var.ssh_public_key_path

  # --- networking: let the module build a fresh VCN + all gateways/NSGs (secure defaults) ---
  # gateway vars take "auto"/"always"/"never" (not bools): "always" forces creation.
  create_vcn                  = true
  vcn_name                    = "oke-tf-vcn"
  vcn_cidrs                   = ["10.0.0.0/16"]
  vcn_create_nat_gateway      = "always"   # private workers reach internet via NAT
  vcn_create_service_gateway  = "always"   # private path to OCIR / object storage
  vcn_create_internet_gateway = "always"   # public ingress for LB + bastion

  # --- cluster (basic, matches the live one; endpoint PRIVATE per secure default) ---
  create_cluster          = true
  cluster_name            = "oke-tf"
  cluster_type            = "basic"
  kubernetes_version      = var.kubernetes_version
  control_plane_is_public = false   # private API endpoint (the secure default we chose)

  # --- access path to the private cluster ---
  create_bastion  = true            # jump host on a public subnet
  create_operator = true            # private host with kubectl/helm pre-installed, reaches the API
  operator_install_kubectl_from_repo = true
  operator_install_helm              = true

  # --- workers: mirror the live pool (2x VM.Standard.E3.Flex, 1 OCPU / 16GB) ---
  worker_pool_mode = "node-pool"
  worker_pools = {
    pool1 = {
      description      = "Primary OKE-managed node pool"
      create           = true
      shape            = "VM.Standard.E3.Flex"
      ocpus            = 1
      memory           = 16
      size             = 2
      boot_volume_size = 50
    }
  }

  # --- governance: tag everything for cost attribution + ownership ---
  freeform_tags = {
    project    = "oke-idp-poc"
    managed_by = "terraform"
    env        = "poc"
  }
}

output "cluster_id" {
  value = module.oke.cluster_id
}
output "operator_ssh_command" {
  description = "SSH to the operator host (it can run kubectl against the private cluster)."
  value       = try(module.oke.ssh_to_operator, null)
}
