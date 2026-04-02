// ╔══════════════════════════════════════════════════════════════╗
// ║  App Gateway (WAF) → Azure Firewall → Web App (Private)    ║
// ║                                                            ║
// ║  Client IP is preserved in X-Forwarded-For by App Gateway. ║
// ║  Azure Firewall SNATs traffic for symmetric routing.       ║
// ║  Web App is reachable only via private endpoint.           ║
// ╚══════════════════════════════════════════════════════════════╝

targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = 'westus2'

@description('Prefix used to name every resource')
param appName string = 'demoapp'

@description('WAF operating mode')
@allowed([
  'Detection'
  'Prevention'
])
param wafMode string = 'Prevention'

@description('App Service Plan SKU (P1v3 for Premium V3)')
param appServicePlanSku string = 'P1v3'

@description('Deploy the header-echo demo container (set false for production workloads)')
param deployDemoApp bool = true

@description('Deploy VPN Gateway for P2S VPN demo (adds ~30 min deployment, ~$0.19/hr cost)')
param deployVpnGateway bool = false

@description('Enable geo-filtering WAF custom rules')
param enableGeoFiltering bool = true

@description('Country codes allowed through geo-filter (ISO 3166-1 alpha-2)')
param allowedCountryCodes array = [
  'US'
]

@description('VPN client address pool CIDR')
param vpnAddressPool string = '172.16.0.0/24'

@secure()
@description('Base64-encoded VPN root certificate public key (required when deployVpnGateway is true)')
param vpnRootCertData string = ''

// ─── 1. Networking (VNet, subnets, NSGs, route table shell) ─
module networking 'modules/networking.bicep' = {
  name: 'networking-deployment'
  params: {
    location: location
    appName: appName
  }
}

// ─── 2. Azure Firewall Premium ──────────────────────────────
module firewall 'modules/firewall.bicep' = {
  name: 'firewall-deployment'
  params: {
    location: location
    appName: appName
    firewallSubnetId: networking.outputs.firewallSubnetId
    appGatewaySubnetPrefix: networking.outputs.appGatewaySubnetPrefix
    privateEndpointSubnetPrefix: networking.outputs.privateEndpointSubnetPrefix
  }
}

// ─── 3. New Web App + Private Endpoint + DNS ────────────────
module webapp 'modules/webapp.bicep' = {
  name: 'webapp-deployment'
  params: {
    location: location
    appName: appName
    appServicePlanSku: appServicePlanSku
    vnetId: networking.outputs.vnetId
    appServiceSubnetId: networking.outputs.appServiceSubnetId
    privateEndpointSubnetId: networking.outputs.privateEndpointSubnetId
    deployDemoApp: deployDemoApp
  }
}

// ─── 4. UDR: route PE subnet traffic through the firewall ───
module routes 'modules/routes.bicep' = {
  name: 'routes-deployment'
  params: {
    routeTableName: networking.outputs.appGwRouteTableName
    firewallPrivateIp: firewall.outputs.firewallPrivateIp
    privateEndpointSubnetPrefix: networking.outputs.privateEndpointSubnetPrefix
  }
}

// ─── 5. Application Gateway with WAF ────────────────────────
module appgateway 'modules/appgateway.bicep' = {
  name: 'appgateway-deployment'
  params: {
    location: location
    appName: appName
    appGatewaySubnetId: networking.outputs.appGatewaySubnetId
    backendFqdn: webapp.outputs.webAppDefaultHostName
    wafMode: wafMode
    enableGeoFiltering: enableGeoFiltering
    allowedCountryCodes: allowedCountryCodes
    vpnAddressPool: vpnAddressPool
  }
  dependsOn: [
    routes
  ]
}

// ─── 6. Log Analytics + Diagnostic Settings ─────────────────
module loganalytics 'modules/loganalytics.bicep' = {
  name: 'loganalytics-deployment'
  params: {
    location: location
    appName: appName
    appGatewayName: appgateway.outputs.appGatewayName
    firewallName: firewall.outputs.firewallName
  }
}

// ─── 7. VPN Gateway (optional — for P2S VPN demo) ───────────
module vpngateway 'modules/vpngateway.bicep' = if (deployVpnGateway) {
  name: 'vpngateway-deployment'
  params: {
    location: location
    appName: appName
    gatewaySubnetId: networking.outputs.gatewaySubnetId
    vpnAddressPool: vpnAddressPool
    vpnRootCertData: vpnRootCertData
  }
}

// ─── Outputs ────────────────────────────────────────────────
output appGatewayPublicIp string = appgateway.outputs.appGatewayPublicIp
output appGatewayPrivateIp string = appgateway.outputs.appGatewayPrivateIp
output webAppHostName string = webapp.outputs.webAppDefaultHostName
output webAppName string = webapp.outputs.webAppName
output firewallPrivateIp string = firewall.outputs.firewallPrivateIp
output logAnalyticsWorkspaceId string = loganalytics.outputs.workspaceCustomerId
output vpnGatewayPublicIp string = deployVpnGateway ? vpngateway.outputs.vpnGatewayPublicIp : 'not deployed'
