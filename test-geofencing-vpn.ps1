<#
.SYNOPSIS
    Verifies WAF geo-filtering and VPN custom rules work end-to-end.

.DESCRIPTION
    Five verification methods:
    1. WAF policy inspection — confirms custom rules (geo-block + VPN allow) are active.
    2. Internet access test — request through App Gateway public IP (allowed country).
    3. WAF managed rules test — SQL injection blocked even from allowed sources.
    4. WAF logs — custom rule and managed rule actions in Log Analytics.
    5. VPN instructions — how to test VPN access through the private frontend.

.EXAMPLE
    .\test-geofencing-vpn.ps1 -ResourceGroupName "rg-demoapp"
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [string]$AppName = 'demoapp'
)

$ErrorActionPreference = 'Stop'

Write-Host "`n╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Geo-Filtering + VPN WAF Verification                  ║" -ForegroundColor Cyan
Write-Host "║  WAF Custom Rules + Managed Rules End-to-End           ║" -ForegroundColor Cyan
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
# METHOD 1: WAF Policy Custom Rules Inspection
# ═══════════════════════════════════════════════════════════════
Write-Host "━━━ Method 1: WAF Policy Custom Rules ━━━" -ForegroundColor Yellow
Write-Host "Checking WAF policy for geo-filtering and VPN allow rules...`n"

try {
    $wafPolicy = az network application-gateway waf-policy show `
        -g $ResourceGroupName -n "$AppName-waf-policy" `
        --output json | ConvertFrom-Json

    if ($wafPolicy.customRules -and $wafPolicy.customRules.Count -gt 0) {
        Write-Host "  ✓ Custom rules found: $($wafPolicy.customRules.Count) rule(s)" -ForegroundColor Green
        foreach ($rule in $wafPolicy.customRules) {
            $operator = $rule.matchConditions[0].operator
            $action = $rule.action
            Write-Host "    ├── $($rule.name) (Priority: $($rule.priority), Action: $action, Operator: $operator)" -ForegroundColor White

            if ($operator -eq 'IPMatch') {
                Write-Host "    │   Allowed IP ranges: $($rule.matchConditions[0].matchValues -join ', ')" -ForegroundColor DarkGray
                Write-Host "    │   → VPN/internal clients bypass geo-block, managed rules STILL apply" -ForegroundColor DarkGray
            }
            elseif ($operator -eq 'GeoMatch') {
                $countries = $rule.matchConditions[0].matchValues -join ', '
                $negated = $rule.matchConditions[0].negationConditon
                if ($negated) {
                    Write-Host "    │   Blocked: All countries EXCEPT [$countries]" -ForegroundColor DarkGray
                } else {
                    Write-Host "    │   Blocked countries: [$countries]" -ForegroundColor DarkGray
                }
            }
        }
    } else {
        Write-Host "  ⚠ No custom rules found. Geo-filtering may not be enabled." -ForegroundColor DarkYellow
    }

    Write-Host ""
    Write-Host "  Managed rule sets:" -ForegroundColor White
    foreach ($rs in $wafPolicy.managedRules.managedRuleSets) {
        Write-Host "    ├── $($rs.ruleSetType) v$($rs.ruleSetVersion)" -ForegroundColor DarkGray
    }
    Write-Host "    └── These apply to ALL traffic (internet + VPN)" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Could not read WAF policy: $($_.Exception.Message)" -ForegroundColor Red
}

# ═══════════════════════════════════════════════════════════════
# METHOD 2: Internet Access Test (from allowed country)
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ Method 2: Internet Access Test ━━━" -ForegroundColor Yellow
Write-Host "Sending request through App Gateway public IP ...`n"

