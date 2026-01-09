#----------------------------------------
# pre-requisites
#-----------------------------------------

Write-Host "Before running for first time, please go into script file properties and 'unblock' if downloaded from web." -ForegroundColor Yellow
Write-Host "Call the script file from PowerShell v7" -ForegroundColor Yellow  


# Parameters

$MAMcutoff = (Get-Date).AddDays(-30)


#Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser

Disconnect-MgGraph -ErrorAction SilentlyContinue
# ───────────────────────────────────────────────────────────
# Importing the required modules
# ───────────────────────────────────────────────────────────

$maximumfunctioncount = '32768'

# 0) Connect once with all the scopes you now need

function Install-RequiredModule {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "Installing $Name for current user..." -ForegroundColor Yellow
        Install-Module -Name $Name -Scope CurrentUser -Force -ErrorAction Stop
    }

    Write-Host "Importing $Name..." -ForegroundColor Cyan
    Import-Module $Name -ErrorAction Stop
}

$modulesToLoad = @(
    'Microsoft.Graph.Identity.DirectoryManagement'
    'Microsoft.Graph.Identity.SignIns'
    'Microsoft.Graph.Reports'
    'Microsoft.Graph.Identity.Governance'
    'Microsoft.Graph.Groups'
    'ImportExcel'
    'Microsoft.Graph.Devices.CorporateManagement'
    'Microsoft.Graph.DeviceManagement'
)

foreach ($m in $modulesToLoad) {
    Install-RequiredModule -Name $m
}


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
    "Application.Read.All" # App registrations
) -NoWelcome

Write-Host "Connected to MS Graph successfully!" -ForegroundColor Green 


# ───────────────────────────────────────────────────────────
# Setting MS Graph request context
# ───────────────────────────────────────────────────────────
Write-Host "Setting MS Graph request context..." -ForegroundColor Green 
Set-MgRequestContext -ClientTimeout 1800 -MaxRetry 8 -RetryDelay 10


# ───────────────────────────────────────────────────────────
# Defining Report Path
# ───────────────────────────────────────────────────────────

$reportcsv= Read-Host "Enter the Excel report path" 


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
    'Department'
    'JobTitle'
)


$users = Get-MgUser -All -Property $selectProps   # one call

# 2) Pull *all* authentication-method registrations (one call)
$authReport = Get-MgReportAuthenticationMethodUserRegistrationDetail -All
# ▸  If you need preview fields, swap for the Beta cmdlet:
#    Get-MgBetaReportAuthenticationMethodUserRegistrationDetail -All

#    Build a lookup keyed by UPN for fast joins
$authLookup = @{}

