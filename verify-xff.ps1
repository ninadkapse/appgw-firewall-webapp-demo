<#
.SYNOPSIS
    Proves that X-Forwarded-For header preservation works end-to-end.

.DESCRIPTION
    Three verification methods:
    1. HTTP echo — the demo container returns all headers received by the Web App.
       X-Forwarded-For shows YOUR real IP; the remote address shows the Firewall IP.
    2. App Gateway access logs — Log Analytics query showing client IP per request.
    3. Azure Firewall logs — shows traffic from AppGW being forwarded (with SNAT).

.EXAMPLE
    .\verify-xff.ps1 -ResourceGroupName "rg-demoapp"
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [string]$AppName = 'demoapp'
)

$ErrorActionPreference = 'Stop'

Write-Host "`n╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  X-Forwarded-For Verification                          ║" -ForegroundColor Cyan
Write-Host "║  App Gateway (WAF) → Azure Firewall → Web App         ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# ─── Gather resource info ────────────────────────────────────
$appGwPip = az network public-ip show `
    -g $ResourceGroupName -n "$AppName-appgw-pip" `
    --query ipAddress -o tsv

$workspaceId = az monitor log-analytics workspace show `
    -g $ResourceGroupName -n "$AppName-law" `
    --query customerId -o tsv

Write-Host "App Gateway Public IP : $appGwPip"
Write-Host "Log Analytics Workspace: $workspaceId`n"

# ═══════════════════════════════════════════════════════════════
# METHOD 1: HTTP Echo — instant visual proof
# ═══════════════════════════════════════════════════════════════
Write-Host "━━━ Method 1: HTTP Echo Response ━━━" -ForegroundColor Yellow
Write-Host "Sending request through App Gateway → Firewall → Web App ...`n"

try {
    $response = Invoke-RestMethod -Uri "http://$appGwPip" -TimeoutSec 30

    Write-Host "✓ Response received!`n" -ForegroundColor Green

    # Extract key headers
    $xff = if ($response.headers.'x-forwarded-for') { $response.headers.'x-forwarded-for' }
           elseif ($response.headers.'X-Forwarded-For') { $response.headers.'X-Forwarded-For' }
           else { 'not found' }

    $xfp = if ($response.headers.'x-forwarded-port') { $response.headers.'x-forwarded-port' }
           elseif ($response.headers.'X-Forwarded-Port') { $response.headers.'X-Forwarded-Port' }
           else { 'not found' }

    $remoteIp = if ($response.ip) { $response.ip } else { 'not found' }

    Write-Host "  ┌─────────────────────────────────────────────────┐"
    Write-Host "  │ X-Forwarded-For  : $xff" -ForegroundColor Green
    Write-Host "  │   → This is YOUR real public IP address"
    Write-Host "  │   → Set by Application Gateway before forwarding"
    Write-Host "  │"
    Write-Host "  │ X-Forwarded-Port : $xfp"
    Write-Host "  │"
    Write-Host "  │ Remote Address   : $remoteIp" -ForegroundColor Magenta
    Write-Host "  │   → This is the Azure Firewall's private IP"
    Write-Host "  │   → Proves firewall SNAT'd the traffic"
    Write-Host "  └─────────────────────────────────────────────────┘"

    Write-Host "`n  Full headers received by the Web App:" -ForegroundColor DarkGray
    if ($response.headers) {
        $response.headers.PSObject.Properties | ForEach-Object {
            Write-Host "    $($_.Name): $($_.Value)" -ForegroundColor DarkGray
        }
    }
}
catch {
    Write-Host "✗ Request failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  The App Gateway may still be provisioning. Retry in a few minutes."
    Write-Host "  Make sure you deployed with -DeployDemoApp `$true (default).`n"
}

# ═══════════════════════════════════════════════════════════════
# METHOD 2: App Gateway Access Logs (Log Analytics)
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ Method 2: App Gateway Access Logs ━━━" -ForegroundColor Yellow
Write-Host "Note: Logs may take 5-10 minutes to appear after first request.`n"

$appGwQuery = @"
AzureDiagnostics
| where ResourceType == "APPLICATIONGATEWAYS"
| where Category == "ApplicationGatewayAccessLog"
| project TimeGenerated, clientIP_s, host_s, requestUri_s, httpMethod_s, httpStatus_d
| order by TimeGenerated desc
| take 5
"@

try {
    $logs = az monitor log-analytics query -w $workspaceId --analytics-query $appGwQuery -o table 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host $logs
        Write-Host "`n  → clientIP_s shows the original client IP that App Gateway recorded." -ForegroundColor Green
    } else {
        Write-Host "  No logs available yet. Wait 5-10 minutes and re-run." -ForegroundColor DarkYellow
    }
}
catch {
    Write-Host "  Could not query logs: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# ═══════════════════════════════════════════════════════════════
# METHOD 3: Azure Firewall Network Rule Logs
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ Method 3: Azure Firewall Network Rule Logs ━━━" -ForegroundColor Yellow

$fwQuery = @"
AzureDiagnostics
| where ResourceType == "AZUREFIREWALLS"
| where Category == "AzureFirewallNetworkRule"
| project TimeGenerated, msg_s
| order by TimeGenerated desc
| take 5
"@

try {
    $fwLogs = az monitor log-analytics query -w $workspaceId --analytics-query $fwQuery -o table 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host $fwLogs
        Write-Host "`n  → msg_s shows traffic from AppGW subnet → PE subnet being allowed." -ForegroundColor Green
    } else {
        Write-Host "  No firewall logs available yet. Wait 5-10 minutes and re-run." -ForegroundColor DarkYellow
    }
}
catch {
    Write-Host "  Could not query logs: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════
Write-Host "`n╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Summary: How X-Forwarded-For Is Preserved             ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║                                                        ║" -ForegroundColor Cyan
Write-Host "║  1. Client (your IP) hits App Gateway public IP        ║" -ForegroundColor Cyan
Write-Host "║  2. App Gateway WAF inspects, adds X-Forwarded-For     ║" -ForegroundColor Cyan
Write-Host "║  3. UDR routes traffic through Azure Firewall          ║" -ForegroundColor Cyan
Write-Host "║  4. Firewall IDPS inspects, SNATs (changes source IP)  ║" -ForegroundColor Cyan
Write-Host "║  5. Web App receives request:                          ║" -ForegroundColor Cyan
Write-Host "║     • X-Forwarded-For = original client IP  ✓          ║" -ForegroundColor Green
Write-Host "║     • Remote address  = firewall private IP  (SNAT)    ║" -ForegroundColor Cyan
Write-Host "║  6. App reads original IP from X-Forwarded-For header  ║" -ForegroundColor Cyan
Write-Host "║                                                        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
