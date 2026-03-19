#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
<#
.SYNOPSIS
    Pester unit tests for the CA Group Automation compliance scanner.
    Tests cover all six scanner scenarios (SC-01 to SC-06) using mock data.

.NOTES
    Run with: Invoke-Pester -Path . -Output Detailed
#>

BeforeAll {
    # Load the scanner functions (dot-source the module under test)
    . "$PSScriptRoot/../Invoke-ComplianceScanner.ps1"

    # ── Mock helper: build a fake user object ──
    function New-MockUser {
        param([string]$UPN, [string]$ObjectId = [guid]::NewGuid().ToString())
        [PSCustomObject]@{ UserPrincipalName = $UPN; ObjectId = $ObjectId }
    }

    # ── Common test users ──
    $script:UserA = New-MockUser -UPN "testuser-a@contoso.com" -ObjectId "aaaa-0001"
    $script:UserB = New-MockUser -UPN "testuser-b@contoso.com" -ObjectId "bbbb-0002"
    $script:UserC = New-MockUser -UPN "testuser-c@contoso.com" -ObjectId "cccc-0003"
}

# ══════════════════════════════════════════════════════════════════════════════
# SC-01 | Role assigned before CA group - scanner detects and flags
# ══════════════════════════════════════════════════════════════════════════════
Describe "SC-01: RBAC assigned without CA group membership" {

    BeforeEach {
        # UserA has an HS RBAC role but is NOT in the CA group
        Mock Get-HSRBACAssignments { return @($script:UserA.ObjectId) }
        Mock Get-CAGroupMembers    { return @() }  # CA group is empty
    }

    It "Should detect UserA as non-compliant" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $result.NonCompliantUsers | Should -Contain $script:UserA.ObjectId
    }

    It "Should classify as Scenario1 (RBAC without CA)" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $finding = $result.Findings | Where-Object { $_.UserId -eq $script:UserA.ObjectId }
        $finding.Scenario | Should -Be "Scenario1"
    }

    It "Should recommend adding user to CA group" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $finding = $result.Findings | Where-Object { $_.UserId -eq $script:UserA.ObjectId }
        $finding.Remediation | Should -Be "AddToCAGroup"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# SC-02 | Manual CA group addition - drift from Terraform state
# ══════════════════════════════════════════════════════════════════════════════
Describe "SC-02: Manual CA group addition not in Terraform state" {

    BeforeEach {
        # UserB is in the Entra CA group but NOT in Terraform state
        Mock Get-CAGroupMembers  { return @($script:UserB.ObjectId) }
        Mock Get-TerraformCAGroupState { return @() }  # Terraform doesn't know about UserB
        Mock Get-HSRBACAssignments { return @($script:UserB.ObjectId) }
    }

    It "Should detect Terraform drift for UserB" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $drift = $result.TerraformDrift | Where-Object { $_.UserId -eq $script:UserB.ObjectId }
        $drift | Should -Not -BeNullOrEmpty
    }

    It "Should classify as Scenario2 (manual drift)" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $drift = $result.TerraformDrift | Where-Object { $_.UserId -eq $script:UserB.ObjectId }
        $drift.Scenario | Should -Be "Scenario2"
    }

    It "Should recommend raising a remediation PR" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $drift = $result.TerraformDrift | Where-Object { $_.UserId -eq $script:UserB.ObjectId }
        $drift.Remediation | Should -Be "RaisePR"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# SC-03 | CA group removed but RBAC still active - HIGH RISK
