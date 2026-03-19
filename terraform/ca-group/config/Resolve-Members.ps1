<#
.SYNOPSIS
    Resolves UPNs from members.yml to object IDs and generates members.auto.tfvars.

.DESCRIPTION
    Reads terraform/ca-group/config/members.yml, looks up each UPN via Microsoft Graph,
    and writes terraform/ca-group/members.auto.tfvars for Terraform to consume.
    Run this script before `terraform plan/apply` in CI.

.PARAMETER ConfigPath
    Path to members.yml. Defaults to the sibling members.yml in the same directory.

.PARAMETER OutputPath
    Path to write members.auto.tfvars. Defaults to ../members.auto.tfvars relative to this script.

.EXAMPLE
    .\Resolve-Members.ps1
#>

param(
    [string]$ConfigPath = "$PSScriptRoot/members.yml",
    [string]$OutputPath = "$PSScriptRoot/../members.auto.tfvars"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) {
    throw "members.yml not found at: $ConfigPath"
}

# Parse UPNs from YAML flat list (no external module required)
$content    = Get-Content $ConfigPath -Raw
$upnMatches = [regex]::Matches($content, '(?m)^\s*-\s+(\S+@\S+)\s*$')
$upns       = @($upnMatches | ForEach-Object { $_.Groups[1].Value.Trim() })

if ($upns.Count -eq 0) {
    throw "No UPN entries found in $ConfigPath"
}

Write-Host "Resolving $($upns.Count) UPN(s) to object IDs via Microsoft Graph..." -ForegroundColor Cyan

$lines  = [System.Collections.Generic.List[string]]::new()
$failed = [System.Collections.Generic.List[string]]::new()

foreach ($upn in $upns) {
    try {
        $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -Property Id,DisplayName -ErrorAction Stop
        if (-not $user) {
            Write-Warning "  UPN not found: $upn"
            $failed.Add($upn)
            continue
        }
        $lines.Add("  `"$($user.Id)`",  # $($user.DisplayName) ($upn)")
        Write-Host "  OK  $upn → $($user.Id)" -ForegroundColor Green
    } catch {
        Write-Warning "  FAILED to resolve $upn`: $_"
        $failed.Add($upn)
    }
}

if ($failed.Count -gt 0) {
    throw "Failed to resolve $($failed.Count) UPN(s): $($failed -join ', ')"
}

$tfvars = @"
# ── CA Group Members (generated) ─────────────────────────────────────────────
# DO NOT EDIT - this file is generated from terraform/ca-group/config/members.yml
# Edit members.yml to add or remove users.
# Generated: $(Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
# ─────────────────────────────────────────────────────────────────────────────

members = [
$($lines -join "`n")
]
"@

Set-Content -Path $OutputPath -Value $tfvars -Encoding UTF8
Write-Host ""
Write-Host "Written $($lines.Count) member(s) to: $OutputPath" -ForegroundColor Cyan
