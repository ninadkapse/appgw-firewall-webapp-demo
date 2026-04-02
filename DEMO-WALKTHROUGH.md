# Demo Walkthrough: X-Forwarded-For Header Preservation

## App Gateway (WAF) → Azure Firewall → Web App

> **Microsoft Reference:** [Azure Firewall and Application Gateway for virtual networks](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/gateway/firewall-application-gateway)

---

## Architecture Overview

```
┌──────────┐     ┌─────────────────────┐     ┌──────────────────┐     ┌─────────────────────────┐
│ Internet │────▶│ App Gateway (WAF_v2)│────▶│ Azure Firewall   │────▶│ Web App (Private EP)    │
│  Client  │     │ Adds X-Forwarded-For│     │ Premium + IDPS   │     │ No public access        │
│          │     │                     │     │ SNATs traffic    │     │ Reads X-Forwarded-For   │
└──────────┘     └─────────────────────┘     └──────────────────┘     └─────────────────────────┘
```

**Key Point:** The Web App sees *your original IP* in the `X-Forwarded-For` header,
even though Azure Firewall SNAT'd the traffic (changed the network source IP).

---

## Prerequisites

After deploying with `deploy.ps1`, note these values from the output:

| Value | How to Get It |
|-------|---------------|
| `APP_GATEWAY_PIP` | Deployment output: `App Gateway Public IP` |
| `WEBAPP_NAME` | Deployment output: `Web App Name` |
| `RESOURCE_GROUP` | The `-ResourceGroupName` you used in `deploy.ps1` |

---

## Demo Steps

### Step 1 — Show the Web App Is NOT Directly Accessible

```powershell
curl https://<WEBAPP_NAME>.azurewebsites.net
```

**Expected:** `403 Forbidden` — public access is disabled.
The web app is only reachable through the private endpoint inside the VNet.

---

### Step 2 — Access the Web App Through the App Gateway

```powershell
Invoke-RestMethod -Uri "http://<APP_GATEWAY_PIP>" -Headers @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    "Accept"     = "application/json"
}
```

Or from any browser: `http://<APP_GATEWAY_PIP>`

**Expected:** A JSON response showing all HTTP headers the Web App received.

---

### Step 3 — Identify X-Forwarded-For in the Response

In the JSON response, look for these key headers:

| Header | What It Proves |
|--------|----------------|
| `x-forwarded-for` | **Your real public IP** — preserved by App Gateway |
| `x-original-host` | Traffic entered via the App Gateway public IP |
| `x-client-ip` | App Gateway's internal subnet IP (not your real IP) |
| `x-appgw-trace-id` | Confirms request was processed by App Gateway WAF |

**Key takeaway:**
- `x-forwarded-for` first value = **your real public IP**
- `x-client-ip` = the App Gateway's internal IP — proves Firewall SNAT'd the traffic
- The original IP is preserved in the HTTP header, not the network layer

---

### Step 4 — Verify from a Different Source IP

Test from a different location to prove it captures *each caller's* IP:
- Use your mobile phone's browser
- Use Azure Cloud Shell: `curl http://<APP_GATEWAY_PIP>`
- Ask a colleague to hit the same URL

Each request will show a **different** `x-forwarded-for` value.

---

### Step 5 — Check App Gateway Access Logs (Log Analytics)

Go to **Azure Portal** → **Log Analytics workspace** (`<appName>-law`)
→ **Logs** → Run this query:

```kusto
AzureDiagnostics
| where ResourceType == "APPLICATIONGATEWAYS"
| where Category == "ApplicationGatewayAccessLog"
| project TimeGenerated, clientIP_s, host_s, requestUri_s, httpMethod_s, httpStatus_d
| order by TimeGenerated desc
| take 10
```

**Expected:** `clientIP_s` shows each caller's real public IP address.

> **Note:** Logs may take 5–10 minutes to appear after the first request.

---

### Step 6 — Check Azure Firewall Logs (Proof of Inspection)

In the same Log Analytics workspace, run:

```kusto
AZFWNetworkRule
| project TimeGenerated, SourceIp, DestinationIp, DestinationPort, Protocol, Action
| order by TimeGenerated desc
| take 10
```

**Expected:** Log entries showing traffic from the App Gateway subnet being allowed
to the Private Endpoint subnet on port 443. This confirms Azure Firewall inspected
and forwarded the traffic.

> **Note:** Firewall logs can take 15–30 minutes to appear after deployment.

