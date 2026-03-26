@description('Location for all resources')
param location string

@description('Application name prefix')
param appName string

@description('App Service Plan SKU')
param appServicePlanSku string

@description('Virtual Network resource ID')
param vnetId string

@description('Subnet ID for App Service VNet integration')
param appServiceSubnetId string

@description('Subnet ID for the private endpoint')
param privateEndpointSubnetId string

@description('Deploy the header-echo demo container (set false for production workloads)')
param deployDemoApp bool = true

var webAppName = '${appName}-webapp-${uniqueString(resourceGroup().id)}'
var appServicePlanName = '${appName}-asp'

// ─── App Service Plan ───────────────────────────────────────
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: appServicePlanSku
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// ─── Web App ────────────────────────────────────────────────
// Public network access is disabled — only reachable via private endpoint
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    virtualNetworkSubnetId: appServiceSubnetId
    siteConfig: {
      // Demo mode: header-echo container shows X-Forwarded-For instantly
      // Production: .NET 8 with forwarded headers middleware enabled
      linuxFxVersion: deployDemoApp ? 'DOCKER|mendhak/http-https-echo:latest' : 'DOTNETCORE|8.0'
      alwaysOn: true
      ftpsState: 'Disabled'
      appSettings: deployDemoApp
        ? [
            { name: 'WEBSITES_PORT', value: '8080' }
          ]
        : [
            { name: 'ASPNETCORE_FORWARDEDHEADERS_ENABLED', value: 'true' }
          ]
      ipSecurityRestrictionsDefaultAction: 'Deny'
      scmIpSecurityRestrictionsDefaultAction: 'Deny'
    }
    publicNetworkAccess: 'Disabled'
  }
}

// ─── Private Endpoint ───────────────────────────────────────
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${appName}-webapp-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${appName}-webapp-pe-connection'
        properties: {
          privateLinkServiceId: webApp.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }
}

// ─── Private DNS Zone ───────────────────────────────────────
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
}

// ─── VNet Link — allows resources in the VNet to resolve private DNS ─
resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${appName}-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// ─── DNS Zone Group — auto-registers PE IP in the private DNS zone ──
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurewebsites-net'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// ─── Outputs ────────────────────────────────────────────────
output webAppDefaultHostName string = webApp.properties.defaultHostName
output webAppName string = webApp.name
output privateEndpointId string = privateEndpoint.id
