
#Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser

Disconnect-MgGraph -ErrorAction SilentlyContinue
# ───────────────────────────────────────────────────────────
# Importing the required modules
# ───────────────────────────────────────────────────────────

$maximumfunctioncount = '32768'

# 0) Connect once with all the scopes you now need


Write-Host "Importing Microsoft.Graph.Identity.DirectoryManagement Module...."
Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop 

Write-Host "Importing Microsoft.Graph.Identity.SignIns...."
import-module Microsoft.Graph.Identity.SignIns  -ErrorAction Stop 

Write-Host "Importing Microsoft.Graph.Reports Module...."
Import-Module Microsoft.Graph.Reports -ErrorAction Stop 

Write-Host "Importing Microsoft.Graph.Identity.Governance Module...."
Import-Module Microsoft.Graph.Identity.Governance -ErrorAction stop 

Write-Host "Importing Microsoft.Graph.Groups Module...."
import-module Microsoft.Graph.Groups -ErrorAction Stop 

Write-Host "Importing Microsoft.Entra Module...."
#Import-Module Microsoft.Entra -ErrorAction Stop -Force 

Write-Host "ImportExcel Module...."
Import-Module ImportExcel -ErrorAction Stop

Write-Host "Importing Microsoft.Graph.Devices.CorporateManagement  Module...."
import-module Microsoft.Graph.Devices.CorporateManagement   


Write-Host "Importing Microsoft.Graph.DeviceManagement  Module...."
import-module Microsoft.Graph.DeviceManagement 



# ───────────────────────────────────────────────────────────
# Connecting to Microsfot Graph
# ───────────────────────────────────────────────────────────
Write-Host "Connecting to MS Graph..........." -ForegroundColor Yellow

Connect-MgGraph -Scopes @(
    'Directory.Read.All',               # basic user data
    'AuditLog.Read.All',                # signInActivity
    'LicenseAssignment.Read.All',       # assignedLicenses
    'Reports.Read.All'   `               # auth-method registration report
    "RoleManagement.Read.Directory"
    "DeviceManagementManagedDevices.Read.All"
    "DeviceManagementApps.Read.All"
)


# ───────────────────────────────────────────────────────────
# Connecting to Entra ID
# ───────────────────────────────────────────────────────────

Write-Host "Connecting to Entra ID..........." -ForegroundColor Yellow
Connect-Entra -Scopes 'AuditLog.Read.All','Directory.Read.All','Device.Read.All'

# ───────────────────────────────────────────────────────────
# Defining Report Path
# ───────────────────────────────────────────────────────────

$reportcsv= Read-Host "Enter the EXcel report path" 




<#
#############################################################################################################
User Details
##############################################################################################################
#>
Write-Host "Querying user details..........." -ForegroundColor Yellow

# 1) Pull user core + sign-in data in a single call
$selectProps = @(
    'id'                         # ← NEW: needed for look-ups
    'displayName'
    'userPrincipalName'
    'mail'
    'accountEnabled'
    'onPremisesSyncEnabled'
    'onPremisesImmutableId'
    'assignedLicenses'
    'signInActivity'
)


$users = Get-MgUser -All -Property $selectProps   # one call

# 2) Pull *all* authentication-method registrations (one call)
$authReport = Get-MgReportAuthenticationMethodUserRegistrationDetail -All
# ▸  If you need preview fields, swap for the Beta cmdlet:
#    Get-MgBetaReportAuthenticationMethodUserRegistrationDetail -All

#    Build a lookup keyed by UPN for fast joins
$authLookup = @{}
foreach ($r in $authReport) {
    $authLookup[$r.UserPrincipalName] = ($r.MethodsRegistered -join '; ')
}

# 3) Optional: build a SKU-ID ➜ product-name map (one call)
$skuMap = @{}
Get-MgSubscribedSku -All | ForEach-Object {
    $skuMap[$_.SkuId] = $_.SkuPartNumber
}

# 4) Assemble the final report
$userreport = foreach ($u in $users) {

    $licences = $u.AssignedLicenses |
        ForEach-Object { $skuMap[$_.SkuId] } |
        Sort-Object -Unique

    [PSCustomObject]@{
        'Display name'                 = $u.DisplayName
        'UPN'                          = $u.UserPrincipalName
        'Primary SMTP'                 = $u.Mail
        'Sign-in status'               = $(if ($u.AccountEnabled) { 'Allowed' } else { 'Blocked' })
        'Assigned licences'            = $licences -join '; '
        'Account type'                 = $(if ($u.OnPremisesSyncEnabled -or $u.OnPremisesImmutableId) { 'Synced' } else { 'Cloud only' })
        'Registered auth methods'      = $authLookup[$u.UserPrincipalName]
        'Last interactive sign-in'     = $u.SignInActivity.LastSignInDateTime
        'Last non-interactive sign-in' = $u.SignInActivity.LastNonInteractiveSignInDateTime
    }
}




# 5) Export
$userreport | Export-Excel -Path $reportcsv -WorksheetName 'UserInfo' `
                       -AutoSize `
                       -FreezeTopRow `
                       -BoldTopRow `
                       -AutoFilter



# Calculate the cutoff date
$sixtyDaysAgo = (Get-Date).AddDays(-60)

# Filter users who have not signed in since that date
$inactiveusers= $UserReport | Where-Object {
    # Consider "no sign-in" (null date) or an older date as “hasn’t signed in within 60 days”
    ($_.LastInteractiveSignInDateTime -eq $null) -or 
    ($_.LastInteractiveSignInDateTime -lt $sixtyDaysAgo)
}



$inactiveusersrow = $inactiveDevices.count + 5

if ($inactiveusers -and $inactiveusers.Count -gt 0) {
    $inactiveusers | Export-Excel -Path $report -WorksheetName "Inactive Users and Devices" `
        -Title "Inactive Users (60- Days)"  -AutoSize -TableStyle Light12 -StartRow $inactiveusersrow
    Write-Host "Exported inactive users to Excel report at $report"
} else {
    Write-Host "No inactive users found. Skipping export." -ForegroundColor Yellow
}