---

### Step 7 — Show WAF Protection (Bonus)

Trigger a WAF rule by sending a simulated SQL injection:

```powershell
Invoke-WebRequest -Uri "http://<APP_GATEWAY_PIP>/?id=1' OR '1'='1" -Headers @{
    "User-Agent" = "Mozilla/5.0"
} -ErrorAction SilentlyContinue
```

**Expected:** `403 Forbidden` — the WAF blocked the malicious request.

Check the WAF log:
```kusto
AzureDiagnostics
| where Category == "ApplicationGatewayFirewallLog"
| project TimeGenerated, clientIp_s, ruleId_s, action_s, Message
| order by TimeGenerated desc
| take 5
```

---

## Automated Verification

Run the included script for a one-command verification:

```powershell
.\verify-xff.ps1 -ResourceGroupName "<your-resource-group>"
```

---

## Resource Summary

All resource names are derived from the `appName` parameter (default: `demoapp`):

| Resource | Name Pattern |
|----------|-------------|
| Resource Group | `<your-resource-group>` |
| Application Gateway | `<appName>-appgw` |
| WAF Policy | `<appName>-waf-policy` |
| Azure Firewall | `<appName>-fw` |
| Firewall Policy | `<appName>-fw-policy` |
| Virtual Network | `<appName>-vnet` |
| Web App | `<appName>-webapp-<uniqueString>` |
| Private Endpoint | `<appName>-webapp-pe` |
| Log Analytics | `<appName>-law` |

---

## Why This Architecture?

| Requirement | How It's Achieved |
|-------------|-------------------|
| Preserve original client IP | App Gateway adds `X-Forwarded-For` header before forwarding |
| Deep packet inspection | Azure Firewall Premium with IDPS inspects all traffic |
| Web App not accessible from internet | Private Endpoint only — `publicNetworkAccess: Disabled` |
| WAF protection | App Gateway WAF_v2 with OWASP 3.2 rules in Prevention mode |
| Symmetric routing | Firewall SNAT on private traffic ensures return path matches |
| Audit trail | Log Analytics captures App Gateway access logs + Firewall logs |

---

## Use Case 2: Geofencing + VPN Bypass Security

> **Problem:** When applying geofencing rules on WAF, VPN users get private IPs that
> cannot be geo-resolved — bypassing geo-restrictions. We need VPN users to still be
> protected by WAF managed rules while exempting them from geo-blocks.

