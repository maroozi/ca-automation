terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53"
    }
  }

  # Local state for testing.
  # In prod, remove this block — backend is configured in the ADO bootstrap.
  backend "local" {}
}

provider "azuread" {
  tenant_id = var.tenant_id
  # Authenticates via az login for local use.
  # In prod the ADO pipeline uses the service connection (ARM_CLIENT_ID etc).
}
