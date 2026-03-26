@description('Name of the existing route table to update')
param routeTableName string

@description('Azure Firewall private IP address (next hop)')
param firewallPrivateIp string

@description('Private Endpoint subnet CIDR (destination)')
param privateEndpointSubnetPrefix string

resource routeTable 'Microsoft.Network/routeTables@2023-11-01' existing = {
  name: routeTableName
}

// Forces traffic destined for the Web App private endpoint through Azure Firewall
resource routeToWebApp 'Microsoft.Network/routeTables/routes@2023-11-01' = {
  parent: routeTable
  name: 'to-webapp-via-firewall'
  properties: {
    addressPrefix: privateEndpointSubnetPrefix
    nextHopType: 'VirtualAppliance'
    nextHopIpAddress: firewallPrivateIp
  }
}