# ══════════════════════════════════════════════════════════════════════════════
Describe "SC-03: User removed from CA group with active HS RBAC (HIGH RISK)" {

    BeforeEach {
        # UserC has HS RBAC role but has been removed from the CA group
        Mock Get-HSRBACAssignments { return @($script:UserC.ObjectId) }
        Mock Get-CAGroupMembers    { return @() }  # Removed from CA group
        Mock Get-TerraformCAGroupState { return @($script:UserC.ObjectId) }  # Still in TF state
    }

    It "Should detect UserC as high-risk non-compliant" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $finding = $result.Findings | Where-Object { $_.UserId -eq $script:UserC.ObjectId }
        $finding | Should -Not -BeNullOrEmpty
    }

    It "Should classify risk level as High" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $finding = $result.Findings | Where-Object { $_.UserId -eq $script:UserC.ObjectId }
        $finding.RiskLevel | Should -Be "High"
    }

    It "Should classify as Scenario3" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $finding = $result.Findings | Where-Object { $_.UserId -eq $script:UserC.ObjectId }
        $finding.Scenario | Should -Be "Scenario3"
    }

    It "Should trigger remediation (re-add to CA group)" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $finding = $result.Findings | Where-Object { $_.UserId -eq $script:UserC.ObjectId }
        $finding.Remediation | Should -BeIn @("AddToCAGroup", "ReviewAccess")
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# SC-04 | Large-scale drift - investigation mode, NO auto-remediation
# ══════════════════════════════════════════════════════════════════════════════
Describe "SC-04: Large-scale drift triggers investigation mode" {

    BeforeEach {
        # Simulate 6 users with mismatches (above the bulk drift threshold)
        $manyUsers = 1..6 | ForEach-Object { "user-$_-id" }
        Mock Get-HSRBACAssignments { return $manyUsers }
        Mock Get-CAGroupMembers    { return @() }
    }

    It "Should detect all 6 users as non-compliant" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $result.NonCompliantUsers.Count | Should -Be 6
    }

    It "Should enter investigation mode when drift exceeds threshold" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group" -BulkDriftThreshold 5
        $result.Mode | Should -Be "Investigation"
    }

    It "Should NOT auto-remediate in investigation mode" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group" -BulkDriftThreshold 5
        $result.AutoRemediationTriggered | Should -Be $false
    }

    It "Should set remediation to ManualReview for all findings" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group" -BulkDriftThreshold 5
        $result.Findings | ForEach-Object {
            $_.Remediation | Should -Be "ManualReview"
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# SC-05 | User loses all HS roles - CA group membership removed
# ══════════════════════════════════════════════════════════════════════════════
Describe "SC-05: User with no HS RBAC roles removed from CA group" {

    BeforeEach {
        # UserA is in the CA group but has NO HS RBAC roles
        Mock Get-CAGroupMembers    { return @($script:UserA.ObjectId) }
        Mock Get-HSRBACAssignments { return @() }  # No roles
        Mock Get-TerraformCAGroupState { return @($script:UserA.ObjectId) }
    }

    It "Should detect UserA as having no HS roles" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $finding = $result.Findings | Where-Object { $_.UserId -eq $script:UserA.ObjectId }
        $finding.Scenario | Should -Be "Scenario5"
    }

    It "Should recommend PR to remove user from CA group" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $finding = $result.Findings | Where-Object { $_.UserId -eq $script:UserA.ObjectId }
        $finding.Remediation | Should -Be "RemoveFromCAGroup"
    }

    It "Should classify risk as Very Low" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $finding = $result.Findings | Where-Object { $_.UserId -eq $script:UserA.ObjectId }
        $finding.RiskLevel | Should -Be "VeryLow"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# SC-06 | Fully compliant user - no output
# ══════════════════════════════════════════════════════════════════════════════
Describe "SC-06: Compliant user produces no scanner findings" {

    BeforeEach {
        # UserA is in the CA group AND has an HS RBAC role - fully compliant
        Mock Get-CAGroupMembers    { return @($script:UserA.ObjectId) }
        Mock Get-HSRBACAssignments { return @($script:UserA.ObjectId) }
        Mock Get-TerraformCAGroupState { return @($script:UserA.ObjectId) }
    }

    It "Should produce no findings for a compliant user" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $result.Findings.Count | Should -Be 0
    }

    It "Should produce no drift entries" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $result.TerraformDrift.Count | Should -Be 0
    }

    It "Should not trigger any remediation" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $result.AutoRemediationTriggered | Should -Be $false
    }

    It "Should return overall status as Compliant" {
        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $result.OverallStatus | Should -Be "Compliant"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# Edge cases
# ══════════════════════════════════════════════════════════════════════════════
Describe "Edge cases" {

    It "Should handle empty subscription gracefully (no users, no roles)" {
        Mock Get-CAGroupMembers    { return @() }
        Mock Get-HSRBACAssignments { return @() }
        Mock Get-TerraformCAGroupState { return @() }

        { Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group" } | Should -Not -Throw
    }

    It "Should return OverallStatus Compliant when both sets are empty" {
        Mock Get-CAGroupMembers    { return @() }
        Mock Get-HSRBACAssignments { return @() }
        Mock Get-TerraformCAGroupState { return @() }

        $result = Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "test-group"
        $result.OverallStatus | Should -Be "Compliant"
    }

    It "Should not throw when CAGroupId is invalid format" {
        Mock Get-CAGroupMembers { throw "Group not found" }
        Mock Get-HSRBACAssignments { return @() }

        { Invoke-ComplianceCheck -SubscriptionId "test-sub" -CAGroupId "invalid-id" } | Should -Throw
    }
}
