<#
.SYNOPSIS
    Compliance scanner for CA Group automation.
    Validates alignment between Azure RBAC assignments and CA group membership.

.DESCRIPTION
    Compares three data sources:
      1. Live Azure RBAC assignments across HS subscriptions
      2. Live Entra ID CA group membership
      3. Terraform-managed membership (from tfstate)

    Detects and remediates the following scenarios:
      SC-01  User has RBAC but is not in CA group             (auto-remediate)
      SC-02  User added to CA group manually, not in TF state (raise PR)
      SC-03  User removed from CA group, still has RBAC       (raise PR - HIGH RISK)
      SC-04  Bulk drift above threshold                       (investigation mode)
      SC-05  User in CA group with no HS RBAC roles           (raise PR)
      SC-06  User in CA group with RBAC roles                 (compliant)

.PARAMETER SubscriptionIds
    One or more HS Azure subscription IDs to scan for RBAC assignments.

.PARAMETER CAGroupId
    Object ID of the Conditional Access protection group in Entra ID.

.PARAMETER TerraformStatePath
    Path to the terraform.tfstate file for the ca-group module.

.PARAMETER MembersVarsPath
    Path to members.auto.tfvars — modified by remediation PRs.

.PARAMETER BulkDriftThreshold
    Number of drifted users that triggers investigation mode. Default: 5.

.PARAMETER DryRun
    Report findings without making any changes or raising PRs.

.PARAMETER GitHubToken
    Personal access token with repo scope (required for PR creation).

.PARAMETER GitHubRepo
    GitHub repository in owner/repo format e.g. "contoso/ca-automation".

.PARAMETER GitHubBaseBranch
    Base branch for remediation PRs. Default: main.

.PARAMETER OutputPath
    Optional path to write the results as a JSON file.

