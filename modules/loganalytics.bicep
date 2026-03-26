@description('Location for all resources')
param location string

@description('Application name prefix')
param appName string

@description('Name of the Application Gateway (for diagnostic settings)')
param appGatewayName string

@description('Name of the Azure Firewall (for diagnostic settings)')
param firewallName string

// ─── Log Analytics Workspace ────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${appName}-law'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ─── App Gateway Diagnostic Settings ────────────────────────
// Captures access logs with client IP and X-Forwarded-For data
resource appGw 'Microsoft.Network/applicationGateways@2023-11-01' existing = {
  name: appGatewayName
}

resource appGwDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'appgw-diagnostics'
  scope: appGw
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ─── Azure Firewall Diagnostic Settings ─────────────────────
// Captures network rule logs, IDPS signature hits, and SNAT info
resource fw 'Microsoft.Network/azureFirewalls@2023-11-01' existing = {
  name: firewallName
}

resource fwDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'firewall-diagnostics'
  scope: fw
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ─── Outputs ────────────────────────────────────────────────
output workspaceId string = logAnalytics.id
output workspaceCustomerId string = logAnalytics.properties.customerId
output workspaceName string = logAnalytics.name
