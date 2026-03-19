# Scenario Testing Guide

Step-by-step instructions for manually testing each compliance scenario end-to-end in the **test environment**.

> **Prerequisites**
> - Az PowerShell connected to the test tenant (`Connect-AzAccount`)
> - Microsoft Graph connected (`Connect-MgGraph -Scopes "GroupMember.ReadWrite.All"`)
> - Scanner parameters ready (subscription ID, CA group ID, GitHub token)
> - `TEST-Group-001` group and test user RBAC assignment in place

---

## Common Commands

```powershell
# Run scanner in dry-run mode
.\scanner\Invoke-ComplianceScanner.ps1 `
    -SubscriptionIds "<sub-id>" `
    -CAGroupId "<ca-group-object-id>" `
    -DryRun

# Run scanner with full remediation
.\scanner\Invoke-ComplianceScanner.ps1 `
    -SubscriptionIds "<sub-id>" `
    -CAGroupId "<ca-group-object-id>" `
    -GitHubToken $env:GITHUB_TOKEN `
    -GitHubRepo "maroozi/ca-automation"

# Add a user to the CA group manually (for SC-02 setup)
New-MgGroupMember -GroupId "<ca-group-object-id>" -DirectoryObjectId "<user-object-id>"

# Remove a user from the CA group (for SC-03 setup)
Remove-MgGroupMemberByRef -GroupId "<ca-group-object-id>" -DirectoryObjectId "<user-object-id>"

# Check current live group members
Get-MgGroupMember -GroupId "<ca-group-object-id>" -All | Select-Object Id, DisplayName
```

---

## SC-01 — Role Assigned Before CA Group

**Condition:** User has HS RBAC but is not in `members.auto.tfvars` or the live CA group.

### Setup
1. Assign a test user an HS RBAC role (e.g. Reader) on the test subscription.
2. Ensure the user is **not** listed in `terraform/ca-group/members.auto.tfvars`.
3. Ensure the user is **not** a member of the live CA group.

### Run
```powershell
.\scanner\Invoke-ComplianceScanner.ps1 -SubscriptionIds "<sub-id>" -CAGroupId "<group-id>" -DryRun
# Confirm SC-01 is reported, then run without -DryRun
```

### Expected Result
- User is added to the live CA group immediately via Graph API.
- A PR is raised to add the user to `members.auto.tfvars`.
- After PR is merged, `terraform-apply` workflow runs and reconciles state.

### Cleanup
- Remove the test RBAC assignment.
- Merge or close the PR.

---

## SC-02 — Manual Addition to CA Group (Configuration Drift)

**Condition:** User is manually added to the CA group in Entra ID but is not in `members.auto.tfvars`.

### Setup
1. Pick a user who has an HS RBAC role and is in `members.auto.tfvars`.
2. Remove them from `members.auto.tfvars` (locally, do not push).
3. Ensure they remain in the live CA group.

### Run
```powershell
.\scanner\Invoke-ComplianceScanner.ps1 -SubscriptionIds "<sub-id>" -CAGroupId "<group-id>" -DryRun
# Confirm SC-02 is reported, then run without -DryRun
```

### Expected Result
- Scanner detects the user is in the live group but not in TF state.
- A PR is raised to add the user to `members.auto.tfvars` (aligning Terraform with reality).
- No change to the live group.

### Cleanup
- Revert `members.auto.tfvars` to its original state.
- Merge or close the PR.

---

## SC-03 — User Removed from CA Group but Still Has Azure Access

**Condition:** User is in `members.auto.tfvars` and has HS RBAC, but has been removed from the live CA group.

### Setup
1. Pick a user who is in `members.auto.tfvars` and has an HS RBAC role.
2. Remove them from the live CA group directly in Entra ID (do not touch `members.auto.tfvars`).

```powershell
Remove-MgGroupMemberByRef -GroupId "<ca-group-object-id>" -DirectoryObjectId "<user-object-id>"
```

### Run
```powershell
.\scanner\Invoke-ComplianceScanner.ps1 -SubscriptionIds "<sub-id>" -CAGroupId "<group-id>" -DryRun
# Confirm SC-03 is reported, then run without -DryRun
```

### Expected Result
- User is **immediately** re-added to the live CA group.
- An audit PR is created and **auto-merged**.
- `terraform-apply` workflow triggers and reconciles Terraform state.
- No manual approval required.

### Cleanup
- No action needed — the auto-remediation restores the correct state.

---

## SC-04 — Large-Scale Drift (Bulk Threshold Exceeded)

**Condition:** Number of drifted users exceeds `BulkDriftThreshold` (default: 5).

### Setup
1. Remove 6 or more users from the live CA group directly in Entra ID.

### Run
```powershell
.\scanner\Invoke-ComplianceScanner.ps1 -SubscriptionIds "<sub-id>" -CAGroupId "<group-id>" -DryRun
```

### Expected Result
- Scanner detects bulk drift and enters **investigation mode**.
- No automatic remediation is performed.
- Output lists all drifted users for manual review.
- Findings are written to `scanner-results.json`.

### Cleanup
- Re-add the removed users manually or reduce the threshold temporarily for testing:
```powershell
.\scanner\Invoke-ComplianceScanner.ps1 -SubscriptionIds "<sub-id>" -CAGroupId "<group-id>" -BulkDriftThreshold 20 -DryRun
```

---

## SC-05 — User Loses All Azure Roles

**Condition:** User is in `members.auto.tfvars` and the live CA group but no longer holds any HS RBAC roles.

### Setup
1. Pick a user who is in `members.auto.tfvars` and the live CA group.
2. Remove **all** HS RBAC role assignments for that user.

### Run
```powershell
.\scanner\Invoke-ComplianceScanner.ps1 -SubscriptionIds "<sub-id>" -CAGroupId "<group-id>" -DryRun
# Confirm SC-05 is reported, then run without -DryRun
```

### Expected Result
- Scanner detects the user has no HS roles.
- A PR is raised to remove the user from `members.auto.tfvars`.
- After PR is reviewed and merged, `terraform-apply` removes them from the live CA group.

### Cleanup
- Re-assign the RBAC role if needed.
- Merge or close the PR.

---

## SC-06 — Compliant (Baseline Verification)

**Condition:** All users with HS RBAC are in the CA group and TF state matches the live group.

### Setup
- Ensure all users are correctly configured (no drift from previous tests).

### Run
```powershell
.\scanner\Invoke-ComplianceScanner.ps1 -SubscriptionIds "<sub-id>" -CAGroupId "<group-id>" -DryRun
```

### Expected Result
- Scanner reports `OverallStatus: Compliant`.
- Zero findings, zero TF drift.
- No PRs raised.

---

## Verifying the Full Pipeline (End-to-End)

To confirm the entire automation chain works:

1. Trigger SC-03 (remove a user from the live CA group).
2. Run the **compliance-scanner** GitHub Actions workflow manually.
3. Confirm the user is re-added to the CA group within the workflow run.
4. Confirm an audit PR is created and auto-merged.
5. Confirm the **terraform-apply** workflow triggers automatically after the merge.
6. Confirm `member_count` in the apply output matches the expected number.
