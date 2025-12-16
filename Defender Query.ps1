# 1) Sign in to the *customer* tenant
# Use the tenant ID or onmicrosoft name
Connect-AzAccount -Tenant (Get-MgContext).tenantid  -AuthScope "https://securitycenter.onmicrosoft.com"

# 2) Get a token for Defender for Endpoint
# IMPORTANT: resource must be this, not the api URL
$token = Get-AzAccessToken -ResourceUrl 'https://securitycenter.onmicrosoft.com'
$accessToken = $token.Token

$headers = @{
    Authorization = "Bearer $accessToken"
    Accept        = "application/json"
}

# 3) Call the Defender "machines" API and page through results
$uri = 'https://api.securitycenter.microsoft.com/api/machines?$top=1000'
$allMachines = @()

while ($uri) {
    $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
    $allMachines += $resp.value
    $uri = $resp.'@odata.nextLink'
}

# 4) Export the key fields to CSV
$exportPath = "C:\Temp\DefenderDevices-$((Get-AzContext).Tenant.Id).csv"

$allMachines |
    Select-Object id,
                  computerDnsName,
                  osPlatform,
                  osVersion,
                  healthStatus,
                  riskScore,
                  exposureLevel,
                  aadDeviceId,
                  lastSeen,
                  machineTags |
    Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8

Write-Host "Export complete: $exportPath" -ForegroundColor Green
