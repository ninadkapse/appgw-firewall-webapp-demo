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
