output "ca_group_object_id" {
  description = "Object ID of the CA protection group"
  value       = azuread_group.ca_group.object_id
}

output "ca_group_display_name" {
  description = "Display name of the CA protection group"
  value       = azuread_group.ca_group.display_name
}

output "member_count" {
  description = "Number of members currently managed by Terraform"
  value       = length(var.members)
}
