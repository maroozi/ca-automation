# ============================================================
# CA Group — Conditional Access Protection Group
# ============================================================
#
# TEST:  Terraform creates the group.
# PROD:  Group already exists. Import it before first apply:
#
#   terraform import azuread_group.ca_group <group-object-id>
#
#   If the group already has members, import each one:
#   terraform import \
#     'azuread_group_member.members["<user-object-id>"]' \
#     <group-object-id>/<user-object-id>
#
# After import, set prevent_destroy = true in the lifecycle block below.
# ============================================================

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
# Each member is a separate resource so PRs add/remove individual entries.
# Remediation automation modifies var.members and raises a PR here.

resource "azuread_group_member" "members" {
  for_each = toset(var.members)

  group_object_id  = azuread_group.ca_group.object_id
  member_object_id = each.value
}
