# ============================================================
# CA Group - Conditional Access Protection Group
# ============================================================
#
# Members are managed in config/members.yml (UPNs).
# Terraform resolves UPNs to object IDs via data.azuread_user.
#
# PROD: Group already exists. Import it before first apply:
#   terraform import azuread_group.ca_group <group-object-id>
#
# After import, set prevent_destroy = true in the lifecycle block below.
# ============================================================

locals {
  config  = yamldecode(file("${path.module}/config/members.yml"))
  members = toset(local.config.members)
}

# Resolve each UPN to an Entra ID object
data "azuread_user" "members" {
  for_each            = local.members
  user_principal_name = each.value
}

resource "azuread_group" "ca_group" {
  display_name     = var.ca_group_name
  description      = var.ca_group_description
  security_enabled = true
  mail_enabled     = false

  lifecycle {
    # Flip to true after importing the prod group to prevent accidental deletion.
    prevent_destroy = false
  }
}

# ── Group Membership ────────────────────────────────────────────────────────
# Each member is a separate resource keyed by UPN.
# Remediation automation modifies config/members.yml and raises a PR.

resource "azuread_group_member" "members" {
  for_each = local.members

  group_object_id  = azuread_group.ca_group.object_id
  member_object_id = data.azuread_user.members[each.value].object_id
}