.EXAMPLE
    # Dry run — report only
    .\Invoke-ComplianceScanner.ps1 `
        -SubscriptionIds "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -CAGroupId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
        -DryRun

.EXAMPLE
    # Full run with GitHub PR remediation
    .\Invoke-ComplianceScanner.ps1 `
        -SubscriptionIds "sub-id-1","sub-id-2" `
        -CAGroupId "group-object-id" `
        -GitHubToken $env:GITHUB_TOKEN `
        -GitHubRepo "contoso/ca-automation"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$SubscriptionIds,
    [Parameter(Mandatory)][string]$CAGroupId,
    [string]$TerraformStatePath = "$PSScriptRoot/../terraform/ca-group/terraform.tfstate",
    [string]$MembersVarsPath    = "$PSScriptRoot/../terraform/ca-group/members.auto.tfvars",
    [int]$BulkDriftThreshold    = 5,
    [switch]$DryRun,
    [string]$GitHubToken,
    [string]$GitHubRepo,
    [string]$GitHubBaseBranch   = "main",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Data collection ──────────────────────────────────────────────────────────

function Format-Scope {
    param([string]$Scope)
    # /subscriptions/{id}                                        → Subscription
    # /subscriptions/{id}/resourceGroups/{rg}                   → RG: {rg}
    # /subscriptions/{id}/resourceGroups/{rg}/providers/.../{n} → Resource: {n}
    if ($Scope -match '^/subscriptions/[^/]+$') {
        return "Subscription"
    } elseif ($Scope -match '^/subscriptions/[^/]+/resourceGroups/([^/]+)$') {
        return "RG: $($Matches[1])"
    } elseif ($Scope -match '/([^/]+)$') {
        return "Resource: $($Matches[1])"
    }
    return $Scope
}

function Get-HSRBACUsers {
    param([string[]]$SubscriptionIds)

    Write-Verbose "Querying RBAC assignments across $($SubscriptionIds.Count) subscription(s)..."
    $userMap = @{}
    $originalContext = Get-AzContext

    foreach ($subId in $SubscriptionIds) {
        # Set context per subscription so Get-AzRoleAssignment returns ALL assignments
        # at every scope level — subscription, resource group, and resource.
        # Using -Scope "/subscriptions/$subId" would only return subscription-level assignments.
        Set-AzContext -SubscriptionId $subId -ErrorAction Stop | Out-Null
        Write-Verbose "  Scanning subscription $subId..."

        $assignments = Get-AzRoleAssignment -ErrorAction Stop |
            Where-Object { $_.ObjectType -eq "User" }

        foreach ($a in $assignments) {
            if (-not $userMap.ContainsKey($a.ObjectId)) {
                $userMap[$a.ObjectId] = [PSCustomObject]@{
                    ObjectId    = $a.ObjectId
                    DisplayName = $a.DisplayName
                    UPN         = $a.SignInName
                    Roles       = [System.Collections.Generic.List[PSCustomObject]]::new()
                }
            }
            $entry = "$($a.RoleDefinitionName) @ $(Format-Scope $a.Scope)"
            if ($entry -notin ($userMap[$a.ObjectId].Roles | ForEach-Object { "$($_.Role) @ $($_.Scope)" })) {
                $userMap[$a.ObjectId].Roles.Add([PSCustomObject]@{
                    Role  = $a.RoleDefinitionName
                    Scope = Format-Scope $a.Scope
                })
            }
        }
    }

    # Restore original context
    if ($originalContext) {
        Set-AzContext -Context $originalContext -ErrorAction SilentlyContinue | Out-Null
    }

    Write-Verbose "Found $($userMap.Count) unique user(s) with RBAC access across all scope levels."
    return $userMap
}

function Get-UserDisplayInfo {
    # Fallback lookup for users not in the RBAC map (e.g. SC-05 users with no roles)
    param([string]$ObjectId)
    try {
        $u = Get-MgUser -UserId $ObjectId -Property DisplayName,UserPrincipalName -ErrorAction SilentlyContinue
        if ($u) {
            return [PSCustomObject]@{ DisplayName = $u.DisplayName; UPN = $u.UserPrincipalName; Roles = @() }
        }
    } catch {}
    return [PSCustomObject]@{ DisplayName = $ObjectId; UPN = ""; Roles = @() }
}

function Get-CAGroupLiveMembers {
    param([string]$CAGroupId)

    Write-Verbose "Reading live CA group members from Entra ID..."
    $members = Get-MgGroupMember -GroupId $CAGroupId -All
    $ids = @($members | Select-Object -ExpandProperty Id)
    Write-Verbose "CA group has $($ids.Count) live member(s)."
    return [string[]]$ids
}

function Get-TerraformManagedMembers {
    param([string]$StatePath, [string]$VarsPath)

    # Prefer tfstate (authoritative) — fall back to members.auto.tfvars (available in CI)
    if (Test-Path $StatePath) {
        $state = Get-Content $StatePath -Raw | ConvertFrom-Json
        $members = @(
            $state.resources |
                Where-Object { $_.type -eq "azuread_group_member" } |
                ForEach-Object { $_.instances } |
                ForEach-Object { $_.attributes.member_object_id } |
                Where-Object { $_ }
        )
        Write-Verbose "Terraform state contains $($members.Count) managed member(s)."
        return [string[]]$members
    }

    if (Test-Path $VarsPath) {
        Write-Verbose "Terraform state not found — falling back to $VarsPath"
        $content = Get-Content $VarsPath -Raw
        $members = [regex]::Matches($content, '"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"') |
            ForEach-Object { $_.Groups[1].Value }
        Write-Verbose "members.auto.tfvars contains $(@($members).Count) managed member(s)."
        return [string[]]@($members)
    }

    Write-Warning "Neither tfstate nor members.auto.tfvars found — treating TF state as empty."
    return [string[]]@()
}

# ── Core compliance logic ────────────────────────────────────────────────────

function Invoke-ComplianceCheck {
    param(
        [string[]]$RBACUsers,
        [string[]]$LiveCAMembers,
        [string[]]$TFCAMembers,
        [int]$BulkDriftThreshold
    )

    $findings   = [System.Collections.Generic.List[PSObject]]::new()
    $driftItems = [System.Collections.Generic.List[PSObject]]::new()
    $nonCompliant = [System.Collections.Generic.HashSet[string]]::new()

    # SC-01: User has RBAC but is NOT in the CA group
    foreach ($userId in $RBACUsers) {
        if ($userId -notin $LiveCAMembers) {
            [void]$nonCompliant.Add($userId)
            $findings.Add([PSCustomObject]@{
                UserId      = $userId
                Scenario    = "Scenario1"
                RiskLevel   = "Low"
                Remediation = "AddToCAGroup"
                Description = "User has HS RBAC access but is not in the CA protection group"
            })
        }
    }

    # SC-03: User was TF-managed in CA group, removed from live group, still has RBAC
    # Escalates SC-01 to SC-03 when the removal was deliberate (user was in TF state)
    foreach ($userId in $TFCAMembers) {
        if ($userId -notin $LiveCAMembers -and $userId -in $RBACUsers) {
            $existing = $findings | Where-Object { $_.UserId -eq $userId }
            if ($existing) {
                $existing.Scenario    = "Scenario3"
                $existing.RiskLevel   = "High"
                $existing.Description = "User removed from CA group while retaining HS RBAC access (HIGH RISK)"
            } else {
                [void]$nonCompliant.Add($userId)
                $findings.Add([PSCustomObject]@{
                    UserId      = $userId
                    Scenario    = "Scenario3"
                    RiskLevel   = "High"
                    Remediation = "AddToCAGroup"
                    Description = "User removed from CA group while retaining HS RBAC access (HIGH RISK)"
                })
            }
        }
    }

    # SC-02: User is in live CA group but NOT in TF state — manual addition
    foreach ($userId in $LiveCAMembers) {
        if ($userId -notin $TFCAMembers) {
            $driftItems.Add([PSCustomObject]@{
                UserId      = $userId
                Scenario    = "Scenario2"
                RiskLevel   = "Low"
                Remediation = "RaisePR"
                Description = "User added to CA group manually — not reflected in Terraform state"
            })
        }
    }

    # SC-05: User is TF-managed in CA group but holds no HS RBAC roles
    foreach ($userId in $TFCAMembers) {
        if ($userId -notin $RBACUsers -and $userId -in $LiveCAMembers) {
            if (-not ($findings | Where-Object { $_.UserId -eq $userId })) {
                $findings.Add([PSCustomObject]@{
                    UserId      = $userId
                    Scenario    = "Scenario5"
                    RiskLevel   = "VeryLow"
                    Remediation = "RemoveFromCAGroup"
                    Description = "User has no HS RBAC roles — CA group membership no longer required"
                })
            }
        }
    }

    # SC-04: Bulk drift — switch to investigation mode, block auto-remediation
    $totalDrift = $findings.Count + $driftItems.Count
    $mode = if ($totalDrift -ge $BulkDriftThreshold) { "Investigation" } else { "Normal" }

    if ($mode -eq "Investigation") {
        Write-Warning "Bulk drift threshold ($BulkDriftThreshold) exceeded ($totalDrift items). Entering Investigation mode — no auto-remediation."
        $findings   | ForEach-Object { $_.Remediation = "ManualReview" }
        $driftItems | ForEach-Object { $_.Remediation = "ManualReview" }
    }

    $overallStatus = if ($findings.Count -eq 0 -and $driftItems.Count -eq 0) {
        "Compliant"
    } else {
        "NonCompliant"
    }

    return [PSCustomObject]@{
        OverallStatus            = $overallStatus
        Mode                     = $mode
        AutoRemediationTriggered = ($mode -eq "Normal") -and ($findings.Count -gt 0)
        NonCompliantUsers        = [string[]]$nonCompliant
        Findings                 = $findings.ToArray()
        TerraformDrift           = $driftItems.ToArray()
    }
}

# ── GitHub PR helpers ────────────────────────────────────────────────────────

function New-GitHubRemediationPR {
    param(
        [string]$Token,
        [string]$Repo,
        [string]$BaseBranch,
        [string]$BranchName,
        [string]$FilePath,       # repo-relative path e.g. terraform/ca-group/members.auto.tfvars
        [string]$FileContent,
        [string]$CommitMessage,
        [string]$PRTitle,
        [string]$PRBody
    )

    $headers = @{
        Authorization          = "Bearer $Token"
        Accept                 = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    $baseUri = "https://api.github.com/repos/$Repo"

    # Get the SHA of the base branch tip
    $ref     = Invoke-RestMethod "$baseUri/git/ref/heads/$BaseBranch" -Headers $headers
    $baseSha = $ref.object.sha

    # Create the remediation branch
    Invoke-RestMethod "$baseUri/git/refs" -Method Post -Headers $headers `
        -ContentType "application/json" `
        -Body (@{ ref = "refs/heads/$BranchName"; sha = $baseSha } | ConvertTo-Json) | Out-Null

    # Get the current file SHA (required by the GitHub contents API for updates)
    $fileInfo = Invoke-RestMethod "$baseUri/contents/$FilePath" -Headers $headers
    $fileSha  = $fileInfo.sha

    # Commit the updated file onto the new branch
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($FileContent))
    Invoke-RestMethod "$baseUri/contents/$FilePath" -Method Put -Headers $headers `
        -ContentType "application/json" `
        -Body (@{
            message = $CommitMessage
            content = $encoded
            sha     = $fileSha
            branch  = $BranchName
        } | ConvertTo-Json) | Out-Null

    # Open the PR
    $pr = Invoke-RestMethod "$baseUri/pulls" -Method Post -Headers $headers `
        -ContentType "application/json" `
        -Body (@{
            title = $PRTitle
            body  = $PRBody
            head  = $BranchName
            base  = $BaseBranch
        } | ConvertTo-Json)

    return $pr.html_url
}

function Build-MembersBlock {
    param([string[]]$Members)

    if ($Members.Count -eq 0) {
        return "members = []"
    }
    $lines = $Members | ForEach-Object { "  `"$_`"," }
    return "members = [`n$($lines -join "`n")`n]"
}

