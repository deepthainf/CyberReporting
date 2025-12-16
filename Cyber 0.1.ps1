<#
.SYNOPSIS
  Export a user inventory with sign-in activity, authentication methods,
  account status, licence names, etc., using Microsoft Graph.

.NOTES
  Required Graph application / delegated permissions
    • Directory.Read.All
    • AuditLog.Read.All          (for signInActivity)
    • UserAuthenticationMethod.Read.All
    • LicenseAssignment.Read.All
#>

# ───────────────────────── 1. Connect to Microsoft Graph ─────────────────────────
Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
import-module Microsoft.Graph.Identity.SignIns  -ErrorAction Stop


$scopes = @(
    'Directory.Read.All',
    'AuditLog.Read.All',
    'UserAuthenticationMethod.Read.All',
    'LicenseAssignment.Read.All'
)

Connect-MgGraph -Scopes $scopes -NoWelcome

# ───────────────────────── 2. Build a SKU-ID ➜ friendly-name map ────────────────
$licenceMap = @{}
Get-MgSubscribedSku -All | ForEach-Object {
    # Use SkuPartNumber if populated, otherwise fall back to SkuId
    $licenceMap[$_.SkuId] = if ($_.SkuPartNumber) { $_.SkuPartNumber } else { $_.SkuId }
}

# ───────────────────────── 3. Pull the user list (with sign-in data) ────────────
# The signInActivity property is only returned if explicitly selected.
# Paging handled transparently by the SDK's -All switch.

$selectProps = @(
    'displayName'
    'userPrincipalName'
    'mail'
    'accountEnabled'
    'onPremisesSyncEnabled'
    'onPremisesImmutableId'
    'assignedLicenses'
    'signInActivity'
)

$users = Get-MgUser -All -Property $selectProps


# ───────────────────────── 4. Build the report ──────────────────────────────────
$report = foreach ($u in $users) {

    # A. Licences → readable names
    $licences = $u.AssignedLicenses |
        ForEach-Object { $licenceMap[$_.SkuId] } |
        Sort-Object -Unique -CaseSensitive |
        Where-Object { $_ } -ErrorAction SilentlyContinue

    # B. Authentication methods (phone, FIDO2, etc.)
    #    NB: This is a separate call per user; large tenants may need throttling.
    $methods = Get-MgUserAuthenticationMethod -UserId $u.Id |
        ForEach-Object {
            # The odata.type gives the method in the form '#microsoft.graph.<Type>'
            $_.'@odata.type' -replace '#microsoft.graph.', ''
        } |
        Sort-Object -Unique

    # C. Account type: synced versus cloud-only
    $accountType = if ($u.OnPremisesSyncEnabled -or $u.OnPremisesImmutableId) {
        'Synced'
    } else {
        'Cloud only'
    }

    # D. Sign-in activity (interactive & non-interactive)
    $interactive    = $u.SignInActivity.lastSignInDateTime
    $nonInteractive = $u.SignInActivity.lastNonInteractiveSignInDateTime

    # E. Assemble a row
    [PSCustomObject]@{
        'Display name'                 = $u.DisplayName
        'User principal name (UPN)'    = $u.UserPrincipalName
        'Primary SMTP address'         = $u.Mail
        'Account sign-in status'       = if ($u.AccountEnabled) { 'Allowed' } else { 'Blocked' }
        'Assigned licences'            = $licences -join '; '
        'Account type'                 = $accountType
        'Registered auth methods'      = $methods  -join '; '
        'Last *interactive* sign-in'   = $interactive
        'Last *non-interactive* sign-in' = $nonInteractive
    }
}

# ───────────────────────── 5. Export to CSV ──────────────────────────────────────
$csvPath = Join-Path -Path (Get-Location) -ChildPath 'Users-with-Sign-in-&-Licences.csv'
$report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "Done. Report written to $csvPath`n"





$selectProps = @(
    'displayName'
    'userPrincipalName'
    'mail'
    'accountEnabled'
    'onPremisesSyncEnabled'
    'onPremisesImmutableId'
    'assignedLicenses'
    'signInActivity'
)

$users = Get-MgUser -All -Property $selectProps


$users |fl displayName,onPremisesSyncEnabled,signInActivity