Write-Host "Querying user sign-in information completed" -ForegroundColor Green




<#
#############################################################################################################
Admin Roles
##############################################################################################################
#>


Write-Host "Finding users wih Admin roles..........." -ForegroundColor Yellow

# ───────────────────────────────────────────────────────────
# 2.  Build a lookup table of  roleDefinitionId ➔ DisplayName
#     (one call, no need to expand)
# ───────────────────────────────────────────────────────────
$roleName = @{}
Get-MgRoleManagementDirectoryRoleDefinition -All | ForEach-Object {
    $roleName[$_.Id] = $_.DisplayName
}

# ───────────────────────────────────────────────────────────
# 3.  Get every active role assignment, expanding only 'principal'
# ───────────────────────────────────────────────────────────
$assignments = Get-MgRoleManagementDirectoryRoleAssignment -All `
               -ExpandProperty "principal"        # only one expand allowed :contentReference[oaicite:0]{index=0}

# ───────────────────────────────────────────────────────────
# 4.  Helper: cache users so we never hit Graph twice
# ───────────────────────────────────────────────────────────
$userCache = @{}
function Get‑UserCached {
    param([string]$Id)
    if (-not $userCache.ContainsKey($Id)) {
        $userCache[$Id] = Get-MgUser -UserId $Id `
            -Property Id,DisplayName,UserPrincipalName,AccountEnabled,SignInActivity
    }
    return $userCache[$Id]
}

# ───────────────────────────────────────────────────────────
# 5.  Build the report
# ───────────────────────────────────────────────────────────
$adminreport = foreach ($a in $assignments) {

    $p = $a.Principal          # already expanded directoryObject
    switch ($p.AdditionalProperties.'@odata.type') {

        # ----- A. direct USER assignment --------------------------------
        '#microsoft.graph.user' {
            $u  = Get‑UserCached $p.Id
            $si = $u.AdditionalProperties.signInActivity
            [pscustomobject]@{
                DisplayName             = $u.DisplayName
                UserPrincipalName       = $u.UserPrincipalName
                AdminRole               = $roleName[$a.RoleDefinitionId]
                SignInAllowed           = $(if ($u.AccountEnabled) { 'Allowed' } else { 'Blocked' })

            }
        }

        # ----- B. role‑assignable GROUP ---------------------------------
        '#microsoft.graph.group' {
            $gUsers = Get-MgGroupTransitiveMember -GroupId $p.Id -All |
                      Where-Object { $_.ODataType -eq '#microsoft.graph.user' }
            foreach ($gU in $gUsers) {
                $u  = Get‑UserCached $gU.Id
                $si = $u.AdditionalProperties.signInActivity
                [pscustomobject]@{
                    DisplayName           = $u.DisplayName
                    UserPrincipalName     = $u.UserPrincipalName
                    AdminRole             = $roleName[$a.RoleDefinitionId] + ' (via group)'
                    SignInAllowed         = $(if ($u.AccountEnabled) { 'Allowed' } else { 'Blocked' })

                }
            }
        }

        # ----- C. ignore service principals, devices, etc. --------------
        default { continue }
    }
}