function Set-MembersInFile {
    param([string]$Content, [string[]]$Members)
    return $Content -replace '(?s)members\s*=\s*\[.*?\]', (Build-MembersBlock $Members)
}

# ── Remediation dispatcher ───────────────────────────────────────────────────

function Invoke-Remediation {
    param(
        [PSObject]$CheckResult,
        [string]$CAGroupId,
        [string]$MembersVarsPath,
        [string[]]$CurrentTFMembers,
        [string]$GitHubToken,
        [string]$GitHubRepo,
        [string]$GitHubBaseBranch,
        [switch]$DryRun
    )

    if ($CheckResult.Mode -eq "Investigation") {
        Write-Host ""
        Write-Host "  [!] Investigation mode — manual review required. No automated remediation." -ForegroundColor Magenta
        return
    }

    $timestamp      = Get-Date -Format "yyyyMMdd-HHmmss"
    $varsContent    = Get-Content $MembersVarsPath -Raw
    $hasPRSupport   = $GitHubToken -and $GitHubRepo

    # ── Findings ────────────────────────────────────────────────────────────
    foreach ($finding in $CheckResult.Findings) {
        $userId = $finding.UserId

        switch ($finding.Scenario) {

            "Scenario1" {
                Write-Host "  [SC-01] Auto-remediating: adding $userId to CA group directly..." -ForegroundColor Yellow
                if (-not $DryRun) {
                    New-MgGroupMember -GroupId $CAGroupId -DirectoryObjectId $userId
                }

                if ($hasPRSupport) {
                    $newMembers = @($CurrentTFMembers) + $userId | Select-Object -Unique
                    $branch     = "remediation/sc01-add-$($userId.Substring(0,8))-$timestamp"
                    Write-Host "  [SC-01] Raising PR to align Terraform state..." -ForegroundColor Yellow
                    if (-not $DryRun) {
                        $url = New-GitHubRemediationPR `
                            -Token $GitHubToken -Repo $GitHubRepo -BaseBranch $GitHubBaseBranch `
                            -BranchName $branch `
                            -FilePath "terraform/ca-group/members.auto.tfvars" `
                            -FileContent (Set-MembersInFile $varsContent $newMembers) `
                            -CommitMessage "remediation: add $userId to CA group (SC-01)" `
                            -PRTitle "[SC-01] Add $userId to CA group (auto-remediation)" `
                            -PRBody "## Auto-Remediation — Scenario 1`n`nUser \`\`$userId\`\` had HS RBAC access but was not a member of the CA protection group.`n`nThe user has been added to the CA group directly. This PR aligns Terraform state.`n`n**Risk Level:** Low  `n**Automated action:** User added to CA group  `n**Required action:** Approve PR to align Terraform state"
                        Write-Host "  [SC-01] PR created: $url" -ForegroundColor Green
                    }
                }
            }

            "Scenario3" {
                Write-Host "  [SC-03] HIGH RISK: $userId removed from CA group with active RBAC — raising PR for review..." -ForegroundColor Red
                if ($DryRun) {
                    Write-Host "  [SC-03] [DryRun] Would raise PR to re-add $userId to CA group." -ForegroundColor DarkGray
                } elseif ($hasPRSupport) {
                    $newMembers = @($CurrentTFMembers) + $userId | Select-Object -Unique
                    $branch     = "remediation/sc03-review-$($userId.Substring(0,8))-$timestamp"
                    $url = New-GitHubRemediationPR `
                        -Token $GitHubToken -Repo $GitHubRepo -BaseBranch $GitHubBaseBranch `
                        -BranchName $branch `
                        -FilePath "terraform/ca-group/members.auto.tfvars" `
                        -FileContent (Set-MembersInFile $varsContent $newMembers) `
                        -CommitMessage "remediation: review SC-03 for $userId" `
                        -PRTitle "[SC-03] ⚠ HIGH RISK — Review CA group removal for $userId" `
                        -PRBody "## ⚠ High Risk — Scenario 3`n`nUser \`\`$userId\`\` has been **removed from the CA protection group** but **still retains HS RBAC access**.`n`nThis means the user can access HS Azure resources without Conditional Access enforcement.`n`n### Required Action`n- [ ] Review whether this user's RBAC access is still valid`n- [ ] If access is still valid: approve this PR to re-add to CA group`n- [ ] If access should no longer exist: remove RBAC assignments and close this PR`n`n**Risk Level:** High  `n**Do not approve without reviewing the user's current access.**"
                    Write-Host "  [SC-03] PR created: $url" -ForegroundColor Green
                } else {
                    Write-Warning "  [SC-03] No GitHub config — cannot raise PR. Manual intervention required for $userId."
                }
            }

            "Scenario5" {
                Write-Host "  [SC-05] $userId has no HS roles — raising PR to remove from CA group..." -ForegroundColor Cyan
                if ($DryRun) {
                    Write-Host "  [SC-05] [DryRun] Would raise PR to remove $userId from CA group." -ForegroundColor DarkGray
                } elseif ($hasPRSupport) {
                    $newMembers = @($CurrentTFMembers) | Where-Object { $_ -ne $userId }
                    $branch     = "remediation/sc05-remove-$($userId.Substring(0,8))-$timestamp"
                    if (-not $DryRun) {
                        $url = New-GitHubRemediationPR `
                            -Token $GitHubToken -Repo $GitHubRepo -BaseBranch $GitHubBaseBranch `
                            -BranchName $branch `
                            -FilePath "terraform/ca-group/members.auto.tfvars" `
                            -FileContent (Set-MembersInFile $varsContent $newMembers) `
                            -CommitMessage "remediation: remove $userId from CA group (SC-05)" `
                            -PRTitle "[SC-05] Remove $userId from CA group (no active roles)" `
                            -PRBody "## Least Privilege Cleanup — Scenario 5`n`nUser \`\`$userId\`\` is a member of the CA protection group but holds **no HS RBAC roles**.`n`nCA group membership is no longer required under least privilege principles. This PR removes the user.`n`n**Risk Level:** Very Low  `n**Action:** Remove user from CA group"
                        Write-Host "  [SC-05] PR created: $url" -ForegroundColor Green
                    }
                }
            }
        }
    }

    # ── Terraform drift ──────────────────────────────────────────────────────
    foreach ($drift in $CheckResult.TerraformDrift) {
        if ($drift.Scenario -ne "Scenario2") { continue }

        $userId = $drift.UserId
        Write-Host "  [SC-02] Manual CA group addition for $userId — raising PR to align Terraform state..." -ForegroundColor Yellow
        if ($DryRun) {
            Write-Host "  [SC-02] [DryRun] Would raise PR to align Terraform state for $userId." -ForegroundColor DarkGray
        } elseif ($hasPRSupport) {
            $newMembers = @($CurrentTFMembers) + $userId | Select-Object -Unique
            $branch     = "remediation/sc02-drift-$($userId.Substring(0,8))-$timestamp"
            $url = New-GitHubRemediationPR `
                -Token $GitHubToken -Repo $GitHubRepo -BaseBranch $GitHubBaseBranch `
                -BranchName $branch `
                -FilePath "terraform/ca-group/members.auto.tfvars" `
                -FileContent (Set-MembersInFile $varsContent $newMembers) `
                -CommitMessage "remediation: align TF state for manual CA addition of $userId (SC-02)" `
                -PRTitle "[SC-02] Align Terraform state — manual CA group addition for $userId" `
                -PRBody "## Terraform Drift — Scenario 2`n`nUser \`\`$userId\`\` was added to the CA protection group **manually** (outside of Terraform).`n`nSecurity is not impacted, but Terraform state is inconsistent. This PR codifies the manual change.`n`n**Risk Level:** Low  `n**Action:** Approve to align Terraform with current live state, or close to investigate and remove the manual addition"
            Write-Host "  [SC-02] PR created: $url" -ForegroundColor Green
        } else {
            Write-Warning "  [SC-02] No GitHub config — cannot raise PR for drift on $userId."
        }
    }
}

# ── Main ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "CA Group Compliance Scanner" -ForegroundColor White
Write-Host "Subscriptions : $($SubscriptionIds -join ', ')" -ForegroundColor DarkGray
Write-Host "CA Group      : $CAGroupId"                     -ForegroundColor DarkGray
Write-Host "TF State      : $TerraformStatePath"            -ForegroundColor DarkGray
if ($DryRun) {
    Write-Host "Mode          : DRY RUN — no changes will be made" -ForegroundColor Yellow
}
Write-Host ""

# Collect live state
$rbacUserMap   = Get-HSRBACUsers             -SubscriptionIds $SubscriptionIds
$rbacUsers     = [string[]]$rbacUserMap.Keys
$liveCAMembers = Get-CAGroupLiveMembers      -CAGroupId $CAGroupId
$tfCAMembers   = Get-TerraformManagedMembers -StatePath $TerraformStatePath -VarsPath $MembersVarsPath

# Run compliance check
$result = Invoke-ComplianceCheck `
    -RBACUsers $rbacUsers `
    -LiveCAMembers $liveCAMembers `
    -TFCAMembers $tfCAMembers `
    -BulkDriftThreshold $BulkDriftThreshold

# Enrich findings with display name, UPN and roles
foreach ($finding in $result.Findings) {
    $info = if ($rbacUserMap.ContainsKey($finding.UserId)) {
        $rbacUserMap[$finding.UserId]
    } else {
        Get-UserDisplayInfo -ObjectId $finding.UserId
    }
    $finding | Add-Member -NotePropertyName DisplayName -NotePropertyValue $info.DisplayName          -Force
    $finding | Add-Member -NotePropertyName UPN         -NotePropertyValue $info.UPN                  -Force
    $finding | Add-Member -NotePropertyName RolesHeld -NotePropertyValue (
        ($info.Roles | ForEach-Object { "$($_.Role) @ $($_.Scope)" }) -join " | "
    ) -Force
}
foreach ($drift in $result.TerraformDrift) {
    $info = if ($rbacUserMap.ContainsKey($drift.UserId)) {
        $rbacUserMap[$drift.UserId]
    } else {
        Get-UserDisplayInfo -ObjectId $drift.UserId
    }
    $drift | Add-Member -NotePropertyName DisplayName -NotePropertyValue $info.DisplayName -Force
    $drift | Add-Member -NotePropertyName UPN         -NotePropertyValue $info.UPN         -Force
    $drift | Add-Member -NotePropertyName RolesHeld   -NotePropertyValue (
        ($info.Roles | ForEach-Object { "$($_.Role) @ $($_.Scope)" }) -join " | "
    ) -Force
}

# Print results
Write-Host "── Results ──────────────────────────────────────────────────────" -ForegroundColor White
Write-Host "Overall Status : $($result.OverallStatus)" -ForegroundColor $(if ($result.OverallStatus -eq "Compliant") { "Green" } else { "Red" })
Write-Host "Mode           : $($result.Mode)"          -ForegroundColor $(if ($result.Mode -eq "Investigation") { "Magenta" } else { "White" })
Write-Host "Findings       : $($result.Findings.Count)"
Write-Host "TF Drift       : $($result.TerraformDrift.Count)"

if ($result.Findings.Count -gt 0) {
    Write-Host ""
    Write-Host "Findings:" -ForegroundColor Yellow
    $result.Findings | Format-Table DisplayName, UPN, Scenario, RiskLevel, RolesHeld, Remediation -AutoSize | Out-Host
}

if ($result.TerraformDrift.Count -gt 0) {
    Write-Host "Terraform Drift:" -ForegroundColor Yellow
    $result.TerraformDrift | Format-Table DisplayName, UPN, Scenario, RolesHeld, Remediation -AutoSize | Out-Host
}

# Remediate
if ($result.OverallStatus -ne "Compliant") {
    Write-Host "── Remediation ──────────────────────────────────────────────────" -ForegroundColor White
    Invoke-Remediation `
        -CheckResult $result `
        -CAGroupId $CAGroupId `
        -MembersVarsPath $MembersVarsPath `
        -CurrentTFMembers $tfCAMembers `
        -GitHubToken $GitHubToken `
        -GitHubRepo $GitHubRepo `
        -GitHubBaseBranch $GitHubBaseBranch `
        -DryRun:$DryRun
}

# Write JSON output
if ($OutputPath) {
    $result | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath
    Write-Host ""
    Write-Host "Results written to: $OutputPath" -ForegroundColor DarkGray
}

Write-Host ""

# Exit codes: 0 = clean/remediated, 1 = non-compliant no remediation, 2 = investigation required
if ($result.Mode -eq "Investigation") {
    exit 2
} elseif ($result.OverallStatus -ne "Compliant" -and -not $result.AutoRemediationTriggered) {
    exit 1
} else {
    exit 0
}
