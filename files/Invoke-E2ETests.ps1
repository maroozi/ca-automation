<#
.SYNOPSIS
    End-to-end test runner for CA Group Automation compliance scenarios.
    Executes E2E-01 through E2E-05 against a test subscription.

.DESCRIPTION
    Each test function:
      1. Sets up initial state
      2. Performs the trigger action
      3. Runs the compliance scanner
      4. Asserts the expected final state
      5. Cleans up test resources

.PARAMETER TestSubscriptionId
    The Azure subscription ID to run tests against (must be a test subscription).

.PARAMETER TestCAGroupId
    Object ID of the test CA group in Entra ID.

.PARAMETER TestUserId
    Object ID of the test user in Entra ID.

.PARAMETER ScannerPath
    Path to the Invoke-ComplianceScanner.ps1 script.

.PARAMETER DryRun
    If true, prints actions without executing them (for review before first run).

.EXAMPLE
    .\Invoke-E2ETests.ps1 `
        -TestSubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -TestCAGroupId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
        -TestUserId "zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz" `
        -ScannerPath "../scanner/Invoke-ComplianceScanner.ps1"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TestSubscriptionId,
    [Parameter(Mandatory)][string]$TestCAGroupId,
    [Parameter(Mandatory)][string]$TestUserId,
    [string]$ScannerPath = "../scanner/Invoke-ComplianceScanner.ps1",
    [string]$TestRoleName = "Reader",  # Low-privilege role for test assignments
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Result tracking ────────────────────────────────────────────────────────────
$script:Results = [System.Collections.Generic.List[PSObject]]::new()
$script:PassCount = 0
$script:FailCount = 0

function Write-TestHeader { param([string]$Id, [string]$Name)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $Id | $Name" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Write-Pass { param([string]$Message)
    Write-Host "  [PASS] $Message" -ForegroundColor Green
}

function Write-Fail { param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Pass $Message
        $script:PassCount++
        return $true
    } else {
        Write-Fail $Message
        $script:FailCount++
        return $false
    }
}

function Record-Result {
    param([string]$TestId, [string]$Name, [bool]$Passed, [string]$Notes = "")
    $script:Results.Add([PSCustomObject]@{
        TestId = $TestId
        Name   = $Name
        Status = if ($Passed) { "PASS" } else { "FAIL" }
        Notes  = $Notes
    })
}

# ── Scanner wrapper ─────────────────────────────────────────────────────────
function Invoke-Scanner {
    Write-Host "  [Scanner] Running compliance check..." -ForegroundColor DarkGray
    if ($DryRun) {
        Write-Host "  [DryRun] Would invoke scanner here" -ForegroundColor Yellow
        return [PSCustomObject]@{ OverallStatus = "DryRun"; Findings = @(); TerraformDrift = @(); NonCompliantUsers = @() }
    }
    & $ScannerPath `
        -SubscriptionId $TestSubscriptionId `
        -CAGroupId $TestCAGroupId `
        -DryRun $false
}

# ── Azure helpers ───────────────────────────────────────────────────────────
function Add-UserToCAGroup {
    Write-Host "  [Setup] Adding test user to CA group..." -ForegroundColor DarkGray
    if (-not $DryRun) {
        Add-AzureADGroupMember -ObjectId $TestCAGroupId -RefObjectId $TestUserId
    }
}

function Remove-UserFromCAGroup {
    Write-Host "  [Setup] Removing test user from CA group..." -ForegroundColor DarkGray
    if (-not $DryRun) {
        try { Remove-AzureADGroupMember -ObjectId $TestCAGroupId -MemberId $TestUserId }
        catch { Write-Host "  [Info] User was not in CA group - skipping" -ForegroundColor DarkGray }
    }
}

function Add-UserRBACRole {
    Write-Host "  [Setup] Assigning RBAC role to test user..." -ForegroundColor DarkGray
    if (-not $DryRun) {
        New-AzRoleAssignment `
            -ObjectId $TestUserId `
            -RoleDefinitionName $TestRoleName `
            -Scope "/subscriptions/$TestSubscriptionId"
    }
}

