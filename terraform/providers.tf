# Terraform + providers. The official oracle-terraform-modules/oke module needs the oci
# provider plus a few helpers (tls/http/local) it uses internally for image lookup, key gen,
# and writing the kubeconfig — declaring them here is required, the module does not bundle them.
terraform {
  required_version = ">= 1.5"
  # versions follow what the official OKE module v5.4 requires (oci >= 7.30) plus the helper
  # providers it pulls in (tls/http/local/random/time). Let the module's own constraints win.
  required_providers {
    oci    = { source = "oracle/oci", version = ">= 7.30.0" }
    tls    = { source = "hashicorp/tls" }
    http   = { source = "hashicorp/http" }
    local  = { source = "hashicorp/local" }
    random = { source = "hashicorp/random" }
    time   = { source = "hashicorp/time" }
  }

  # PoC uses local state. PRODUCTION: switch to a remote backend with locking, e.g.
  #   backend "oci" { namespace=... bucket="tf-state" key="oke/terraform.tfstate" region=... }
  # (left as a documented TODO — wiring it needs a pre-created bucket, not worth it for the PoC.)
}

# Auth reuses the SAME session-token CLI profile the rest of the project uses (oktest6).
# No keys in code. SecurityToken is correct for interactive local dev; CI would use OIDC/UPST
# or an instance principal instead (a documented limit, not a flaw).
provider "oci" {
  auth                = "SecurityToken"
  config_file_profile = var.config_file_profile
  region              = var.region
}

# The module creates IAM resources (tags, policies) in the tenancy HOME region — it requires a
# second, aliased provider for that. Here home == ap-mumbai-1, so it points at the same region.
provider "oci" {
  alias               = "home"
  auth                = "SecurityToken"
  config_file_profile = var.config_file_profile
  region              = var.home_region
}

variable "home_region" {
  description = "Tenancy home region (where IAM/identity resources must be created)."
  type        = string
  default     = "ap-mumbai-1"
}
