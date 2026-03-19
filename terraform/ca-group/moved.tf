# ── State key migration ───────────────────────────────────────────────────────
# for_each key changed from object ID → UPN when switching to yamldecode.
# These moved blocks update state without destroying/recreating members.
# Delete this file after the first successful apply.
# ─────────────────────────────────────────────────────────────────────────────

moved {
  from = azuread_group_member.members["b23ea181-2677-46b5-af0d-84824e562ad2"]
  to   = azuread_group_member.members["admin-allan.west@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["c4da49b6-4bb6-49e0-b473-4d377811805a"]
  to   = azuread_group_member.members["admin@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["01f520b1-497b-4c2d-841c-7dac9b8422db"]
  to   = azuread_group_member.members["lrqapentestingaccount@lrqa.com"]
}

moved {
  from = azuread_group_member.members["39558af5-60f4-4e31-a8df-86e9d2a85557"]
  to   = azuread_group_member.members["Admin-abushayan.khan@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["b8f07a98-0823-4a6c-8e0f-91c72085fb6e"]
  to   = azuread_group_member.members["Admin-Fiona.Laufs@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["4e8176d2-374c-4df0-8bcd-d3b247151598"]
  to   = azuread_group_member.members["muhammad.abdulsamad@lrqa.com"]
}

moved {
  from = azuread_group_member.members["46980360-f860-4d9f-9fa3-8107754c4061"]
  to   = azuread_group_member.members["Admin-Shrikant.Umadi@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["ce71f88f-0019-4dd5-aa1a-f2a54a25291f"]
  to   = azuread_group_member.members["Admin-Muhammad.Abdulsamad@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["4786f93f-f693-4558-b049-57e91c54e88f"]
  to   = azuread_group_member.members["martina.ruocco@lrqa.com"]
}

moved {
  from = azuread_group_member.members["73f61b63-5bed-49db-8b5f-d2f5e5e095ac"]
  to   = azuread_group_member.members["moshi.wei@lrqa.com"]
}

moved {
  from = azuread_group_member.members["c9c5811c-5b7f-432e-b8b8-b2c162608d5e"]
  to   = azuread_group_member.members["Admin-Paul.Cave@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["bef1d246-da26-4d94-bb44-e0e27b041de9"]
  to   = azuread_group_member.members["admin-cam.mcewan@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["81f86a72-e6ff-4a0a-a7bb-a4ef268c1b8c"]
  to   = azuread_group_member.members["admin-Dylan.Karrass@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["fd0ab0e2-777c-4569-8552-682d9b63391a"]
  to   = azuread_group_member.members["admin-moshi.wei@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["e3d061c1-d5cc-4a67-93e2-03f57654b924"]
  to   = azuread_group_member.members["admin-martina.ruocco@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["24c3d353-0c65-4787-ad27-065d9bb37eb5"]
  to   = azuread_group_member.members["admin-dan.abbatt@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["2ca7ca84-a149-44d7-9409-53dd25fc18f9"]
  to   = azuread_group_member.members["Admin-Adeel.Qayyum@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["86d723db-6dc3-45f5-ae66-567a5b10e8be"]
  to   = azuread_group_member.members["ashley.prosser@lrqa.com"]
}

moved {
  from = azuread_group_member.members["39258d66-4d14-4f32-9c46-b9d6bf3866ce"]
  to   = azuread_group_member.members["lewis.wilson@lrqa.com"]
}

moved {
  from = azuread_group_member.members["ba9af88c-a5d9-4efe-9d6f-d42934b27443"]
  to   = azuread_group_member.members["admin-ashley.prosser@lrqagroup.onmicrosoft.com"]
}

moved {
  from = azuread_group_member.members["10f4c55b-08d8-451c-91e2-1bc3ba2b1e28"]
  to   = azuread_group_member.members["admin-ross.alexander@lrqagroup.onmicrosoft.com"]
}
