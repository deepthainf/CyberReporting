<#
.SYNOPSIS
    Creates the “native” Defender for Endpoint app registration exactly
    as described in https://aka.ms/mde-nativeapp-doc (public-client, delegated
    permissions only) and produces the IDs your users need.

.EXAMPLE
    .\New-MdeNativeApp.ps1 -AppName 'MDE Native (May 2025)' `
                           -DelegatedPerms 'Alert.Read','Machine.Read.All'
#>

param(
    [string]  $AppName          = "MDE-Native-$(Get-Date -Format yyyyMMdd-HHmmss)",
    [string]  $RedirectUri      = "http://localhost",
    [string[]]$DelegatedPerms   = @('Alert.Read','Machine.Read')   # add more if required
)

# 1. Admin signs in once (needs Application.ReadWrite.All + AppRoleAssignment.ReadWrite.All)
Connect-MgGraph -Scopes "Application.ReadWrite.All","AppRoleAssignment.ReadWrite.All" -ContextScope Process

# 2. Locate the Defender for Endpoint resource (service-principal)
$wdSp = Get-MgServicePrincipal -Filter "displayName eq 'WindowsDefenderATP'" `
                               -Property AppId,OAuth2PermissionScopes,id
if (-not $wdSp) { throw "WindowsDefenderATP service-principal not found." }

# 3. Build RequiredResourceAccess from the delegated scope names you passed in
$requestedScopes = foreach ($name in $DelegatedPerms) {
    $scope = $wdSp.OAuth2PermissionScopes | Where-Object { $_.Value -eq $name }
    if (-not $scope) { throw "Permission ‘$name’ not found on WindowsDefenderATP." }
    @{ Id = $scope.Id; Type = 'Scope' }
}
$requiredResourceAccess = @(
    @{ ResourceAppId = $wdSp.AppId; ResourceAccess = $requestedScopes }
)

# 4. Create the native (public-client) application
$app = New-MgApplication `
          -DisplayName            $AppName `
          -SignInAudience         "AzureADMyOrg" `
          -PublicClient           @{ RedirectUris = @($RedirectUri) } `
          -RequiredResourceAccess $requiredResourceAccess

Write-Host "`n✔ App registration created: $($app.DisplayName)  (ClientId: $($app.AppId))"

# 5. Create a matching enterprise application (service-principal)
$sp = New-MgServicePrincipal -AppId $app.AppId
Write-Host "✔ Enterprise application object created (Id: $($sp.Id))"

# 6. Grant tenant-wide admin consent for the delegated scopes you picked
New-MgOauth2PermissionGrant `
    -ClientId     $sp.Id `
    -ConsentType  "AllPrincipals" `
    -ResourceId   $wdSp.id `
    -Scope        ($DelegatedPerms -join ' ')
Write-Host "✔ Admin consent granted for scopes: $($DelegatedPerms -join ', ')"



$params = @{
    ClientId    = $sp.Id          # client service-principal (your app)
    ConsentType = "AllPrincipals" # tenant-wide admin consent
    ResourceId  = $wdSp.Id        # Defender for Endpoint service-principal
    Scope       = ($DelegatedPerms -join ' ')
}

New-MgOauth2PermissionGrant -BodyParameter $params





New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -ResourceId $sp.Id

# 7. Show the values your users (or scripts) will need
@"
====================  SAVE THESE  ====================
Tenant ID : $(Get-MgContext).TenantId
Client ID : $($app.AppId)
Redirect  : $RedirectUri
======================================================
"@