foreach ($r in $authReport) {
    $authLookup[$r.UserPrincipalName] = [PSCustomObject]@{
        MethodsRegistered = $r.MethodsRegistered -join '; '
        IsMfaCapable      = $r.IsMfaCapable
        IsSsprCapable     = $r.IsSsprCapable
    }
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

 $auth = $authLookup[$u.UserPrincipalName]

    [PSCustomObject]@{
        'Display name'                 = $u.DisplayName
        'UPN'                          = $u.UserPrincipalName
        'Primary SMTP'                 = $u.Mail
        'Department'                   = $u.Department
        'Job Title'                    = $u.JobTitle
        'Sign-in status'               = $(if ($u.AccountEnabled) { 'Allowed' } else { 'Blocked' })
        'Assigned licences'            = $licences -join '; '
        'Account type'                 = $(if ($u.OnPremisesSyncEnabled -or $u.OnPremisesImmutableId) { 'Synced' } else { 'Cloud only' })
        'Registered auth methods'      = $auth.MethodsRegistered
        'Is MFA capable'               = $auth.IsMfaCapable
        'Is SSPR capable'              = $auth.IsSsprCapable
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
    ($_.'Last interactive sign-in' -eq $null) -or 
    ($_.'Last interactive sign-in' -lt $sixtyDaysAgo)
}



if ($inactiveusers -and $inactiveusers.Count -gt 0) {
    $inactiveusers | Export-Excel -Path $reportcsv -WorksheetName "Inactive Users and Devices" `
        -Title "Inactive Users (60- Days)"  -AutoSize -TableStyle Light12 
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
                $u  = Get-UserCached $gU.Id
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


Write-Host "Querying admin roles is completed" -ForegroundColor Green


<#
#############################################################################################################
Mac Devices
##############################################################################################################
#>


# ───────────────────────────────────────────────────────────
#  macOS devices that have signed in during the last 14 days
#  (Microsoft Graph PowerShell SDK version)
# ───────────────────────────────────────────────────────────


Write-Host "Querying Entra sign-in logs for macOS devices…" -ForegroundColor Yellow

# 1. Define the time window (-14 days)
$since = (Get-Date).AddDays(-14).ToString('yyyy-MM-ddTHH:mm:ssZ')

# 2. Pull sign-ins where the device OS starts with “Mac”
#    The nested filter works in both v1.0 and beta, but if it ever
#    throws ‘unsupported property’ just remove the startsWith()
#    bit and do the OS filtering in PowerShell (see comment below).
$macSignIns = Get-MgAuditLogSignIn -All `
    -Filter "createdDateTime ge $since and startswith(deviceDetail/operatingSystem,'Mac')"

# ALTERNATIVE (works everywhere, including older tenants):
# $macSignIns = Get-MgAuditLogSignIn -All -Filter "createdDateTime ge $since"
# $macSignIns = $macSignIns | Where-Object { $_.DeviceDetail.OperatingSystem -like 'Mac*' }

# 3. Flatten to one line per physical device
#$seen = @{}
$macreport=foreach ($si in $macSignIns) {
    $dd  = $si.DeviceDetail
    $key = if ($dd.DeviceId) { $dd.DeviceId } else { $dd.DisplayName }

   
            [pscustomobject]@{
            UserDisplayName = $si.UserDisplayName
            UserUPN         = $si.UserPrincipalName
            DeviceName      = $dd.DisplayName
            OperatingOS     = $dd.OperatingSystem
            Browser         = $dd.Browser
            App             = $si.AppDisplayName
            JoinType        = $dd.TrustType        # Entra-joined / Registered / Hybrid …
            Managed         = $(if ($dd.IsManaged)   { 'Yes' } else { 'No' })
            Compliant       = $(if ($dd.IsCompliant) { 'Yes' } else { 'No' })
            LastSeen        = $si.CreatedDateTime
        }}
  


# 4. Present or export

$macReport | Export-Excel -Path $reportcsv -WorksheetName 'Mac Devices' `
                           -AutoSize -FreezeTopRow -BoldTopRow -AutoFilter


Write-Host "Querying MacOS users based on sign in logs is completed" -ForegroundColor Green
<#
#############################################################################################################
All Entra Devices
##############################################################################################################
#>


$props = @(
    'id','displayName','managementType',
    'operatingSystem','operatingSystemVersion',
    'approximateLastSignInDateTime',
    'isCompliant','accountEnabled',
    'registrationDateTime','trustType',
    'mdmAppId','deviceId','model',
    'approximateLastLogonTimestamp'       # still preview at May 2025
)

Write-Host "Getting the complete list of Entra Devices – this may take a minute …" -f Yellow
$devices = Get-MgDevice -All -Property $props

# ------------------------------------------------------------------
# 2.  Build initial report (add first user owner)
# ------------------------------------------------------------------
$Entradevicereport = foreach ($d in $devices) {

    # first registered **user** owner, if one exists
    $owner = (Get-MgDeviceRegisteredOwner -DeviceId $d.Id -Top 1).AdditionalProperties.userPrincipalName

    [pscustomobject]@{
        Name                = $d.DisplayName
        'Management Type'   = $d.ManagementType
        OS                  = "$($d.OperatingSystem) $($d.OperatingSystemVersion)"
        'Last Activity'     = $d.ApproximateLastSignInDateTime
        'Compliance Status' = if ($d.IsCompliant) { 'Compliant' } else { 'Not compliant' }
        Enabled             = if ($d.AccountEnabled) { 'Yes' } else { 'No' }
        'Registered Date'   = $d.RegistrationDateTime
        'Join Type'         = $d.TrustType
        Owner               = if ($owner) { $owner} else { '—' }
        MDM                 = if ($d.MdmAppId -eq '0000000a-0000-0000-c000-000000000000') { 'Intune' } else {}
        ID                  = $d.DeviceId
        'Device Model'      = $d.Model
        'Approx Last Login' = $d.ApproximateLastLogonTimestamp
    }
}

# ------------------------------------------------------------------
# 3.  Pull Intune managed devices and map useful fields
# ------------------------------------------------------------------

# Properties to retrieve from Intune managed devices
$graphProps = @(
    'deviceName'
    'azureAdDeviceId'
    'serialNumber'
    'operatingSystem'
    'osVersion'
    'model'
    'manufacturer'
    'lastSyncDateTime'
    'skuFamily'
    'skuNumber'
)
$selectQuery = '$select=' + ($graphProps -join ',')
$url = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?$selectQuery"

# 3) Call Graph
$response = Invoke-MgGraphRequest -Method GET -Uri $url

# 4) Project into $managed (this is your final variable)
$managed = $response.value | Select-Object $graphProps



# 3a.  Build a hash keyed by Azure AD device Id → full Intune object
$intuneByAadId = @{}
foreach ($m in $managed) {
    if ($m.AzureAdDeviceId) {
        $intuneByAadId[$m.AzureAdDeviceId.ToLower()] = $m
    }
}

# ------------------------------------------------------------------
# 4.  Enrich report with Intune data
# ------------------------------------------------------------------
$Entradevicereport = $Entradevicereport | ForEach-Object {

    $key    = if ($_.Id) { $_.Id.ToString().ToLower() } else { $null }
    $intune = if ($key) {$intuneByAadId[$key] } else {$null}     # may be $null

    $_ | Add-Member -MemberType NoteProperty -Name 'Device Serial Number'     -Value $intune.SerialNumber      -Force
    $_ | Add-Member -MemberType NoteProperty -Name 'Device OperatingSystem'   -Value $intune.OperatingSystem   -Force
    $_ | Add-Member -MemberType NoteProperty -Name 'Device OSVersion'         -Value $intune.OsVersion         -Force
    $_ | Add-Member -MemberType NoteProperty -Name 'Device Model'             -Value $intune.Model             -Force
    $_ | Add-Member -MemberType NoteProperty -Name 'Device Manufacturer'      -Value $intune.Manufacturer      -Force
    $_ | Add-Member -MemberType NoteProperty -Name 'Intune LastSyncDateTime'  -Value $intune.LastSyncDateTime  -Force
    # Build Windows SKU as "OS OSVersion SkuFamily", skipping blanks
    $windowsSkuParts = @(
        if ($intune.OperatingSystem) { $intune.OperatingSystem } else { $_.OS }
        $intune.OsVersion
        $intune.SkuFamily
    ) | Where-Object { $_ }

    $_ | Add-Member -MemberType NoteProperty -Name 'OS Version and SKU' -Value ($windowsSkuParts -join ' ') -Force
    $_
}

# ------------------------------------------------------------------
# 5.  Output
# ------------------------------------------------------------------


$Entradevicereport | Export-Excel -Path $reportcsv -WorksheetName 'Entra Devices' `
                       -AutoSize `
                       -FreezeTopRow `
                       -BoldTopRow `
                       -AutoFilter



Write-Host "Querying Entra devices completed" -ForegroundColor Green

<#
#############################################################################################################
MAM Devices
##############################################################################################################
#>



Write-Host "Querying MAM Device information..........." -ForegroundColor Yellow


# ------------------------------------------------------------------
# 1.  Start the “App protection status” export job
# ------------------------------------------------------------------
$body = @{
    reportName       = 'MAMAppProtectionStatus'
    format           = 'Csv'
    localisationType = 'LocalizedValuesAsAdditionalColumn'
    # select = @('UserPrincipalName','DeviceName','DeviceModel','DeviceManufacturer')
} | ConvertTo-Json -Depth 4

$job = Invoke-MgGraphRequest `
          -Uri    'https://graph.microsoft.com/v1.0/deviceManagement/reports/exportJobs' `
          -Method POST `
          -Body   $body `
          -ContentType 'application/json'

$jobId = $job.id
Write-Host "Job $jobId queued – polling until it completes …" -f Yellow

# ------------------------------------------------------------------
# 2.  Poll the job status
# ------------------------------------------------------------------
do {
    Start-Sleep 10
    $status = Invoke-MgGraphRequest `
                -Uri    "https://graph.microsoft.com/v1.0/deviceManagement/reports/exportJobs('$jobId')" `
                -Method GET
} until ($status.status -eq 'completed')

# ------------------------------------------------------------------
# 3.  Download and unpack the report
# ------------------------------------------------------------------


# $status.url is the SAS link returned by the completed export job
$response = Invoke-WebRequest -Uri $status.url -UseBasicParsing

# 1. load the ZIP into a memory stream
$zipStream = [System.IO.MemoryStream]::new($response.Content)

# 2. open the archive without writing it out
$zip = [System.IO.Compression.ZipArchive]::new($zipStream)

# 3. read the first (only) entry into a string
$csvText = [System.IO.StreamReader]::new($zip.Entries[0].Open()).ReadToEnd()

# 4. convert to objects on the pipeline
$report = $csvText | ConvertFrom-Csv

$recentmamadevices = $report | Where-Object { [DateTime]$_.LastSync -ge $MAMcutoff }

$mamdeviceresults = $recentmamadevices | Where-Object {$_.ManagementType -EQ 'unmanaged' }#|Sort-Object AADDeviceID -Unique


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

    if ($_.OS -eq 'Android' -and $majorVersion -lt 13) {
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
                      
Write-Host "Querying MAM devices completed" -ForegroundColor Green
                        
 
 
 <#
#############################################################################################################
Intune device Defender status
##############################################################################################################
#>



Write-Host "Querying Defender Device information..........." -ForegroundColor Yellow


# ------------------------------------------------------------------
# 1.  Start the “Defender Agent status” export job
# ------------------------------------------------------------------
$body = @{
    reportName       = 'DefenderAgents'
    format           = 'Csv'
    localisationType = 'LocalizedValuesAsAdditionalColumn'
    # select = @('UserPrincipalName','DeviceName','DeviceModel','DeviceManufacturer')
} | ConvertTo-Json -Depth 4

$job = Invoke-MgGraphRequest `
          -Uri    'https://graph.microsoft.com/v1.0/deviceManagement/reports/exportJobs' `
          -Method POST `
          -Body   $body `
          -ContentType 'application/json'

$jobId = $job.id
Write-Host "Job $jobId queued – polling until it completes …" -f Yellow

# ------------------------------------------------------------------
# 2.  Poll the job status
# ------------------------------------------------------------------
do {
    Start-Sleep 10
    $status = Invoke-MgGraphRequest `
                -Uri    "https://graph.microsoft.com/v1.0/deviceManagement/reports/exportJobs('$jobId')" `
                -Method GET
} until ($status.status -eq 'completed')

# ------------------------------------------------------------------
# 3.  Download and unpack the report
# ------------------------------------------------------------------


# $status.url is the SAS link returned by the completed export job
$response = Invoke-WebRequest -Uri $status.url -UseBasicParsing

# 1. load the ZIP into a memory stream
$zipStream = [System.IO.MemoryStream]::new($response.Content)

# 2. open the archive without writing it out
$zip = [System.IO.Compression.ZipArchive]::new($zipStream)

# 3. read the first (only) entry into a string
$csvText = [System.IO.StreamReader]::new($zip.Entries[0].Open()).ReadToEnd()

# 4. convert to objects on the pipeline
$report = $csvText | ConvertFrom-Csv


$report| Export-Excel -Path $reportcsv -WorksheetName 'Defender Device Status' `
                       -AutoSize `
                       -FreezeTopRow `
                       -BoldTopRow `
                       -AutoFilter

                      
Write-Host "Querying defender devices completed" -ForegroundColor Green                   


 <#
#############################################################################################################
Enterpsie apps with SSO type
##############################################################################################################
#>

Write-Host "Querying Enterprise Apps SSO type information..........." -ForegroundColor Yellow


# Get all Service Principals (Enterprise Apps)
$apps = Get-MgServicePrincipal -All

# Create an array to store results
$results = @()

foreach ($app in $apps) {
    $results += [PSCustomObject]@{
        DisplayName                = $app.DisplayName
        AppId                      = $app.AppId
        ObjectId                   = $app.Id
        PreferredSingleSignOnMode  = $app.PreferredSingleSignOnMode
    }
}

# Output to console
#$results | Sort-Object DisplayName | Format-Table -AutoSize

$results | Export-Excel -Path $reportcsv -WorksheetName 'Enterprise Apps SSO Status' `
                       -AutoSize `
                       -FreezeTopRow `
                       -BoldTopRow `
                       -AutoFilter



Write-Host "Querying enterprise apps with SSO type completed" -ForegroundColor Green    