$adminreport| Export-Excel -Path $reportcsv -WorksheetName 'Admin Roles' `
                       -AutoSize `
                       -FreezeTopRow `
                       -BoldTopRow `
                       -AutoFilter





<#
#############################################################################################################
Mac Devices
##############################################################################################################
#>


# ═══════════════════════════════════════════════════════════
#  macOS devices that have signed in during the last 14 days
#  (uses Microsoft.Entra PowerShell, not Graph SDK)
# ═══════════════════════════════════════════════════════════


Write-Host "Querying Entra Sign inlogs to Find MacOS devices..........." -ForegroundColor Yellow



# 1.  Define the time window (‑14 days)
$since = (Get-Date).AddDays(-14).ToString('yyyy-MM-ddTHH:mm:ssZ')

# 2.  Pull sign‑ins where the device OS starts with “Mac”
#     ‑Property lists only what we need; *don’t* include deviceId
$macSignIns = Get-EntraAuditSignInLog -All `
    -Filter "createdDateTime ge $since and startswith(deviceDetail/operatingSystem,'Mac')" 
    #-Property createdDateTime,deviceDetail

# 3.  Flatten to one line per physical device
$seen = @{}
foreach ($si in $macSignIns) {
    $dd  = $si.deviceDetail
    $key = if ($dd.deviceId) { $dd.deviceId } else { $dd.displayName }

    if (-not $seen.ContainsKey($key)) {
        $seen[$key] = [ordered]@{
            UserDisPlayName=$si.userDisplayName
            UserUPN        =$si.userPrincipalName
            DeviceName     = $dd.displayName
            OperatingOS    = $dd.operatingSystem
            JoinType       = $dd.trustType                 # Entra‑joined / Registered / Hybrid …
            Managed        = $(if ($dd.isManaged)   { 'Yes' } else { 'No' })
            Compliant      = $(if ($dd.isCompliant) { 'Yes' } else { 'No' })
            LastSeen       = $si.createdDateTime
        }
    }
    elseif ($si.createdDateTime -gt $seen[$key].LastSeen) {
        $seen[$key].LastSeen = $si.createdDateTime     # keep the newest sign‑in time
    }
}

# 4.  Present (or export) the report
$macReport = $seen.GetEnumerator() | ForEach-Object { [pscustomobject]$_.Value }
$macReport | Export-Excel -Path $reportcsv -WorksheetName 'Mac Devices' `
                       -AutoSize `
                       -FreezeTopRow `
                       -BoldTopRow `
                       -AutoFilter



<#
#############################################################################################################
All Entra Devices
##############################################################################################################
#>



# ═══════════════════════════════════════════════════════════
#  SECTION C – all Microsoft Entra devices → CSV
# ═══════════════════════════════════════════════════════════


# 2.  Properties we need from each device object
$props = @(
    'id','displayName','managementType',               # name & management channel
    'operatingSystem','operatingSystemVersion',        # OS
    'approximateLastSignInDateTime',                   # last activity
    'isCompliant','accountEnabled',                    # compliance + enabled
    'registrationDateTime','trustType',                # registered + join type
    'mdmAppId' ,'DeviceId','Model',
   'ApproximateLastLogonTimestamp'                     # MDM application ID
)

Write-Host "Getting the complete device list – this may take a minute …"
$devices = Get-EntraDevice -All -Property $props    # returns every device

# 3.  Build the report
$Entradevicereport = foreach ($d in $devices) {

    # grab the first registered owner (if any)
    $owner = (Get-EntraDeviceRegisteredOwner -DeviceId $d.Id -Top 1).userPrincipalName

    [pscustomobject]@{
        Name            = $d.DisplayName
        'Management Type' = $d.ManagementType                          # e.g. mdm, jamf, intuneClient :contentReference[oaicite:0]{index=0}
        OS              = "$($d.OperatingSystem) $($d.OperatingSystemVersion)"
        'Last Activity' = $d.ApproximateLastSignInDateTime             # approx. last sign‑in :contentReference[oaicite:1]{index=1}
        'Compliance Status' = if ($d.IsCompliant) { 'Compliant' } else { 'Not compliant' }
        Enabled         = if ($d.AccountEnabled) { 'Yes' } else { 'No' }
        'Registered Date' = $d.RegistrationDateTime
        'Join Type'     = $d.TrustType                                  # AzureAd, Workplace, ServerAd … :contentReference[oaicite:2]{index=2}
        Owner           = if ($owner) { $owner} else { '—' }
        MDM             = if ($d.MdmAppId = '0000000a-0000-0000-c000-000000000000') {'Intune'} else {} 
        ID              = $d.DeviceId  
        'Device Model'  = $d.Model                              # the Intune / MDM app GUID
        'Approx Last Login' = $d.ApproximateLastLogonTimestamp
    }
}





# ───────────────────────────────────────────────────────────
# 1.  Pull Intune devices – GA endpoint, v1.0
# ───────────────────────────────────────────────────────────

$serials = Get-MgDeviceManagementManagedDevice -All `
          -Property AzureAdDeviceId,SerialNumber    # GA properties