> **Microsoft Reference:**
> - [Azure WAF Geomatch Custom Rules](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/geomatch-custom-rules)
> - [WAF Custom Rules Overview](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/custom-waf-rules-overview)
> - [WAF Best Practices](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/best-practices)
> - [Geomatch Custom Rules Examples](https://learn.microsoft.com/en-us/azure/web-application-firewall/geomatch-custom-rules-examples)

### Architecture

```
┌──────────────┐                    ┌─────────────────────────────────────────┐
│  Internet    │───────────────────▶│ App Gateway (WAF_v2)                    │
│  Client      │  Public Frontend   │ ┌─────────────────────────────────────┐ │
└──────────────┘                    │ │ WAF Custom Rule (compound Block):   │ │
                                    │ │  Block if:                          │ │
┌──────────────┐     ┌──────────┐  │ │   GeoMatch NOT IN [allowed]  AND   │ │
│  VPN Client  │────▶│ VPN GW   │──▶│ │   IPMatch NOT IN [VPN/internal]    │ │
│  (VPN Pool)  │     │ (P2S)    │  │ │ Managed Rules:                      │ │
└──────────────┘     └──────────┘  │ │  OWASP 3.2 + Bot Manager (always)  │ │
                    Private Frontend│ └─────────────────────────────────────┘ │
                                    └────────────────┬────────────────────────┘
                                                     ▼
                                    ┌──────────────────┐     ┌──────────────────┐
                                    │ Azure Firewall   │────▶│ Web App (PE)     │
                                    │ Premium + IDPS   │     │ No public access │
                                    └──────────────────┘     └──────────────────┘
```

### The Solution: Single Compound Block Rule

> ⚠️ **Common Mistake:** Using a separate "Allow" rule for VPN IPs causes WAF to skip
> ALL subsequent rules **including managed rules (OWASP)**. This means VPN traffic would
> have zero protection against SQL injection, XSS, etc.

**Correct approach:** A single compound **Block** rule with two AND conditions:

```
Rule: GeoBlockExcludeVpn  (Priority 10, Action: Block)
  Condition 1 (AND): GeoMatch  NOT IN  [allowed country codes]
  Condition 2 (AND): IPMatch   NOT IN  [VPN address pool, internal ranges]
```

When the rule doesn't fire (because either condition is FALSE), traffic falls through
to managed rules (OWASP 3.2 + Bot Manager) for full L7 protection.

### Traffic Flow Summary

| Source | Cond 1 (NOT allowed geo?) | Cond 2 (NOT VPN IP?) | Rule Fires? | Managed Rules | Result |
|--------|--------------------------|---------------------|-------------|---------------|--------|
| Internet (allowed country) | ❌ FALSE | — | NO | ✅ Evaluated | 200 OK |
| Internet (blocked country) | ✅ TRUE | ✅ TRUE | YES → Block | N/A | 403 Forbidden |
| VPN client (normal) | ✅ TRUE | ❌ FALSE | NO | ✅ Evaluated | 200 OK |
| VPN + SQL injection | ✅ TRUE | ❌ FALSE | NO | ❌ OWASP blocks | 403 Forbidden |

---

### Demo Steps: Geofencing + VPN

#### Step 8 — Verify WAF Custom Rule Is Deployed

```powershell
az network application-gateway waf-policy show `
    -g <RESOURCE_GROUP> -n <appName>-waf-policy `
    --query "customRules[].{Name:name, Priority:priority, Action:action}" `
    -o table
```

**Expected:**
```
Name                  Priority    Action
--------------------  ----------  --------
GeoBlockExcludeVpn    10          Block
```

(Single compound rule with two match conditions — verify via Azure Portal → Custom Rules)

---

#### Step 9 — Test Geo-Filtering (Internet Access)

From your local machine (in an allowed country):

```powershell
# Should succeed — your country is in the allow list
Invoke-RestMethod -Uri "http://<APP_GATEWAY_PIP>"
```

**Expected:** HTTP 200 with JSON echo response.

To verify geo-blocking, check WAF logs after a request from a non-allowed region
(or temporarily remove your country from the allow list):

```kusto
AzureDiagnostics
| where Category == "ApplicationGatewayFirewallLog"
| where action_s == "Blocked"
| project TimeGenerated, clientIp_s, ruleId_s, action_s, Message
| order by TimeGenerated desc
| take 5
```

---

#### Step 10 — Prove Managed Rules Still Protect VPN Traffic

Send a SQL injection from VPN (via App Gateway private frontend):

```powershell
# OWASP managed rules should block this — compound rule does NOT fire for VPN IPs
Invoke-WebRequest -Uri "http://<APP_GATEWAY_PRIVATE_IP>/?id=1' OR '1'='1" -ErrorAction SilentlyContinue
```

**Expected:** `403 Forbidden` — OWASP 3.2 blocked the SQL injection.

This proves that the compound Block rule correctly exempts VPN traffic while
managed rules continue to evaluate.

---

#### Step 11 — Test VPN Access (Requires VPN Gateway)

If deployed with `-DeployVpnGateway $true`:

```powershell
# 1. Download and install VPN client
az network vnet-gateway vpn-client generate `
    -g <RESOURCE_GROUP> -n <appName>-vpngw -o tsv

# 2. Connect to P2S VPN via Azure VPN Client

# 3. Access via App Gateway private frontend
curl http://<APP_GATEWAY_PRIVATE_IP>

# 4. Verify SQL injection is still blocked from VPN
curl "http://<APP_GATEWAY_PRIVATE_IP>/?id=1' OR '1'='1"
```

**Expected:**
- Step 3: HTTP 200 — VPN client exempted by compound rule (Cond 2 = FALSE)
- Step 4: HTTP 403 — OWASP managed rules still protect VPN traffic

---

#### Step 12 — Check WAF Logs for Both Rule Types

```kusto
AzureDiagnostics
| where Category == "ApplicationGatewayFirewallLog"
| extend RuleType = case(
    ruleId_s startswith "Geo", "Custom Rule",
    "Managed Rule"
  )
| project TimeGenerated, clientIp_s, RuleType, ruleId_s, action_s, Message
| order by TimeGenerated desc
| take 20
```

---

### Automated Geofencing Verification

Run the included script for comprehensive verification:

```powershell
.\test-geofencing-vpn.ps1 -ResourceGroupName "<your-resource-group>"
```
