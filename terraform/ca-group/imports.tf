# ── Import existing CA group and members into Terraform state ─────────────────
# Run once: terraform plan (will show imports), then terraform apply.
# Delete this file after successful import — it is not needed ongoing.
#
# Group ID: f6598023-3e75-4fb1-a6ae-ec59fb6475e9
# Member import ID format: <group_object_id>/member/<member_object_id>
# ─────────────────────────────────────────────────────────────────────────────

import {
  to = azuread_group.ca_group
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9"
}

import {
  to = azuread_group_member.members["b23ea181-2677-46b5-af0d-84824e562ad2"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/b23ea181-2677-46b5-af0d-84824e562ad2"
}

import {
  to = azuread_group_member.members["c4da49b6-4bb6-49e0-b473-4d377811805a"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/c4da49b6-4bb6-49e0-b473-4d377811805a"
}

import {
  to = azuread_group_member.members["01f520b1-497b-4c2d-841c-7dac9b8422db"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/01f520b1-497b-4c2d-841c-7dac9b8422db"
}

import {
  to = azuread_group_member.members["39558af5-60f4-4e31-a8df-86e9d2a85557"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/39558af5-60f4-4e31-a8df-86e9d2a85557"
}

import {
  to = azuread_group_member.members["b8f07a98-0823-4a6c-8e0f-91c72085fb6e"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/b8f07a98-0823-4a6c-8e0f-91c72085fb6e"
}

import {
  to = azuread_group_member.members["4e8176d2-374c-4df0-8bcd-d3b247151598"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/4e8176d2-374c-4df0-8bcd-d3b247151598"
}

import {
  to = azuread_group_member.members["46980360-f860-4d9f-9fa3-8107754c4061"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/46980360-f860-4d9f-9fa3-8107754c4061"
}

import {
  to = azuread_group_member.members["ce71f88f-0019-4dd5-aa1a-f2a54a25291f"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/ce71f88f-0019-4dd5-aa1a-f2a54a25291f"
}

import {
  to = azuread_group_member.members["4786f93f-f693-4558-b049-57e91c54e88f"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/4786f93f-f693-4558-b049-57e91c54e88f"
}

import {
  to = azuread_group_member.members["73f61b63-5bed-49db-8b5f-d2f5e5e095ac"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/73f61b63-5bed-49db-8b5f-d2f5e5e095ac"
}

import {
  to = azuread_group_member.members["c9c5811c-5b7f-432e-b8b8-b2c162608d5e"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/c9c5811c-5b7f-432e-b8b8-b2c162608d5e"
}

import {
  to = azuread_group_member.members["bef1d246-da26-4d94-bb44-e0e27b041de9"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/bef1d246-da26-4d94-bb44-e0e27b041de9"
}

import {
  to = azuread_group_member.members["81f86a72-e6ff-4a0a-a7bb-a4ef268c1b8c"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/81f86a72-e6ff-4a0a-a7bb-a4ef268c1b8c"
}

import {
  to = azuread_group_member.members["fd0ab0e2-777c-4569-8552-682d9b63391a"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/fd0ab0e2-777c-4569-8552-682d9b63391a"
}

import {
  to = azuread_group_member.members["e3d061c1-d5cc-4a67-93e2-03f57654b924"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/e3d061c1-d5cc-4a67-93e2-03f57654b924"
}

import {
  to = azuread_group_member.members["24c3d353-0c65-4787-ad27-065d9bb37eb5"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/24c3d353-0c65-4787-ad27-065d9bb37eb5"
}

import {
  to = azuread_group_member.members["2ca7ca84-a149-44d7-9409-53dd25fc18f9"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/2ca7ca84-a149-44d7-9409-53dd25fc18f9"
}

import {
  to = azuread_group_member.members["86d723db-6dc3-45f5-ae66-567a5b10e8be"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/86d723db-6dc3-45f5-ae66-567a5b10e8be"
}

import {
  to = azuread_group_member.members["39258d66-4d14-4f32-9c46-b9d6bf3866ce"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/39258d66-4d14-4f32-9c46-b9d6bf3866ce"
}

import {
  to = azuread_group_member.members["ba9af88c-a5d9-4efe-9d6f-d42934b27443"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/ba9af88c-a5d9-4efe-9d6f-d42934b27443"
}

import {
  to = azuread_group_member.members["10f4c55b-08d8-451c-91e2-1bc3ba2b1e28"]
  id = "f6598023-3e75-4fb1-a6ae-ec59fb6475e9/member/10f4c55b-08d8-451c-91e2-1bc3ba2b1e28"
}