# ───────────────────────────────────────────────────────────
# 2.  Build lookup keyed by lower‑case GUID
# ───────────────────────────────────────────────────────────
$serialByAadId = @{}
foreach ($m in $serials) {
    if ($m.AzureAdDeviceId -and $m.SerialNumber) {
        $key = $m.AzureAdDeviceId.ToString().ToLower()
        $serialByAadId[$key] = $m.SerialNumber
    }
}

# ───────────────────────────────────────────────────────────
# 3.  Enrich your existing report
# ───────────────────────────────────────────────────────────
$Entradevicereport = $Entradevicereport | ForEach-Object {

    # ensure the Id exists and normalise to lower‑case
    $key    = if ($_.Id) { $_.Id.ToString().ToLower() } else { $null }
    $serial = if ($key)  { $serialByAadId[$key] }     else { $null }

    $_ | Add-Member -MemberType NoteProperty `
                    -Name  'Serial Number' `
                    -Value $serial -Force
    $_
}



$Entradevicereport | Export-Excel -Path $reportcsv -WorksheetName 'Entra Devices' `
                       -AutoSize `
                       -FreezeTopRow `
                       -BoldTopRow `
                       -AutoFilter




<#
#############################################################################################################
MAM Devices
##############################################################################################################
#>



Write-Host "Querying MAM Device information..........." -ForegroundColor Yellow

#Grab all MAM registrations on the tenant
$allmamregistrations = Get-MgDeviceAppManagementManagedAppRegistration

# Filter out duplicate device records

$mamDevices = $allmamregistrations |
    Group-Object -Property DeviceTag |
    ForEach-Object { $_.Group | Select-Object -First 1 }

# Build final results with user info, etc.

$mamdeviceresults = foreach ($device in $mamDevices) {

    # Look up user info
    $userObject = Get-MgUser -UserId $device.UserId -ErrorAction SilentlyContinue

    # Derive OS by examining the @odata.type
    # (Sometimes exposed as $device.ODataType or $device."@odata.type")
    $os = if (($device).AdditionalProperties.Values -like "*microsoft.graph.iosManagedAppRegistration") {
        "iOS"
    }
    elseif (($device).AdditionalProperties.Values -like "*microsoft.graph.androidManagedAppRegistration") {
        "Android"
    }
    else {
        "Unknown"
    }

    [PSCustomObject]@{
        DeviceName         = $device.DeviceName
        OS                 = $os
        PlatformVersion    = $device.PlatformVersion
        UserDisplayName    = $userObject.DisplayName
        UserPrincipalName  = $userObject.UserPrincipalName
        LastSyncTime       = $device.LastSyncDateTime
    }
}

# Export report to Excel 

$mamdeviceresults | Export-Excel -Path $reportcsv -WorksheetName 'MAM Devices' `
                       -AutoSize `
                       -FreezeTopRow `
                       -BoldTopRow `
                       -AutoFilter

# Identifying Below threshold MAM devices +++++++++++++++++++++++++++++++++++++++++++++

$mamdevicesBelowThreshold = $mamdeviceresults| Where-Object {
    # Split on '.' and take the first segment as an integer.
    # For example, "16.2.3" -> "16"
    $majorVersion = ($_.PlatformVersion -split '\.')[0] -as [int]

    if ($_.OS -eq 'Android' -and $majorVersion -lt 15) {
        $true
    }
    elseif ($_.OS -in @('iOS', 'iPadOS') -and $majorVersion -lt 16) {
        $true
    }
    else {
        $false
    }
}


#Export below threshold MAM devices to Excel

if ($mamdevicesBelowThreshold -and $mamdevicesBelowThreshold.Count -gt 0) {
    $mamdevicesBelowThreshold | Export-Excel -Path $reportcsv -WorksheetName "Incompatible Devices"  `
                             -Title "Incompatible MAM Devices"  -AutoSize -TableStyle Light12 -StartRow 2
    Write-Host "Exported incompatible MAM devices to Excel report at $report"
} else {
    Write-Host "No incompatible MAM devices found. Skipping export." -ForegroundColor Yellow
}
                      

                        
                    