try {
    $response = Invoke-RestMethod -Uri "http://$appGwPip" -TimeoutSec 30 -Headers @{
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    }
    Write-Host "  ✓ Response received (HTTP 200) — your country is in the allow list!" -ForegroundColor Green

    $xff = if ($response.headers.'x-forwarded-for') { $response.headers.'x-forwarded-for' }
           elseif ($response.headers.'X-Forwarded-For') { $response.headers.'X-Forwarded-For' }
           else { 'not found' }
    Write-Host "  X-Forwarded-For: $xff (your real IP)" -ForegroundColor DarkGray
}
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 403) {
        Write-Host "  ✓ Request blocked with 403 — your country is NOT in the allow list!" -ForegroundColor Magenta
        Write-Host "  This proves geo-filtering is working correctly." -ForegroundColor Magenta
    } else {
        Write-Host "  ✗ Request failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ═══════════════════════════════════════════════════════════════
# METHOD 3: WAF Managed Rules Test (SQL Injection)
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ Method 3: WAF Managed Rules Test (SQL Injection) ━━━" -ForegroundColor Yellow
Write-Host "Sending SQL injection payload — should be blocked by OWASP 3.2 ...`n"

try {
    $sqliResponse = Invoke-WebRequest -Uri "http://$appGwPip/?id=1'%20OR%20'1'='1" `
        -Headers @{ "User-Agent" = "Mozilla/5.0" } `
        -TimeoutSec 30 -ErrorAction Stop
    Write-Host "  ⚠ Request was NOT blocked (HTTP $($sqliResponse.StatusCode))" -ForegroundColor DarkYellow
    Write-Host "  WAF may be in Detection mode. Switch to Prevention for blocking." -ForegroundColor DarkYellow
}
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 403) {
        Write-Host "  ✓ SQL injection BLOCKED (HTTP 403) — managed rules are protecting!" -ForegroundColor Green
        Write-Host "  This proves OWASP 3.2 managed rules apply to internet traffic." -ForegroundColor DarkGray
        Write-Host "  The same managed rules also apply to VPN traffic (only geo-block is bypassed)." -ForegroundColor DarkGray
    } else {
        Write-Host "  Response: HTTP $statusCode — $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

# ═══════════════════════════════════════════════════════════════
# METHOD 4: WAF Custom Rule Logs (Log Analytics)
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ Method 4: WAF Custom Rule + Geo-Block Logs ━━━" -ForegroundColor Yellow
Write-Host "Note: Logs may take 5-10 minutes to appear after requests.`n"

$wafLogQuery = @"
AzureDiagnostics
| where Category == "ApplicationGatewayFirewallLog"
| project TimeGenerated, clientIp_s, ruleId_s, ruleGroup_s, action_s, Message
| order by TimeGenerated desc
| take 10
"@

try {
    $logs = az monitor log-analytics query -w $workspaceId --analytics-query $wafLogQuery -o table 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host $logs
        Write-Host "`n  → Look for ruleId_s values:" -ForegroundColor Green
        Write-Host "    • Custom rules: AllowVpnCorporateClients, GeoBlockNonAllowedCountries" -ForegroundColor DarkGray
        Write-Host "    • Managed rules: 942100 (SQLi), 941100 (XSS), etc." -ForegroundColor DarkGray
    } else {
        Write-Host "  No WAF logs available yet. Wait 5-10 minutes and re-run." -ForegroundColor DarkYellow
    }
}
catch {
    Write-Host "  Could not query logs: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# ═══════════════════════════════════════════════════════════════
# METHOD 5: VPN Access Instructions
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ Method 5: VPN Access Testing ━━━" -ForegroundColor Yellow

$vpnGwExists = az network vnet-gateway show -g $ResourceGroupName -n "$AppName-vpngw" --query name -o tsv 2>$null
if ($vpnGwExists) {
    $appGwPrivateIp = az network application-gateway show `
        -g $ResourceGroupName -n "$AppName-appgw" `
        --query "frontendIPConfigurations[?name=='appGwPrivateFrontendIp'].privateIPAddress" `
        -o tsv 2>$null

    Write-Host "  VPN Gateway detected! Follow these steps to test:`n" -ForegroundColor Green
    Write-Host "  1. Download VPN client configuration:" -ForegroundColor White
    Write-Host "     az network vnet-gateway vpn-client generate -g $ResourceGroupName -n $AppName-vpngw -o tsv" -ForegroundColor DarkGray
    Write-Host "  2. Import the OpenVPN profile and connect" -ForegroundColor White
    Write-Host "  3. Access the App Gateway private frontend:" -ForegroundColor White
    Write-Host "     curl http://$appGwPrivateIp" -ForegroundColor DarkGray
    Write-Host "     → Should return 200 with headers (VPN IP allowed by custom rule)" -ForegroundColor DarkGray
    Write-Host "  4. Test SQL injection from VPN:" -ForegroundColor White
    Write-Host "     curl `"http://$appGwPrivateIp/?id=1' OR '1'='1`"" -ForegroundColor DarkGray
    Write-Host "     → Should return 403 (OWASP managed rules still protect VPN traffic)" -ForegroundColor DarkGray
} else {
    Write-Host "  VPN Gateway not deployed. To enable, re-deploy with:" -ForegroundColor DarkYellow
    Write-Host "  .\deploy.ps1 -ResourceGroupName $ResourceGroupName -DeployVpnGateway `$true" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Without VPN Gateway, you can still verify:" -ForegroundColor White
    Write-Host "  • Geo-filtering works (Methods 1-4 above)" -ForegroundColor DarkGray
    Write-Host "  • WAF custom rules are configured correctly (Method 1)" -ForegroundColor DarkGray
    Write-Host "  • Managed rules protect all traffic (Method 3)" -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════
Write-Host "`n╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  How Geofencing + VPN Security Works                   ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║                                                        ║" -ForegroundColor Cyan
Write-Host "║  WAF Custom Rules (evaluated first, by priority):      ║" -ForegroundColor Cyan
Write-Host "║   P5: Allow VPN/corp IPs → skip geo-block             ║" -ForegroundColor Cyan
Write-Host "║   P10: Geo-block non-allowed countries                 ║" -ForegroundColor Cyan
Write-Host "║                                                        ║" -ForegroundColor Cyan
Write-Host "║  WAF Managed Rules (always evaluated after Allow):     ║" -ForegroundColor Cyan
Write-Host "║   OWASP 3.2: SQLi, XSS, RCE, LFI protection       ✓  ║" -ForegroundColor Green
Write-Host "║   Bot Manager 1.0: Bot detection                   ✓  ║" -ForegroundColor Green
Write-Host "║                                                        ║" -ForegroundColor Cyan
Write-Host "║  Internet from allowed country → Allow → Managed    ✓  ║" -ForegroundColor Green
Write-Host "║  Internet from blocked country → BLOCKED            ✓  ║" -ForegroundColor Green
Write-Host "║  VPN client (any country)      → Allow → Managed    ✓  ║" -ForegroundColor Green
Write-Host "║  VPN + SQL injection           → Allow → BLOCKED    ✓  ║" -ForegroundColor Green
Write-Host "║                                                        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
