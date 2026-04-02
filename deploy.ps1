<#
.SYNOPSIS
    Deploys the App Gateway (WAF) → Azure Firewall → Web App architecture.

.DESCRIPTION
    Creates a resource group (if needed) and deploys main.bicep.

.EXAMPLE
    .\deploy.ps1 -ResourceGroupName "rg-demoapp" -Location "eastus"
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [string]$Location = 'westus2',
    [string]$AppName  = 'demoapp',
    [string]$WafMode  = 'Prevention',
    [bool]$DeployDemoApp = $true,
    [bool]$DeployVpnGateway = $false,
    [bool]$EnableGeoFiltering = $true,
    [string[]]$AllowedCountryCodes = @('US'),
    [string]$VpnAddressPool = '172.16.0.0/24'
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== App Gateway + WAF → Azure Firewall → Web App ===" -ForegroundColor Cyan
if ($EnableGeoFiltering) {
    Write-Host "    Geo-filtering: ENABLED (allowed countries: $($AllowedCountryCodes -join ', '))" -ForegroundColor Yellow
}
if ($DeployVpnGateway) {
    Write-Host "    VPN Gateway:   ENABLED (adds ~30 min to deployment)" -ForegroundColor Yellow
}

# Ensure resource group exists
Write-Host "`n[1/2] Creating resource group '$ResourceGroupName' in '$Location'..."
az group create --name $ResourceGroupName --location $Location --output none

# Generate VPN certificates if VPN Gateway is being deployed
$vpnRootCertData = ''
if ($DeployVpnGateway) {
    Write-Host "`n[VPN] Generating self-signed certificates for P2S VPN..."
    $rootCert = New-SelfSignedCertificate -Type Custom -KeySpec Signature `
        -Subject "CN=DemoVPNRootCA" -KeyExportPolicy Exportable `
        -HashAlgorithm sha256 -KeyLength 2048 `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyUsageProperty Sign -KeyUsage CertSign

    $clientCert = New-SelfSignedCertificate -Type Custom -KeySpec Signature `
        -Subject "CN=DemoVPNClient" -KeyExportPolicy Exportable `
        -HashAlgorithm sha256 -KeyLength 2048 `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -Signer $rootCert -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2")

    $vpnRootCertData = [Convert]::ToBase64String($rootCert.RawData)
    Write-Host "  Root cert thumbprint  : $($rootCert.Thumbprint)" -ForegroundColor DarkGray
    Write-Host "  Client cert thumbprint: $($clientCert.Thumbprint)" -ForegroundColor DarkGray
}

# Build Bicep parameters as a JSON file (handles arrays and secure values cleanly)
$paramsObj = @{
    location            = @{ value = $Location }
    appName             = @{ value = $AppName }
    wafMode             = @{ value = $WafMode }
    deployDemoApp       = @{ value = $DeployDemoApp }
    enableGeoFiltering  = @{ value = $EnableGeoFiltering }
    deployVpnGateway    = @{ value = $DeployVpnGateway }
    vpnAddressPool      = @{ value = $VpnAddressPool }
    allowedCountryCodes = @{ value = $AllowedCountryCodes }
}
if ($DeployVpnGateway) {
    $paramsObj['vpnRootCertData'] = @{ value = $vpnRootCertData }
}

$paramsJson = @{
    '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters     = $paramsObj
} | ConvertTo-Json -Depth 5

$paramsFile = Join-Path $env:TEMP "deploy-params-$(Get-Random).json"
$paramsJson | Set-Content -Path $paramsFile -Encoding UTF8

# Deploy the Bicep template
Write-Host "[2/2] Deploying infrastructure (this takes ~15-20 minutes)..."
try {
    $result = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file "$PSScriptRoot\main.bicep" `
        --parameters "@$paramsFile" `
        --output json | ConvertFrom-Json
} finally {
    Remove-Item $paramsFile -ErrorAction SilentlyContinue
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed."
    exit 1
}

# Show outputs
Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
Write-Host "App Gateway Public IP : $($result.properties.outputs.appGatewayPublicIp.value)"
Write-Host "App Gateway Private IP: $($result.properties.outputs.appGatewayPrivateIp.value)"
Write-Host "Web App Hostname      : $($result.properties.outputs.webAppHostName.value)"
Write-Host "Firewall Private IP   : $($result.properties.outputs.firewallPrivateIp.value)"
Write-Host "Web App Name          : $($result.properties.outputs.webAppName.value)"
Write-Host ""
Write-Host "Workspace ID          : $($result.properties.outputs.logAnalyticsWorkspaceId.value)"
if ($DeployVpnGateway) {
    Write-Host "VPN Gateway Public IP : $($result.properties.outputs.vpnGatewayPublicIp.value)"
}
Write-Host ""
Write-Host "Test: curl http://$($result.properties.outputs.appGatewayPublicIp.value)" -ForegroundColor Yellow
Write-Host "The Web App is NOT accessible directly — only via the App Gateway." -ForegroundColor Yellow
Write-Host ""
Write-Host "To verify X-Forwarded-For, run: .\verify-xff.ps1 -ResourceGroupName $ResourceGroupName" -ForegroundColor Yellow
if ($EnableGeoFiltering) {
    Write-Host "To verify geo-filtering + VPN rules, run: .\test-geofencing-vpn.ps1 -ResourceGroupName $ResourceGroupName" -ForegroundColor Yellow
}
if ($DeployVpnGateway) {
    Write-Host ""
    Write-Host "=== VPN Client Setup ===" -ForegroundColor Cyan
    Write-Host "1. Download VPN client config:" -ForegroundColor Yellow
    Write-Host "   az network vnet-gateway vpn-client generate -g $ResourceGroupName -n $AppName-vpngw -o tsv" -ForegroundColor Yellow
    Write-Host "2. Install the OpenVPN client profile from the downloaded package" -ForegroundColor Yellow
    Write-Host "3. Connect and access the App Gateway private IP: http://$($result.properties.outputs.appGatewayPrivateIp.value)" -ForegroundColor Yellow
}
