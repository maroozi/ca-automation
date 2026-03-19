variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "environment" {
  description = "Deployment environment - test or prod"
  type        = string
  default     = "test"

  validation {
    condition     = contains(["test", "prod"], var.environment)
    error_message = "environment must be 'test' or 'prod'."
  }
}

variable "ca_group_name" {
  description = "Display name of the Conditional Access protection group"
  type        = string
}

variable "ca_group_description" {
  description = "Description of the CA group"
  type        = string
  default     = "Conditional Access protection group for High Security subscriptions"
}