function Remove-UserRBACRole {
    Write-Host "  [Cleanup] Removing RBAC role from test user..." -ForegroundColor DarkGray
    if (-not $DryRun) {
        try {
            Remove-AzRoleAssignment `
                -ObjectId $TestUserId `
                -RoleDefinitionName $TestRoleName `
                -Scope "/subscriptions/$TestSubscriptionId"
        } catch {
            Write-Host "  [Info] Role assignment not found - skipping" -ForegroundColor DarkGray
        }
    }
}

function Get-IsUserInCAGroup {
    if ($DryRun) { return $false }
    $members = Get-AzureADGroupMember -ObjectId $TestCAGroupId
    return ($members | Where-Object { $_.ObjectId -eq $TestUserId }) -ne $null
}

function Get-UserHasHSRole {
    if ($DryRun) { return $false }
    $assignments = Get-AzRoleAssignment -ObjectId $TestUserId -Scope "/subscriptions/$TestSubscriptionId"
    return ($assignments | Where-Object { $_.RoleDefinitionName -eq $TestRoleName }) -ne $null
}

# ══════════════════════════════════════════════════════════════════════════════
# E2E-01 | Standard provisioning - user gains compliant access
# ══════════════════════════════════════════════════════════════════════════════
function Test-E2E01 {
    Write-TestHeader "E2E-01" "Standard provisioning - user gains compliant access"
    $passed = $true

    try {
        # Precondition: clean state
        Remove-UserFromCAGroup
        Remove-UserRBACRole

        # Step 1: Add to CA group (simulates Terraform PR for CA group repo)
        Add-UserToCAGroup
        $inCAGroup = Get-IsUserInCAGroup
        if (-not (Assert-True $inCAGroup "User added to CA group")) { $passed = $false }

        # Step 2: Assign RBAC role (simulates Terraform PR for RBAC repo)
        Add-UserRBACRole
        $hasRole = Get-UserHasHSRole
        if (-not (Assert-True $hasRole "User has HS RBAC role")) { $passed = $false }

        # Step 3: Run scanner - should be clean
        $result = Invoke-Scanner
        if (-not (Assert-True ($result.Findings.Count -eq 0) "Scanner reports no findings")) { $passed = $false }
        if (-not (Assert-True ($result.OverallStatus -eq "Compliant" -or $result.OverallStatus -eq "DryRun") "Overall status is Compliant")) { $passed = $false }

    } catch {
        Write-Fail "Test threw exception: $_"
        $passed = $false
    } finally {
        Remove-UserFromCAGroup
        Remove-UserRBACRole
    }

    Record-Result "E2E-01" "Standard provisioning" $passed
}

# ══════════════════════════════════════════════════════════════════════════════
# E2E-02 | Scenario 1 - RBAC before CA group, auto-remediated
# ══════════════════════════════════════════════════════════════════════════════
function Test-E2E02 {
    Write-TestHeader "E2E-02" "Scenario 1 - RBAC before CA group, auto-remediated"
    $passed = $true

    try {
        Remove-UserFromCAGroup
        Remove-UserRBACRole

        # Assign RBAC without CA group (out-of-process)
        Add-UserRBACRole
        $inCAGroup = Get-IsUserInCAGroup
        if (-not (Assert-True (-not $inCAGroup) "Precondition: user NOT in CA group")) { $passed = $false }

        # Run scanner - should detect Scenario 1
        $result = Invoke-Scanner
        $finding = $result.Findings | Where-Object { $_.UserId -eq $TestUserId }
        if (-not (Assert-True ($finding -ne $null) "Scanner detects non-compliance")) { $passed = $false }
        if (-not $DryRun) {
            if (-not (Assert-True ($finding.Scenario -eq "Scenario1") "Classified as Scenario1")) { $passed = $false }
        }

        # After remediation, user should be in CA group
        if (-not $DryRun) {
            Start-Sleep -Seconds 5  # Allow remediation to run
            $inCAGroupAfter = Get-IsUserInCAGroup
            if (-not (Assert-True $inCAGroupAfter "User added to CA group by remediation")) { $passed = $false }
        }

    } catch {
        Write-Fail "Test threw exception: $_"
        $passed = $false
    } finally {
        Remove-UserFromCAGroup
        Remove-UserRBACRole
    }

    Record-Result "E2E-02" "Scenario 1 - RBAC before CA group" $passed
}

# ══════════════════════════════════════════════════════════════════════════════
# E2E-03 | Scenario 3 - CA removed with active RBAC (HIGH RISK)
# ══════════════════════════════════════════════════════════════════════════════
function Test-E2E03 {
    Write-TestHeader "E2E-03" "Scenario 3 - CA removed with RBAC active (HIGH RISK)"
    $passed = $true

    try {
        # Precondition: user is fully compliant
        Add-UserToCAGroup
        Add-UserRBACRole

        # Action: remove from CA group manually (out-of-process)
        Remove-UserFromCAGroup
        $inCAGroup = Get-IsUserInCAGroup
        if (-not (Assert-True (-not $inCAGroup) "Precondition: user removed from CA group")) { $passed = $false }

        $hasRole = Get-UserHasHSRole
        if (-not (Assert-True $hasRole "Precondition: user still has HS RBAC role")) { $passed = $false }

        # Run scanner - should detect HIGH RISK Scenario 3
        $result = Invoke-Scanner
        $finding = $result.Findings | Where-Object { $_.UserId -eq $TestUserId }
        if (-not (Assert-True ($finding -ne $null) "Scanner detects high-risk condition")) { $passed = $false }
        if (-not $DryRun) {
            if (-not (Assert-True ($finding.RiskLevel -eq "High") "Risk level classified as High")) { $passed = $false }
            if (-not (Assert-True ($finding.Scenario -eq "Scenario3") "Classified as Scenario3")) { $passed = $false }
        }

    } catch {
        Write-Fail "Test threw exception: $_"
        $passed = $false
    } finally {
        Remove-UserFromCAGroup
        Remove-UserRBACRole
    }

    Record-Result "E2E-03" "Scenario 3 - CA removed with active RBAC" $passed
}

# ══════════════════════════════════════════════════════════════════════════════
# E2E-04 | Scenario 5 - All roles revoked, CA group cleaned up
# ══════════════════════════════════════════════════════════════════════════════
function Test-E2E04 {
    Write-TestHeader "E2E-04" "Scenario 5 - Role revoked, CA group cleaned up"
    $passed = $true

    try {
        # Precondition: user is fully compliant
        Add-UserToCAGroup
        Add-UserRBACRole

        # Action: revoke all HS RBAC roles
        Remove-UserRBACRole
        $hasRole = Get-UserHasHSRole
        if (-not (Assert-True (-not $hasRole) "Precondition: user has no HS RBAC roles")) { $passed = $false }

        # Run scanner - should detect Scenario 5 and raise PR to remove from CA group
        $result = Invoke-Scanner
        $finding = $result.Findings | Where-Object { $_.UserId -eq $TestUserId }
        if (-not (Assert-True ($finding -ne $null) "Scanner detects user with no roles")) { $passed = $false }
        if (-not $DryRun) {
            if (-not (Assert-True ($finding.Scenario -eq "Scenario5") "Classified as Scenario5")) { $passed = $false }
            if (-not (Assert-True ($finding.Remediation -eq "RemoveFromCAGroup") "Remediation is RemoveFromCAGroup")) { $passed = $false }
        }

    } catch {
        Write-Fail "Test threw exception: $_"
        $passed = $false
    } finally {
        Remove-UserFromCAGroup
        Remove-UserRBACRole
    }

    Record-Result "E2E-04" "Scenario 5 - Role revoked, CA group cleaned up" $passed
}

# ══════════════════════════════════════════════════════════════════════════════
# E2E-05 | Full revocation - user removed from everything, clean state
# ══════════════════════════════════════════════════════════════════════════════
function Test-E2E05 {
    Write-TestHeader "E2E-05" "Full access revocation - clean final state"
    $passed = $true

    try {
        # Precondition: user is fully compliant
        Add-UserToCAGroup
        Add-UserRBACRole

        # Action: remove from everything (via Terraform apply simulation)
        Remove-UserFromCAGroup
        Remove-UserRBACRole

        $inCAGroup = Get-IsUserInCAGroup
        $hasRole   = Get-UserHasHSRole
        if (-not (Assert-True (-not $inCAGroup) "User not in CA group")) { $passed = $false }
        if (-not (Assert-True (-not $hasRole)   "User has no HS roles")) { $passed = $false }

        # Scanner should confirm clean state
        $result = Invoke-Scanner
        if (-not (Assert-True ($result.Findings.Count -eq 0) "Scanner reports no findings")) { $passed = $false }
        if (-not (Assert-True ($result.OverallStatus -eq "Compliant" -or $result.OverallStatus -eq "DryRun") "Overall status is Compliant")) { $passed = $false }

    } catch {
        Write-Fail "Test threw exception: $_"
        $passed = $false
    } finally {
        Remove-UserFromCAGroup
        Remove-UserRBACRole
    }

    Record-Result "E2E-05" "Full access revocation" $passed
}

# ══════════════════════════════════════════════════════════════════════════════
# Main execution
# ══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "CA Group Automation - End-to-End Test Runner" -ForegroundColor White
Write-Host "Subscription : $TestSubscriptionId" -ForegroundColor DarkGray
Write-Host "CA Group     : $TestCAGroupId" -ForegroundColor DarkGray
Write-Host "Test User    : $TestUserId" -ForegroundColor DarkGray
if ($DryRun) { Write-Host "Mode         : DRY RUN (no changes will be made)" -ForegroundColor Yellow }

if (-not $DryRun) {
    Import-Module AzureAD -ErrorAction Stop
    Connect-AzAccount -ErrorAction Stop
    Set-AzContext -SubscriptionId $TestSubscriptionId
}

Test-E2E01
Test-E2E02
Test-E2E03
Test-E2E04
Test-E2E05

# ── Results summary ────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor White
Write-Host "  TEST RESULTS SUMMARY" -ForegroundColor White
Write-Host ("=" * 70) -ForegroundColor White
$script:Results | Format-Table -AutoSize | Out-Host
Write-Host ""
Write-Host "  Passed : $script:PassCount" -ForegroundColor Green
Write-Host "  Failed : $script:FailCount" -ForegroundColor $(if ($script:FailCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($script:FailCount -gt 0) { exit 1 } else { exit 0 }
