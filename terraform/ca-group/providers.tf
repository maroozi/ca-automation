terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53"
    }
  }

  # Backend config values are passed at init time via -backend-config flags.
  # Locally: use the backend.hcl file (gitignored).
  # CI: passed as GitHub secrets.
  backend "azurerm" {}
}

provider "azuread" {
  tenant_id = var.tenant_id
  # Authenticates via az login for local use.
  # In prod the ADO pipeline uses the service connection (ARM_CLIENT_ID etc).
}
