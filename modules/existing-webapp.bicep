@description('Location for all resources')
param location string

@description('Application name prefix')
param appName string

@description('Virtual Network resource ID')
param vnetId string

@description('Subnet ID for the private endpoint')
param privateEndpointSubnetId string

@description('Name of the existing Web App')
param existingWebAppName string

@description('Resource group of the existing Web App')
param existingWebAppResourceGroup string

// ─── Reference existing Web App (cross-resource-group) ──────
resource existingWebApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: existingWebAppName
  scope: resourceGroup(existingWebAppResourceGroup)
}

// ─── Private Endpoint for existing Web App ──────────────────
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
          privateLinkServiceId: existingWebApp.id
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
output webAppDefaultHostName string = existingWebApp.properties.defaultHostName
output webAppName string = existingWebApp.name
output privateEndpointId string = privateEndpoint.id
