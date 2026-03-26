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
    [bool]$DeployDemoApp = $true
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== App Gateway + WAF → Azure Firewall → Web App ===" -ForegroundColor Cyan

# Ensure resource group exists
Write-Host "`n[1/2] Creating resource group '$ResourceGroupName' in '$Location'..."
az group create --name $ResourceGroupName --location $Location --output none

# Deploy the Bicep template
Write-Host "[2/2] Deploying infrastructure (this takes ~15-20 minutes)..."
$result = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file "$PSScriptRoot\main.bicep" `
    --parameters location=$Location appName=$AppName wafMode=$WafMode deployDemoApp=$("$DeployDemoApp".ToLower()) `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed."
    exit 1
}

# Show outputs
Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
Write-Host "App Gateway Public IP : $($result.properties.outputs.appGatewayPublicIp.value)"
Write-Host "Web App Hostname      : $($result.properties.outputs.webAppHostName.value)"
Write-Host "Firewall Private IP   : $($result.properties.outputs.firewallPrivateIp.value)"
Write-Host "Web App Name          : $($result.properties.outputs.webAppName.value)"
Write-Host ""
Write-Host "Workspace ID          : $($result.properties.outputs.logAnalyticsWorkspaceId.value)"
Write-Host ""
Write-Host "Test: curl http://$($result.properties.outputs.appGatewayPublicIp.value)" -ForegroundColor Yellow
Write-Host "The Web App is NOT accessible directly — only via the App Gateway." -ForegroundColor Yellow
Write-Host ""
Write-Host "To verify X-Forwarded-For, run: .\verify-xff.ps1 -ResourceGroupName $ResourceGroupName" -ForegroundColor Yellow
